package com.example.firsttest.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.BandUpgradeExam
import com.example.firsttest.data.model.BandUpgradeQuestion
import com.example.firsttest.data.repository.VocabRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface BandUpgradeExamUiState {
    data object Loading : BandUpgradeExamUiState

    data class Answering(
        val exam: BandUpgradeExam,
        val question: BandUpgradeQuestion,
        val questionIndex: Int,
        val selectedOptionId: String? = null,
        val typedAnswer: String = "",
        val isSubmitting: Boolean = false,
        val questionStartMs: Long = System.currentTimeMillis(),
    ) : BandUpgradeExamUiState {
        val submitEnabled: Boolean get() = !isSubmitting && when (question.answerForm) {
            "keyboard" -> typedAnswer.isNotBlank()
            else -> selectedOptionId != null
        }
    }

    data class Result(val exam: BandUpgradeExam) : BandUpgradeExamUiState
    data class Error(val message: String) : BandUpgradeExamUiState
}

class BandUpgradeExamViewModel(
    private val vocabRepository: VocabRepository,
    private val targetBand: Double,
) : ViewModel() {

    private val _uiState = MutableStateFlow<BandUpgradeExamUiState>(BandUpgradeExamUiState.Loading)
    val uiState: StateFlow<BandUpgradeExamUiState> = _uiState.asStateFlow()

    private var exam: BandUpgradeExam? = null

    init {
        load()
    }

    fun retry() = load()

    private fun load() {
        _uiState.value = BandUpgradeExamUiState.Loading
        viewModelScope.launch {
            try {
                val loaded = vocabRepository.startBandUpgradeExam(targetBand)
                exam = loaded
                _uiState.value = if (loaded.status == "completed") {
                    BandUpgradeExamUiState.Result(loaded)
                } else {
                    buildAnswering(loaded.nextQuestionIndex())
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = BandUpgradeExamUiState.Error(
                    e.message ?: "Failed to load Band upgrade exam.",
                )
            }
        }
    }

    fun onOptionSelected(optionId: String) {
        val state = _uiState.value as? BandUpgradeExamUiState.Answering ?: return
        _uiState.value = state.copy(selectedOptionId = optionId)
    }

    fun onTypedAnswerChanged(text: String) {
        val state = _uiState.value as? BandUpgradeExamUiState.Answering ?: return
        _uiState.value = state.copy(typedAnswer = text)
    }

    fun onSubmit() {
        val state = _uiState.value as? BandUpgradeExamUiState.Answering ?: return
        val answer = when (state.question.answerForm) {
            "keyboard" -> state.typedAnswer.trim().ifBlank { return }
            else -> state.selectedOptionId ?: return
        }
        _uiState.value = state.copy(isSubmitting = true)
        viewModelScope.launch {
            try {
                vocabRepository.saveBandUpgradeAnswer(
                    attemptId = state.exam.attemptId,
                    position = state.question.position,
                    answer = answer,
                    responseTimeMs = elapsed(state.questionStartMs),
                )
                val updatedQuestions = state.exam.questions.map { question ->
                    if (question.position == state.question.position) {
                        question.copy(answered = true)
                    } else {
                        question
                    }
                }
                val updatedExam = state.exam.copy(questions = updatedQuestions)
                exam = updatedExam
                val nextIndex = state.questionIndex + 1
                if (nextIndex < updatedExam.questions.size) {
                    _uiState.value = buildAnswering(nextIndex)
                } else {
                    completeExam(updatedExam.attemptId)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = BandUpgradeExamUiState.Error(
                    e.message ?: "Failed to save exam answer.",
                )
            }
        }
    }

    private fun completeExam(attemptId: String) {
        _uiState.value = BandUpgradeExamUiState.Loading
        viewModelScope.launch {
            try {
                val completed = vocabRepository.completeBandUpgradeExam(attemptId)
                exam = completed
                _uiState.value = BandUpgradeExamUiState.Result(completed)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = BandUpgradeExamUiState.Error(
                    e.message ?: "Failed to complete Band upgrade exam.",
                )
            }
        }
    }

    private fun buildAnswering(index: Int): BandUpgradeExamUiState.Answering {
        val currentExam = requireNotNull(exam)
        val safeIndex = index.coerceIn(0, currentExam.questions.lastIndex)
        return BandUpgradeExamUiState.Answering(
            exam = currentExam,
            question = currentExam.questions[safeIndex],
            questionIndex = safeIndex,
        )
    }

    private fun BandUpgradeExam.nextQuestionIndex(): Int {
        val next = questions.indexOfFirst { !it.answered }
        return if (next >= 0) next else questions.lastIndex.coerceAtLeast(0)
    }

    private fun elapsed(startMs: Long): Int =
        (System.currentTimeMillis() - startMs).coerceIn(0, Int.MAX_VALUE.toLong()).toInt()

    companion object {
        fun factory(targetBand: Double) = viewModelFactory {
            initializer {
                BandUpgradeExamViewModel(
                    vocabRepository = AppRepositories.vocab,
                    targetBand = targetBand,
                )
            }
        }
    }
}
