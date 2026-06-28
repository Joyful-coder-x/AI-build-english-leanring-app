package com.example.firsttest.ui.practice

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.Question
import com.example.firsttest.data.repository.PracticeRepository
import com.example.firsttest.data.repository.UserRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// ---- Cloze result levels (type 3 only) --------------------------------------

enum class ClozeResult {
    FIRST_TRY_CORRECT,     // correct on first attempt — strong active recall
    HINT_CORRECT,          // correct after seeing letter-count hint
    MEMORY_RETYPE_CORRECT, // typed correctly only after the full word was shown
    WRONG,                 // failed even the memory retype
}

// ---- UI state ---------------------------------------------------------------

sealed interface PracticeUiState {
    data object Loading : PracticeUiState

    data class Answering(
        val question: Question,
        val questionIndex: Int,
        val totalQuestions: Int,
        val comboCount: Int,
        val currentAnswer: String = "",
        val questionStartMs: Long = System.currentTimeMillis(),
        // Type 3 progressive hint state:
        val clozeAttemptCount: Int = 0,
        val showLetterHint: Boolean = false,
        val nearMeaningFeedback: String? = null,
    ) : PracticeUiState {
        val submitEnabled: Boolean get() = currentAnswer.isNotBlank()
    }

    /** Type 3: briefly reveal the target word before memory retype. */
    data class ShowingClozeAnswer(
        val question: Question,
        val questionIndex: Int,
        val totalQuestions: Int,
        val comboCount: Int,
    ) : PracticeUiState

    /** Type 3: user types from memory after having seen the full word. */
    data class ClozeMemoryRetype(
        val question: Question,
        val questionIndex: Int,
        val totalQuestions: Int,
        val comboCount: Int,
        val currentAnswer: String = "",
    ) : PracticeUiState {
        val submitEnabled: Boolean get() = currentAnswer.isNotBlank()
    }

    data class Reviewing(
        val question: Question,
        val questionIndex: Int,
        val totalQuestions: Int,
        val givenAnswer: String,
        val isCorrect: Boolean,
        val comboCount: Int,
        val clozeResult: ClozeResult? = null, // non-null for type 3 questions
    ) : PracticeUiState

    /** All questions answered — navigate to PracticeResultScreen. */
    data class Finished(
        val correctCount: Int,
        val totalCount: Int,
        val starRating: Int,
        val duckPowerEarned: Int,
    ) : PracticeUiState

    /** Question load failed — shows message and a retry button. */
    data class Error(val message: String) : PracticeUiState
}

// ---- ViewModel --------------------------------------------------------------

