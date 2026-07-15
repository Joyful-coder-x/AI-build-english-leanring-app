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
        val attemptCount: Int = question.attemptCount,
        val letterCount: Int? = question.letterCount,
        val feedback: String = "",
        val lastWrongAnswer: String = "",
        val selfCheckHintStage: Int = 0,
        val selfCheckDefinitionZh: String = "",
        val selfCheckExampleSentence: String? = null,
        val isHintLoading: Boolean = false,
        val questionStartMs: Long = System.currentTimeMillis(),
        val isSubmitting: Boolean = false,
    ) : LevelPracticeUiState {
        val submitEnabled: Boolean get() = !isSubmitting && when (question.answerForm) {
            "keyboard" -> typedAnswer.isNotBlank()
            else -> selectedOptionId != null
        }
    }

    /**
     * Shown after the backend reveals the correct answer (attempt_count == 2, wrong).
     * Displays a letter-by-letter diff so the user sees exactly what was wrong, then
     * requires one correct retype to finalize the backend question before Reviewing.
     */
    data class SpellingCorrection(
        val question: LevelPracticeQuestion,
        val questionIndex: Int,
        val totalQuestions: Int,
        val comboCount: Int,
        val lastWrongAnswer: String,
        val correctAnswer: String,
        val typedAnswer: String = "",
        // Set after each wrong retype attempt — drives inline feedback without hitting backend
        val retryWrongAnswer: String = "",
        val retryTooManyTypos: Boolean = false,
        val questionStartMs: Long = System.currentTimeMillis(),
        val isSubmitting: Boolean = false,
    ) : LevelPracticeUiState {
        val submitEnabled: Boolean get() = typedAnswer.isNotBlank() && !isSubmitting
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
        val selfCheckHintUsed: Boolean = false,
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
                // Resuming an in-progress round: replaying an already-graded position
                // would resubmit into a question the backend already scored, so the
                // server just echoes back its original (possibly stale-looking) verdict.
                // Skip forward to the first position that hasn't been answered yet.
                val nextIndex = questions.indexOfFirst { !it.isAnswered }
                _uiState.value = when {
                    questions.isEmpty() -> LevelPracticeUiState.Error("该关卡暂无题目，请稍后重试")
                    nextIndex == -1 -> {
                        awaitingCompletion = true
                        finishRound()
                        return@launch
                    }
                    else -> buildAnswering(nextIndex)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = LevelPracticeUiState.Error(e.message ?: "加载题目失败，请重试")
            }
        }
    }

    fun onOptionSelected(optionId: String) {
        val s = _uiState.value as? LevelPracticeUiState.Answering ?: return
        if (s.question.isSpeakingSelfCheck() && optionId == SELF_CHECK_KNOWN_OPTION_ID) {
            _uiState.value = s.copy(selectedOptionId = optionId)
            return
        }
        val option = s.question.options.firstOrNull { it.optionId == optionId } ?: return
        if (s.question.isSpeakingSelfCheck() && option.isSelfCheckHint()) {
            showSelfCheckHint(s)
            return
        }
        _uiState.value = s.copy(selectedOptionId = optionId)
    }

    private fun showSelfCheckHint(state: LevelPracticeUiState.Answering) {
        if (state.isHintLoading) return
        if (state.selfCheckHintStage == 0) {
            _uiState.value = state.copy(
                selfCheckHintStage = 1,
                selfCheckDefinitionZh = state.question.translationZh,
                selectedOptionId = null,
                questionStartMs = System.currentTimeMillis(),
            )
            return
        }
        if (state.question.isReadAloudSelfCheck()) {
            _uiState.value = state.copy(
                selectedOptionId = null,
                questionStartMs = System.currentTimeMillis(),
                isSubmitting = false,
            )
            return
        }

        _uiState.value = state.copy(isHintLoading = true, selectedOptionId = null)
        viewModelScope.launch {
            try {
                val hint = vocabRepository.getSenseHint(state.question.senseId)
                val current = _uiState.value as? LevelPracticeUiState.Answering ?: return@launch
                if (current.question.questionId != state.question.questionId) return@launch
                _uiState.value = current.copy(
                    selfCheckHintStage = 2,
                    selfCheckDefinitionZh = hint.definitionZh.ifBlank { current.question.translationZh },
                    selfCheckExampleSentence = hint.exampleSentence,
                    isHintLoading = false,
                    questionStartMs = System.currentTimeMillis(),
                )
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                val current = _uiState.value as? LevelPracticeUiState.Answering ?: return@launch
                _uiState.value = current.copy(
                    selfCheckHintStage = 2,
                    selfCheckExampleSentence = null,
                    isHintLoading = false,
                    questionStartMs = System.currentTimeMillis(),
                )
            }
        }
    }

    fun onTypedAnswerChanged(text: String) {
        when (val s = _uiState.value) {
            is LevelPracticeUiState.Answering -> _uiState.value = s.copy(typedAnswer = text, feedback = "")
            is LevelPracticeUiState.SpellingCorrection -> _uiState.value = s.copy(typedAnswer = text)
            else -> Unit
        }
    }

    fun onSubmit() {
        when (val state = _uiState.value) {
            is LevelPracticeUiState.Answering -> {
                val answer = when (state.question.answerForm) {
                    "keyboard" -> state.typedAnswer.trim().ifBlank { return }
                    else -> state.selectedOptionId ?: return
                }
                submitStagedAnswer(
                    state.question, state.questionIndex, state.totalQuestions, answer,
                    elapsed(state.questionStartMs),
                    { _uiState.value = state.copy(isSubmitting = true) },
                ) { result -> handleAnsweringResult(state, answer, result) }
            }
            is LevelPracticeUiState.SpellingCorrection -> {
                val answer = state.typedAnswer.trim().ifBlank { return }
                val typos = countTypos(answer, state.correctAnswer)
                if (typos == 0) {
                    // Correct — finalize with backend
                    submitStagedAnswer(
                        state.question, state.questionIndex, state.totalQuestions, answer,
                        elapsed(state.questionStartMs),
                        { _uiState.value = state.copy(isSubmitting = true) },
                    ) { result ->
                        showReview(state.question, state.questionIndex, state.totalQuestions, answer, result)
                    }
                } else {
                    // Wrong — stay in SpellingCorrection with inline feedback, don't hit backend
                    _uiState.value = state.copy(
                        typedAnswer = "",
                        retryWrongAnswer = answer,
                        retryTooManyTypos = typos > 3,
                    )
                }
            }
            else -> Unit
        }
    }

    private fun submitStagedAnswer(
        question: LevelPracticeQuestion,
        questionIndex: Int,
        totalQuestions: Int,
        answer: String,
        responseMs: Int,
        markSubmitting: () -> Unit,
        handleResult: (com.example.firsttest.data.model.LevelPracticeAnswerResult) -> Unit,
    ) {
        markSubmitting()
        viewModelScope.launch {
            try {
                handleResult(vocabRepository.saveLevelPracticeAnswer(
                    roundId, question.position, answer, responseMs,
                ))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = LevelPracticeUiState.Error(e.message ?: "保存答案失败，请重试")
            }
        }
    }

    private fun handleAnsweringResult(
        state: LevelPracticeUiState.Answering,
        answer: String,
        result: com.example.firsttest.data.model.LevelPracticeAnswerResult,
    ) {
        when (result.action) {
            "near_meaning" -> _uiState.value = state.copy(
                typedAnswer = "",
                lastWrongAnswer = answer,
                feedback = result.feedback.ifBlank { "意思接近，但本题练的是本关目标词。" },
                questionStartMs = System.currentTimeMillis(),
                isSubmitting = false,
            )
            "retry_with_hint" -> _uiState.value = state.copy(
                typedAnswer = "",
                lastWrongAnswer = answer,
                attemptCount = result.attemptCount,
                letterCount = result.letterCount,
                questionStartMs = System.currentTimeMillis(),
                isSubmitting = false,
            )
            "reveal_answer" -> _uiState.value = LevelPracticeUiState.SpellingCorrection(
                question = state.question,
                questionIndex = state.questionIndex,
                totalQuestions = state.totalQuestions,
                comboCount = state.comboCount,
                lastWrongAnswer = answer,
                correctAnswer = requireNotNull(result.revealedAnswer),
            )
            else -> {
                val effectiveResult =
                    if (state.question.isSpeakingSelfCheck() && state.selfCheckHintStage > 0) {
                        result.copy(answerOutcome = "assisted_correct")
                    } else {
                        result
                    }
                showReview(
                    state.question,
                    state.questionIndex,
                    state.totalQuestions,
                    answer,
                    effectiveResult,
                    selfCheckHintUsed = state.question.isSpeakingSelfCheck() &&
                        state.selfCheckHintStage > 0,
                )
            }
        }
    }

    private fun showReview(
        question: LevelPracticeQuestion,
        questionIndex: Int,
        totalQuestions: Int,
        answer: String,
        result: com.example.firsttest.data.model.LevelPracticeAnswerResult,
        selfCheckHintUsed: Boolean = false,
    ) {
        if (result.answerOutcome == "full_correct") comboCount++ else comboCount = 0
        _uiState.value = LevelPracticeUiState.Reviewing(
            question = question,
            questionIndex = questionIndex,
            totalQuestions = totalQuestions,
            submittedAnswer = answer,
            correctOptionId = result.correctOptionId,
            correctAnswer = result.revealedAnswer ?: result.correctAnswer,
            answerOutcome = result.answerOutcome,
            comboCount = comboCount,
            selfCheckHintUsed = selfCheckHintUsed,
        )
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

    private fun buildAnswering(index: Int): LevelPracticeUiState.Answering {
        val question = questions[index]
        return LevelPracticeUiState.Answering(
            question = question,
            questionIndex = index,
            totalQuestions = questions.size,
            comboCount = comboCount,
        )
    }

    private fun countTypos(attempted: String, correct: String): Int {
        val a = attempted.trim().lowercase()
        val b = correct.trim().lowercase()
        return (0 until maxOf(a.length, b.length)).count { i -> a.getOrNull(i) != b.getOrNull(i) }
    }

    private fun elapsed(startMs: Long): Int =
        (System.currentTimeMillis() - startMs).coerceIn(0, Int.MAX_VALUE.toLong()).toInt()

    private fun LevelPracticeQuestion.isSpeakingSelfCheck(): Boolean =
        questionTypeKey == "open_speaking" ||
            questionTypeKey == "speaking_repeat" ||
            typeCode == 105 ||
            typeCode == 106 ||
            stem.startsWith("Say one short sentence using:", ignoreCase = true)

    private fun LevelPracticeQuestion.isReadAloudSelfCheck(): Boolean =
        questionTypeKey == "speaking_repeat" ||
            typeCode == 105 ||
            stem.startsWith("Say this word aloud:", ignoreCase = true)

    private fun com.example.firsttest.data.model.MeaningChoiceOption.isSelfCheckHint(): Boolean =
        text == "I need hint" || text == "I need more practice."

    companion object {
        private const val SELF_CHECK_KNOWN_OPTION_ID = "__self_check_known__"

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
