package com.example.firsttest.ui.level

import com.example.firsttest.data.model.User
import com.example.firsttest.data.repository.FakeVocabRepository
import com.example.firsttest.data.repository.FakeUserRepository
import com.example.firsttest.data.repository.SessionUserRepository
import com.example.firsttest.data.repository.VocabRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class LevelPracticeViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    private fun newVm(
        vocabRepository: VocabRepository = FakeVocabRepository(),
        userRepository: RecordingSessionUserRepository = RecordingSessionUserRepository(),
    ) = LevelPracticeViewModel(vocabRepository, userRepository, levelNumber = 1)

    @Test
    fun loadsActiveLevelPracticeRound() = runTest(dispatcher) {
        val vm = newVm()

        advanceUntilIdle()

        val state = vm.uiState.value as LevelPracticeUiState.Answering
        assertEquals(0, state.questionIndex)
        assertEquals(7, state.totalQuestions)
        assertEquals("meaning_choice", state.question.questionTypeKey)
        assertFalse(state.submitEnabled)
    }

    @Test
    fun optionAnswerTransitionsToReviewing() = runTest(dispatcher) {
        val vm = newVm()
        advanceUntilIdle()

        val answering = vm.uiState.value as LevelPracticeUiState.Answering
        val correctOption = answering.question.options.first { it.isCorrect }
        vm.onOptionSelected(correctOption.optionId)
        assertTrue((vm.uiState.value as LevelPracticeUiState.Answering).submitEnabled)

        vm.onSubmit()
        advanceUntilIdle()

        val reviewing = vm.uiState.value as LevelPracticeUiState.Reviewing
        assertTrue(reviewing.isCorrect)
        assertEquals(1, reviewing.comboCount)
        assertEquals(correctOption.optionId, reviewing.submittedAnswer)
    }

    @Test
    fun keyboardWrongThenNextBreaksCombo() = runTest(dispatcher) {
        val vm = newVm()
        advanceUntilIdle()

        advanceToQuestion(vm, targetIndex = 3)

        val keyboard = vm.uiState.value as LevelPracticeUiState.Answering
        assertEquals("listening_fill", keyboard.question.questionTypeKey)
        assertEquals("keyboard", keyboard.question.answerForm)
        vm.onTypedAnswerChanged("__wrong__")
        vm.onSubmit()
        advanceUntilIdle()

        val reviewing = vm.uiState.value as LevelPracticeUiState.Reviewing
        assertFalse(reviewing.isCorrect)
        assertEquals(0, reviewing.comboCount)
    }

    @Test
    fun clozeNearMeaningDoesNotConsumeAttempt() = runTest(dispatcher) {
        val vm = newVm()
        advanceUntilIdle()
        advanceToQuestion(vm, targetIndex = 1)

        vm.onTypedAnswerChanged("reach")
        vm.onSubmit()
        advanceUntilIdle()

        val state = vm.uiState.value as LevelPracticeUiState.Answering
        assertEquals(0, state.attemptCount)
        assertEquals("", state.typedAnswer)
        assertTrue(state.feedback.contains("Close meaning"))
    }

    @Test
    fun clozeFirstWrongShowsHint() = runTest(dispatcher) {
        val vm = newVm()
        advanceUntilIdle()
        advanceToQuestion(vm, targetIndex = 1)

        vm.onTypedAnswerChanged("wrong")
        vm.onSubmit()
        advanceUntilIdle()

        val state = vm.uiState.value as LevelPracticeUiState.Answering
        assertEquals(1, state.attemptCount)
        assertEquals(7, state.letterCount)
        assertEquals("wrong", state.lastWrongAnswer)
        assertEquals("", state.typedAnswer)
    }

    @Test
    fun clozeHintCorrectIsAssistedCorrect() = runTest(dispatcher) {
        val vm = newVm()
        advanceUntilIdle()
        advanceToQuestion(vm, targetIndex = 1)

        vm.onTypedAnswerChanged("wrong")
        vm.onSubmit()
        advanceUntilIdle()
        vm.onTypedAnswerChanged("achieve")
        vm.onSubmit()
        advanceUntilIdle()

        val reviewing = vm.uiState.value as LevelPracticeUiState.Reviewing
        assertTrue(reviewing.isCorrect)
        assertEquals("assisted_correct", reviewing.answerOutcome)
        assertEquals(0, reviewing.comboCount)
    }

    @Test
    fun clozeSecondWrongRevealsAnswerThenRemediationRetype() = runTest(dispatcher) {
        val vm = newVm()
        advanceUntilIdle()
        advanceToQuestion(vm, targetIndex = 1)

        vm.onTypedAnswerChanged("wrong")
        vm.onSubmit()
        advanceUntilIdle()
        vm.onTypedAnswerChanged("still wrong")
        vm.onSubmit()
        advanceUntilIdle()

        val correction = vm.uiState.value as LevelPracticeUiState.SpellingCorrection
        assertEquals("still wrong", correction.lastWrongAnswer)
        assertEquals("achieve", correction.correctAnswer)

        vm.onTypedAnswerChanged("achieve")
        vm.onSubmit()
        advanceUntilIdle()

        val reviewing = vm.uiState.value as LevelPracticeUiState.Reviewing
        assertFalse(reviewing.isCorrect)
        assertEquals("remediation_completed", reviewing.answerOutcome)
    }

    @Test
    fun finishesRoundAndRefreshesUser() = runTest(dispatcher) {
        val userRepository = RecordingSessionUserRepository()
        val vm = newVm(userRepository = userRepository)
        advanceUntilIdle()

        repeat(7) {
            answerCurrentQuestionCorrectly(vm)
            advanceUntilIdle()
            vm.onNext()
            advanceUntilIdle()
        }

        val finished = vm.uiState.value as LevelPracticeUiState.Finished
        assertEquals(7, finished.correctCount)
        assertEquals(7, finished.totalCount)
        assertEquals(3, finished.starRating)
        assertEquals(7, finished.duckPowerEarned)
        assertEquals(1, userRepository.refreshCount)
    }

    @Test
    fun completionStillFinishesWhenProfileRefreshFails() = runTest(dispatcher) {
        val vm = newVm(userRepository = RecordingSessionUserRepository(failRefresh = true))
        advanceUntilIdle()

        repeat(7) {
            answerCurrentQuestionCorrectly(vm)
            advanceUntilIdle()
            vm.onNext()
            advanceUntilIdle()
        }

        assertTrue(vm.uiState.value is LevelPracticeUiState.Finished)
    }

    @Test
    fun retryAfterCompletionFailureFinishesRound() = runTest(dispatcher) {
        val repository = CompleteFailsOnceRepository()
        val vm = newVm(vocabRepository = repository)
        advanceUntilIdle()

        repeat(7) {
            answerCurrentQuestionCorrectly(vm)
            advanceUntilIdle()
            vm.onNext()
            advanceUntilIdle()
        }

        assertTrue(vm.uiState.value is LevelPracticeUiState.Error)

        vm.retry()
        advanceUntilIdle()

        assertTrue(vm.uiState.value is LevelPracticeUiState.Finished)
    }

    private fun answerCurrentQuestionCorrectly(vm: LevelPracticeViewModel) {
        val state = vm.uiState.value as LevelPracticeUiState.Answering
        if (state.question.answerForm == "keyboard") {
            val answer = when (state.question.questionTypeKey) {
                "sentence_cloze_typing" -> "achieve"
                "listening_fill" -> "significant"
                "word_form" -> "achievement"
                else -> error("Unexpected keyboard type ${state.question.questionTypeKey}")
            }
            vm.onTypedAnswerChanged(answer)
        } else {
            vm.onOptionSelected(state.question.options.first { it.isCorrect }.optionId)
        }
        vm.onSubmit()
    }

    private fun answerCurrentOptionCorrectly(vm: LevelPracticeViewModel) {
        val state = vm.uiState.value as LevelPracticeUiState.Answering
        vm.onOptionSelected(state.question.options.first { it.isCorrect }.optionId)
        vm.onSubmit()
    }

    private suspend fun kotlinx.coroutines.test.TestScope.advanceToQuestion(
        vm: LevelPracticeViewModel,
        targetIndex: Int,
    ) {
        while ((vm.uiState.value as LevelPracticeUiState.Answering).questionIndex < targetIndex) {
            answerCurrentQuestionCorrectly(vm)
            advanceUntilIdle()
            vm.onNext()
            advanceUntilIdle()
        }
    }
}

private class RecordingSessionUserRepository(
    private val failRefresh: Boolean = false,
) : SessionUserRepository {
    private val userRepository = FakeUserRepository()
    var refreshCount: Int = 0
        private set

    override suspend fun refreshCurrentUser() {
        refreshCount++
        if (failRefresh) error("Refresh failed")
    }

    override suspend fun clear() = Unit

    override suspend fun getCurrentUser(): User = userRepository.getCurrentUser()

    override suspend fun recordLoginAndCheckAwards(): List<com.example.firsttest.data.model.NewAward> = emptyList()
}

private class CompleteFailsOnceRepository(
    private val delegate: FakeVocabRepository = FakeVocabRepository(),
) : VocabRepository by delegate {
    private var shouldFail = true

    override suspend fun completePracticeRound(roundId: String): com.example.firsttest.data.model.PracticeRoundResult {
        if (shouldFail) {
            shouldFail = false
            error("temporary completion failure")
        }
        return delegate.completePracticeRound(roundId)
    }
}
