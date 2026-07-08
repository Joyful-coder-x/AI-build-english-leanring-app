package com.example.firsttest.ui.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.repository.OnboardingFlowState
import com.example.firsttest.data.repository.OnboardingRepository
import com.example.firsttest.data.repository.UserBootstrapState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class OnboardingOption(
    val value: String,
    val label: String,
)

data class OnboardingQuestion(
    val key: String,
    val text: String,
    val options: List<OnboardingOption>,
)

val ONBOARDING_QUESTIONS = listOf(
    OnboardingQuestion(
        key = "occupation",
        text = "Before we start, what describes you best?",
        options = listOf(
            OnboardingOption("student", "Student"),
            OnboardingOption("employed", "Working professional"),
            OnboardingOption("freelancer", "Freelancer"),
            OnboardingOption("full_time_parent", "Full-time parent"),
            OnboardingOption("other", "Other"),
        ),
    ),
    OnboardingQuestion(
        key = "ielts_reason",
        text = "Why are you preparing for IELTS?",
        options = listOf(
            OnboardingOption("study_abroad", "Study abroad"),
            OnboardingOption("work", "Work requirement"),
            OnboardingOption("self_improvement", "Improve my English"),
            OnboardingOption("migration", "Migration plan"),
            OnboardingOption("accompany_child", "Support my child"),
            OnboardingOption("other", "Other"),
        ),
    ),
    OnboardingQuestion(
        key = "self_reported_level",
        text = "How would you describe your current English level?",
        options = listOf(
            OnboardingOption("weak", "Basic foundation"),
            OnboardingOption("cet4", "Intermediate"),
            OnboardingOption("cet6", "Upper intermediate"),
            OnboardingOption("unsure", "Not sure"),
        ),
    ),
    OnboardingQuestion(
        key = "target_band",
        text = "What IELTS band are you aiming for?",
        options = listOf(
            OnboardingOption("5_0", "5.0"),
            OnboardingOption("5_5", "5.5"),
            OnboardingOption("6_0", "6.0"),
            OnboardingOption("6_5", "6.5"),
            OnboardingOption("7_0_plus", "7.0+"),
        ),
    ),
    OnboardingQuestion(
        key = "prep_timeline",
        text = "How long do you plan to prepare?",
        options = listOf(
            OnboardingOption("under_3_months", "Under 3 months"),
            OnboardingOption("3_to_6_months", "3 to 6 months"),
            OnboardingOption("over_6_months", "Over 6 months"),
            OnboardingOption("unsure", "Not sure"),
        ),
    ),
)

sealed interface OnboardingUiState {
    data class Question(
        val currentIndex: Int,
        val answers: Map<String, String>,
        val isSaving: Boolean = false,
        val errorMessage: String? = null,
    ) : OnboardingUiState

    data object Completed : OnboardingUiState
}

class OnboardingViewModel(
    private val repository: OnboardingRepository,
    bootstrap: UserBootstrapState,
) : ViewModel() {
    private val mutableState = MutableStateFlow<OnboardingUiState>(
        if (bootstrap.flowState == OnboardingFlowState.HOME_READY) {
            OnboardingUiState.Completed
        } else {
            OnboardingUiState.Question(
                currentIndex = bootstrap.currentQuestionIndex.coerceIn(0, 4),
                answers = bootstrap.onboardingAnswers,
            )
        }
    )
    val uiState: StateFlow<OnboardingUiState> = mutableState.asStateFlow()

    private var failedOption: OnboardingOption? = null

    fun onAnswer(option: OnboardingOption) {
        val state = mutableState.value as? OnboardingUiState.Question ?: return
        if (state.isSaving) return
        submit(state, option)
    }

    fun retry() {
        val state = mutableState.value as? OnboardingUiState.Question ?: return
        val option = failedOption ?: return
        submit(state, option)
    }

    private fun submit(state: OnboardingUiState.Question, option: OnboardingOption) {
        val question = ONBOARDING_QUESTIONS[state.currentIndex]
        failedOption = option
        viewModelScope.launch {
            mutableState.value = state.copy(isSaving = true, errorMessage = null)
            try {
                val bootstrap = repository.saveAnswer(
                    questionnaireVersion = QUESTIONNAIRE_VERSION,
                    answerKey = question.key,
                    answerValue = option.value,
                    expectedQuestionIndex = state.currentIndex,
                )
                failedOption = null
                mutableState.value =
                    if (bootstrap.flowState == OnboardingFlowState.HOME_READY) {
                        OnboardingUiState.Completed
                    } else {
                        OnboardingUiState.Question(
                            currentIndex = bootstrap.currentQuestionIndex.coerceIn(0, 4),
                            answers = bootstrap.onboardingAnswers,
                        )
                    }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                mutableState.value = state.copy(
                    isSaving = false,
                    errorMessage = error.message ?: "Failed to save. Please retry.",
                )
            }
        }
    }

    companion object {
        const val QUESTIONNAIRE_VERSION = "1"

        fun factory(
            repository: OnboardingRepository,
            bootstrap: UserBootstrapState,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer { OnboardingViewModel(repository, bootstrap) }
        }
    }
}
