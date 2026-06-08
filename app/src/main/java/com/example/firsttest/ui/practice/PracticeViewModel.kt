package com.example.firsttest.ui.practice

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.Question
import com.example.firsttest.data.repository.PracticeRepository
import com.example.firsttest.data.repository.UserRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// ---- UI state ---------------------------------------------------------------

sealed interface PracticeUiState {
    data object Loading : PracticeUiState

    /**
     * User is actively answering.
     * [submitEnabled] is false until [currentAnswer] is non-blank.
     * Combo bonus (>5 consecutive correct → +1/correct, >10 → +2/correct from spec 2.2.3)
     * TODO PHASE 2: apply combo duck-power bonus in [calcDuckPower].
     */
    data class Answering(
        val question: Question,
        val questionIndex: Int,
        val totalQuestions: Int,
        val comboCount: Int,
        val currentAnswer: String = "",
    ) : PracticeUiState {
        val submitEnabled: Boolean get() = currentAnswer.isNotBlank()
    }

    /**
     * Answer submitted — result panel is visible.
     * Speed bonus (3★ within [Question.expectedTimeMs] → +5, spec 2.2.3):
     * TODO PHASE 2: add visible countdown in PracticeQuestionScreen and pass
     *   solveTimeMs here so [calcDuckPower] can apply the +5 bonus.
     */
    data class Reviewing(
        val question: Question,
        val questionIndex: Int,
        val totalQuestions: Int,
        val givenAnswer: String,
        val isCorrect: Boolean,
        val comboCount: Int,
    ) : PracticeUiState

    /** All questions answered — navigate to PracticeResultScreen. */
    data class Finished(
        val correctCount: Int,
        val totalCount: Int,
        val starRating: Int,
        val duckPowerEarned: Int,
    ) : PracticeUiState
}

// ---- ViewModel --------------------------------------------------------------

/**
 * Drives one practice session.
 *
 * Questions are loaded from [PracticeRepository] (real Supabase in production,
 * fake in tests). On [onNext] past the last question, [addDuckPower] is called
 * on [UserRepository] so the earned 鸭力值 immediately reflects in Profile and
 * Home via the shared [UserRepository.userFlow].
 *
 * Spec rules implemented:
 *   ✅ Stars by accuracy: <40% 0★, 40–65% 1★, 65–90% 2★, ≥90% 3★ (spec 2.2.3)
 *   ✅ Base duck power: +1 per correct, +5 bonus if all correct (spec 2.2.3)
 *   ✅ Combo counter displayed (spec 2.2.3)
 *   ✅ Level/EXP only shown going UP in UI (spec 2.2.1) — enforced in UserRepository
 *   TODO PHASE 2: combo duck-power bonus (>5 consecutive → +1/answer extra)
 *   TODO PHASE 2: speed bonus (+5 if 3★ within expectedTimeMs)
 *   TODO PHASE 3: persist session result to practice_sessions table in Supabase
 *   TODO PHASE 3: update card state (PRACTICED + starRating) in Supabase
 */
class PracticeViewModel(
    private val userRepository: UserRepository,
    private val practiceRepository: PracticeRepository,
    private val cardId: String,
) : ViewModel() {

    private val _uiState = MutableStateFlow<PracticeUiState>(PracticeUiState.Loading)
    val uiState: StateFlow<PracticeUiState> = _uiState.asStateFlow()

    private var questions: List<Question> = emptyList()
    private var correctCount = 0
    private var comboCount = 0
    // Extra duck power accumulated from combo bonuses this session (spec 2.2.3):
    // COMBO >5 correct → +1 per correct answer; COMBO >10 → +2 per correct answer.
    private var sessionComboBonus = 0

    init { load() }

    private fun load() {
        viewModelScope.launch {
            questions = practiceRepository.getQuestionsForCard(cardId)
            if (questions.isNotEmpty()) _uiState.value = buildAnswering(0)
        }
    }

    fun onAnswerChanged(answer: String) {
        val s = _uiState.value as? PracticeUiState.Answering ?: return
        _uiState.value = s.copy(currentAnswer = answer)
    }

    fun onSubmit() {
        val s = _uiState.value as? PracticeUiState.Answering ?: return
        val isCorrect = s.question.correctAnswer.trim().lowercase() ==
                s.currentAnswer.trim().lowercase()
        if (isCorrect) {
            correctCount++
            comboCount++
            // Combo bonus (spec 2.2.3): COMBO >5 → +1 extra; COMBO >10 → +2 extra.
            sessionComboBonus += when {
                comboCount > 10 -> 2
                comboCount > 5  -> 1
                else            -> 0
            }
        } else {
            comboCount = 0
        }
        _uiState.value = PracticeUiState.Reviewing(
            question       = s.question,
            questionIndex  = s.questionIndex,
            totalQuestions = s.totalQuestions,
            givenAnswer    = s.currentAnswer.trim(),
            isCorrect      = isCorrect,
            comboCount     = comboCount,
        )
    }

    fun onNext() {
        val s = _uiState.value as? PracticeUiState.Reviewing ?: return
        val next = s.questionIndex + 1
        if (next < questions.size) {
            _uiState.value = buildAnswering(next)
        } else {
            val earned = calcDuckPower(correctCount, questions.size) + sessionComboBonus
            // Persist duck power to the shared UserRepository immediately so
            // Profile and Home screens update as soon as the user returns.
            viewModelScope.launch { userRepository.addDuckPower(earned) }
            // TODO PHASE 3: also write to Supabase practice_sessions + level_progress.
            _uiState.value = PracticeUiState.Finished(
                correctCount    = correctCount,
                totalCount      = questions.size,
                starRating      = calcStars(correctCount, questions.size),
                duckPowerEarned = earned,
            )
        }
    }

    private fun buildAnswering(index: Int) = PracticeUiState.Answering(
        question       = questions[index],
        questionIndex  = index,
        totalQuestions = questions.size,
        comboCount     = comboCount,
    )

    companion object {
        fun factory(cardId: String) = viewModelFactory {
            initializer {
                PracticeViewModel(AppRepositories.user, AppRepositories.practice, cardId)
            }
        }
    }
}

// ---- Scoring helpers (spec 2.2.3) — internal so tests can import them ------

internal fun calcStars(correct: Int, total: Int): Int {
    if (total == 0) return 0
    return when {
        correct.toFloat() / total >= 0.90f -> 3
        correct.toFloat() / total >= 0.65f -> 2
        correct.toFloat() / total >= 0.40f -> 1
        else -> 0
    }
}

internal fun calcDuckPower(correct: Int, total: Int): Int =
    correct + if (correct == total && total > 0) 5 else 0
