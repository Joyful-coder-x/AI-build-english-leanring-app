package com.example.firsttest.ui.level

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.LevelPracticeQuestion
import com.example.firsttest.data.repository.SessionUserRepository
import com.example.firsttest.data.repository.VocabRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// ---- UI states --------------------------------------------------------------

sealed interface LevelPracticeUiState {

    data object Loading : LevelPracticeUiState

    data class Answering(
        val question: LevelPracticeQuestion,
        val questionIndex: Int,
        val totalQuestions: Int,
        val comboCount: Int,
        val selectedOptionId: String? = null,
        val typedAnswer: String = "",
        val questionStartMs: Long = System.currentTimeMillis(),
        val isSubmitting: Boolean = false,
    ) : LevelPracticeUiState {
        val submitEnabled: Boolean get() = !isSubmitting && when (question.answerForm) {
            "keyboard" -> typedAnswer.isNotBlank()
            else -> selectedOptionId != null
        }
    }

    data class Reviewing(
        val question: LevelPracticeQuestion,
        val questionIndex: Int,
        val totalQuestions: Int,
        val submittedAnswer: String,   // option id or typed text
        val correctOptionId: String?,  // option questions
        val correctAnswer: String?,    // cloze questions
        val answerOutcome: String,     // "full_correct" | "assisted_correct" | "remediation_completed" | "wrong"
        val comboCount: Int,
    ) : LevelPracticeUiState {
        val isCorrect: Boolean get() = answerOutcome == "full_correct" || answerOutcome == "assisted_correct"
    }

    data class Finished(
        val correctCount: Int,
        val totalCount: Int,
        val starRating: Int,
        val duckPowerEarned: Int,
    ) : LevelPracticeUiState

    data class Error(val message: String) : LevelPracticeUiState
}

// ---- ViewModel --------------------------------------------------------------

class LevelPracticeViewModel(
    private val vocabRepository: VocabRepository,
    private val userRepository: SessionUserRepository,
    private val levelNumber: Int,
) : ViewModel() {

    private val _uiState = MutableStateFlow<LevelPracticeUiState>(LevelPracticeUiState.Loading)
    val uiState: StateFlow<LevelPracticeUiState> = _uiState.asStateFlow()

    private var questions: List<LevelPracticeQuestion> = emptyList()
    private var roundId: String = ""
    private var comboCount = 0
    private var awaitingCompletion = false

    init { load() }

    fun retry() {
        if (awaitingCompletion) finishRound() else load()
    }

    private fun load() {
        _uiState.value = LevelPracticeUiState.Loading
        viewModelScope.launch {
            try {
                val round = vocabRepository.startLevelPracticeRound(levelNumber)
                roundId = round.roundId
                questions = round.questions
                _uiState.value = if (questions.isNotEmpty()) buildAnswering(0)
                                 else LevelPracticeUiState.Error("该关卡暂无题目，请稍后重试")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = LevelPracticeUiState.Error(e.message ?: "加载题目失败，请重试")
            }
        }
    }

    fun onOptionSelected(optionId: String) {
        val s = _uiState.value as? LevelPracticeUiState.Answering ?: return
        _uiState.value = s.copy(selectedOptionId = optionId)
    }

    fun onTypedAnswerChanged(text: String) {
        val s = _uiState.value as? LevelPracticeUiState.Answering ?: return
        _uiState.value = s.copy(typedAnswer = text)
    }

    fun onSubmit() {
        val s = _uiState.value as? LevelPracticeUiState.Answering ?: return
        val answer = when (s.question.answerForm) {
            "keyboard" -> s.typedAnswer.trim().ifBlank { return }
            else -> s.selectedOptionId ?: return
        }
        val responseMs = (System.currentTimeMillis() - s.questionStartMs).coerceAtLeast(0).toInt()
        _uiState.value = s.copy(isSubmitting = true)

        viewModelScope.launch {
            try {
                val result = vocabRepository.saveLevelPracticeAnswer(
                    roundId        = roundId,
                    position       = s.question.position,
                    answer         = answer,
                    responseTimeMs = responseMs,
                )
                // Only full_correct continues combo; everything else breaks it.
                if (result.answerOutcome == "full_correct") comboCount++ else comboCount = 0

                _uiState.value = LevelPracticeUiState.Reviewing(
                    question        = s.question,
                    questionIndex   = s.questionIndex,
                    totalQuestions  = s.totalQuestions,
                    submittedAnswer = answer,
                    correctOptionId = result.correctOptionId,
                    correctAnswer   = result.correctAnswer,
                    answerOutcome   = result.answerOutcome,
                    comboCount      = comboCount,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = LevelPracticeUiState.Error(e.message ?: "保存答案失败，请重试")
            }
        }
    }

    fun onNext() {
        val s = _uiState.value as? LevelPracticeUiState.Reviewing ?: return
        val next = s.questionIndex + 1
        if (next < questions.size) {
            _uiState.value = buildAnswering(next)
        } else {
            awaitingCompletion = true
            finishRound()
        }
    }

    private fun finishRound() {
        _uiState.value = LevelPracticeUiState.Loading
        viewModelScope.launch {
            try {
                val result = vocabRepository.completePracticeRound(roundId)
                try {
                    userRepository.refreshCurrentUser()
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    // Round is safely completed on the server; profile refresh can retry later.
                }
                awaitingCompletion = false
                _uiState.value = LevelPracticeUiState.Finished(
                    correctCount    = result.correctCount,
                    totalCount      = result.questionCount,
                    starRating      = result.starRating,
                    duckPowerEarned = result.duckPowerEarned,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = LevelPracticeUiState.Error(e.message ?: "完成练习失败，请重试")
            }
        }
    }

    private fun buildAnswering(index: Int) = LevelPracticeUiState.Answering(
        question       = questions[index],
        questionIndex  = index,
        totalQuestions = questions.size,
        comboCount     = comboCount,
    )

    companion object {
        fun factory(levelNumber: Int) = viewModelFactory {
            initializer {
                LevelPracticeViewModel(
                    vocabRepository = AppRepositories.vocab,
                    userRepository  = AppRepositories.user,
                    levelNumber     = levelNumber,
                )
            }
        }
    }
}