/**
 * Drives one practice session.
 *
 * Spec rules implemented:
 *   ✅ Stars by accuracy: <40% 0★, 40–65% 1★, 65–90% 2★, ≥90% 3★ (spec 2.2.3)
 *   ✅ Base duck power: +1 per correct, +5 bonus if all correct (spec 2.2.3)
 *   ✅ Combo counter displayed (spec 2.2.3)
 *   ✅ Combo duck-power bonus (>5 consecutive → +1/answer extra)
 *   ✅ Speed bonus (+5 if 3★ within total expectedTimeMs across all questions)
 *   ✅ Streak check-in on ≥1★ result
 *   ✅ Type 3 (sentence_cloze_typing): progressive hints + memory retype
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
    private var sessionComboBonus = 0
    private var totalSolveMs: Long = 0

    init { load() }

    fun retry() { load() }

    private fun load() {
        _uiState.value = PracticeUiState.Loading
        viewModelScope.launch {
            try {
                questions = practiceRepository.getQuestionsForCard(cardId)
                _uiState.value = if (questions.isNotEmpty()) buildAnswering(0)
                                 else PracticeUiState.Error("没有找到题目，请稍后重试")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = PracticeUiState.Error(e.message ?: "加载题目失败，请重试")
            }
        }
    }

    fun onAnswerChanged(answer: String) {
        when (val s = _uiState.value) {
            is PracticeUiState.Answering -> _uiState.value = s.copy(currentAnswer = answer)
            is PracticeUiState.ClozeMemoryRetype -> _uiState.value = s.copy(currentAnswer = answer)
            else -> {}
        }
    }

    fun onSubmit() {
        when (val s = _uiState.value) {
            is PracticeUiState.Answering ->
                if (s.question.typeCode == 3) submitCloze(s) else submitNormal(s)
            is PracticeUiState.ClozeMemoryRetype -> submitMemoryRetype(s)
            else -> {}
        }
    }

    /** Called when user taps "I remember it" after seeing the revealed answer. */
    fun onClozeAnswerSeen() {
        val s = _uiState.value as? PracticeUiState.ShowingClozeAnswer ?: return
        _uiState.value = PracticeUiState.ClozeMemoryRetype(
            question       = s.question,
            questionIndex  = s.questionIndex,
            totalQuestions = s.totalQuestions,
            comboCount     = s.comboCount,
        )
    }

    fun onNext() {
        val s = _uiState.value as? PracticeUiState.Reviewing ?: return
        val next = s.questionIndex + 1
        if (next < questions.size) {
            _uiState.value = buildAnswering(next)
        } else {
            val stars = calcStars(correctCount, questions.size)
            val totalExpectedMs = questions.sumOf { it.expectedTimeMs.toLong() }
            val speedBonus = if (stars >= 3 && totalSolveMs <= totalExpectedMs) 5 else 0
            val earned = calcDuckPower(correctCount, questions.size) + sessionComboBonus + speedBonus
            viewModelScope.launch {
                userRepository.addDuckPower(earned)
                if (stars >= 1) userRepository.checkInToday()
                // TODO PHASE 3: write to Supabase practice_sessions + level_progress.
            }
            _uiState.value = PracticeUiState.Finished(
                correctCount    = correctCount,
                totalCount      = questions.size,
                starRating      = stars,
                duckPowerEarned = earned,
            )
        }
    }

    // ---- Submit helpers ------------------------------------------------------

    private fun submitNormal(s: PracticeUiState.Answering) {
        totalSolveMs += System.currentTimeMillis() - s.questionStartMs
        val isCorrect = s.question.correctAnswer.trim().lowercase() ==
                s.currentAnswer.trim().lowercase()
        if (isCorrect) {
            correctCount++
            comboCount++
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

    private fun submitCloze(s: PracticeUiState.Answering) {
        val given = s.currentAnswer.trim()
        val isCorrect = normalizeAnswer(given) == normalizeAnswer(s.question.correctAnswer)

        if (isCorrect) {
            totalSolveMs += System.currentTimeMillis() - s.questionStartMs
            val result = if (s.clozeAttemptCount == 0) ClozeResult.FIRST_TRY_CORRECT
                         else ClozeResult.HINT_CORRECT
            correctCount++
            comboCount++
            sessionComboBonus += when {
                comboCount > 10 -> 2
                comboCount > 5  -> 1
                else            -> 0
            }
            _uiState.value = PracticeUiState.Reviewing(
                question       = s.question,
                questionIndex  = s.questionIndex,
                totalQuestions = s.totalQuestions,
                givenAnswer    = given,
                isCorrect      = true,
                comboCount     = comboCount,
                clozeResult    = result,
            )
            return
        }

        // Near-meaning check: only on the first attempt (before the letter hint is shown)
        if (s.clozeAttemptCount == 0) {
            val isNearMeaning = s.question.nearMeaningAnswers.any {
                normalizeAnswer(it) == normalizeAnswer(given)
            }
            if (isNearMeaning) {
                _uiState.value = s.copy(
                    currentAnswer = "",
                    nearMeaningFeedback = "意思接近，但本题练的是本关目标词。\n再试一次。",
                )
                return
            }
        }

        if (s.clozeAttemptCount == 0) {
            // First wrong: show letter count, keep question open for attempt 2
            _uiState.value = s.copy(
                currentAnswer       = "",
                clozeAttemptCount   = 1,
                showLetterHint      = true,
                nearMeaningFeedback = null,
            )
        } else {
            // Second wrong: reveal the full word, then require memory retype
            totalSolveMs += System.currentTimeMillis() - s.questionStartMs
            comboCount = 0
            _uiState.value = PracticeUiState.ShowingClozeAnswer(
                question       = s.question,
                questionIndex  = s.questionIndex,
                totalQuestions = s.totalQuestions,
                comboCount     = comboCount,
            )
        }
    }

    private fun submitMemoryRetype(s: PracticeUiState.ClozeMemoryRetype) {
        val given = s.currentAnswer.trim()
        val isCorrect = normalizeAnswer(given) == normalizeAnswer(s.question.correctAnswer)
        // Memory retype never counts as session-correct (user already saw the answer)
        _uiState.value = PracticeUiState.Reviewing(
            question       = s.question,
            questionIndex  = s.questionIndex,
            totalQuestions = s.totalQuestions,
            givenAnswer    = given,
            isCorrect      = false,
            comboCount     = s.comboCount,
            clozeResult    = if (isCorrect) ClozeResult.MEMORY_RETYPE_CORRECT else ClozeResult.WRONG,
        )
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

internal fun normalizeAnswer(s: String): String =
    s.trim().lowercase().trimEnd('.')
