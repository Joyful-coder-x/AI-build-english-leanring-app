package com.example.firsttest.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.OverallAssessment
import com.example.firsttest.data.model.OverallAssessmentQuestion
import com.example.firsttest.data.repository.VocabRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface OverallAssessmentUiState {
    /** Warning screen: question count, estimated time, confirm to start (ASSESS-002). */
    data object Confirm : OverallAssessmentUiState
    data object Loading : OverallAssessmentUiState

    data class Answering(
        val assessment: OverallAssessment,
        val question: OverallAssessmentQuestion,
        val questionIndex: Int,
        val selectedOptionId: String? = null,
        val typedAnswer: String = "",
        val isSubmitting: Boolean = false,
        val questionStartMs: Long = System.currentTimeMillis(),
    ) : OverallAssessmentUiState {
        val submitEnabled: Boolean get() = !isSubmitting && when (question.answerForm) {
            "keyboard" -> typedAnswer.isNotBlank()
            else -> selectedOptionId != null
        }
    }

    data class Result(val assessment: OverallAssessment) : OverallAssessmentUiState
    data class Error(val message: String) : OverallAssessmentUiState
}

class OverallAssessmentViewModel(
    private val vocabRepository: VocabRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<OverallAssessmentUiState>(OverallAssessmentUiState.Confirm)
    val uiState: StateFlow<OverallAssessmentUiState> = _uiState.asStateFlow()

    private var assessment: OverallAssessment? = null

    fun start() = load()

    fun retry() = load()

    private fun load() {
        _uiState.value = OverallAssessmentUiState.Loading
        viewModelScope.launch {
            try {
                val loaded = vocabRepository.startOverallAssessment()
                assessment = loaded
                _uiState.value = if (loaded.status == "completed") {
                    OverallAssessmentUiState.Result(loaded)
                } else {
                    buildAnswering(loaded.nextQuestionIndex())
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = OverallAssessmentUiState.Error(
                    e.message ?: "Failed to load the overall assessment.",
                )
            }
        }
    }

    fun onOptionSelected(optionId: String) {
        val state = _uiState.value as? OverallAssessmentUiState.Answering ?: return
        _uiState.value = state.copy(selectedOptionId = optionId)
    }

    fun onTypedAnswerChanged(text: String) {
        val state = _uiState.value as? OverallAssessmentUiState.Answering ?: return
        _uiState.value = state.copy(typedAnswer = text)
    }

    fun onSubmit() {
        val state = _uiState.value as? OverallAssessmentUiState.Answering ?: return
        val answer = when (state.question.answerForm) {
            "keyboard" -> state.typedAnswer.trim().ifBlank { return }
            else -> state.selectedOptionId ?: return
        }
        _uiState.value = state.copy(isSubmitting = true)
        viewModelScope.launch {
            try {
                vocabRepository.saveOverallAssessmentAnswer(
                    attemptId = state.assessment.attemptId,
                    position = state.question.position,
                    answer = answer,
                    responseTimeMs = elapsed(state.questionStartMs),
                )
                val updatedQuestions = state.assessment.questions.map { question ->
                    if (question.position == state.question.position) {
                        question.copy(answered = true)
                    } else {
                        question
                    }
                }
                val updated = state.assessment.copy(questions = updatedQuestions)
                assessment = updated
                val nextIndex = state.questionIndex + 1
                if (nextIndex < updated.questions.size) {
                    _uiState.value = buildAnswering(nextIndex)
                } else {
                    complete(updated.attemptId)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = OverallAssessmentUiState.Error(
                    e.message ?: "Failed to save your answer.",
                )
            }
        }
    }

    private fun complete(attemptId: String) {
        _uiState.value = OverallAssessmentUiState.Loading
        viewModelScope.launch {
            try {
                val completed = vocabRepository.completeOverallAssessment(attemptId)
                assessment = completed
                _uiState.value = OverallAssessmentUiState.Result(completed)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = OverallAssessmentUiState.Error(
                    e.message ?: "Failed to complete the overall assessment.",
                )
            }
        }
    }

    private fun buildAnswering(index: Int): OverallAssessmentUiState.Answering {
        val current = requireNotNull(assessment)
        val safeIndex = index.coerceIn(0, current.questions.lastIndex)
        return OverallAssessmentUiState.Answering(
            assessment = current,
            question = current.questions[safeIndex],
            questionIndex = safeIndex,
        )
    }

    private fun OverallAssessment.nextQuestionIndex(): Int {
        val next = questions.indexOfFirst { !it.answered }
        return if (next >= 0) next else questions.lastIndex.coerceAtLeast(0)
    }

    private fun elapsed(startMs: Long): Int =
        (System.currentTimeMillis() - startMs).coerceIn(0, Int.MAX_VALUE.toLong()).toInt()

    companion object {
        val Factory = viewModelFactory {
            initializer { OverallAssessmentViewModel(AppRepositories.vocab) }
        }
    }
}
