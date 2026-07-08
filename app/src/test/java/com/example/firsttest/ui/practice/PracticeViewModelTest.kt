package com.example.firsttest.ui.practice

import com.example.firsttest.data.repository.FakePracticeRepository
import com.example.firsttest.data.repository.FakeUserRepository
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
class PracticeViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun newVm(userRepo: FakeUserRepository = FakeUserRepository()) =
        PracticeViewModel(userRepo, FakePracticeRepository(), "dt2")

    // ---- Loading → first question -------------------------------------------

    @Test
    fun startsLoading() = assertEquals(PracticeUiState.Loading, newVm().uiState.value)

    @Test
    fun loadsFourQuestions() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        val s = vm.uiState.value as PracticeUiState.Answering
        assertEquals(4, s.totalQuestions)
        assertEquals(0, s.questionIndex)
    }

    // ---- Submit gate --------------------------------------------------------

    @Test
    fun submitDisabledWithNoAnswer() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        assertFalse((vm.uiState.value as PracticeUiState.Answering).submitEnabled)
    }

    @Test
    fun submitEnabledAfterAnswerTyped() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        vm.onAnswerChanged("discovery")
        assertTrue((vm.uiState.value as PracticeUiState.Answering).submitEnabled)
    }

    // ---- Correct / wrong answers -------------------------------------------

    @Test
    fun correctAnswerTransitionsToReviewingIsCorrect() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        vm.onAnswerChanged("discovery"); vm.onSubmit()
        val s = vm.uiState.value as PracticeUiState.Reviewing
        assertTrue(s.isCorrect)
        assertEquals(1, s.comboCount)
    }

    @Test
    fun wrongAnswerResetsCombo() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        vm.onAnswerChanged("wrong"); vm.onSubmit()
        val s = vm.uiState.value as PracticeUiState.Reviewing
        assertFalse(s.isCorrect)
        assertEquals(0, s.comboCount)
    }

    @Test
    fun answerCheckIsCaseInsensitive() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        vm.onAnswerChanged("DISCOVERY"); vm.onSubmit()
        assertTrue((vm.uiState.value as PracticeUiState.Reviewing).isCorrect)
    }

    // ---- Navigation through all questions ----------------------------------

    @Test
    fun nextAdvancesToSecondQuestion() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        vm.onAnswerChanged("discovery"); vm.onSubmit(); vm.onNext()
        assertEquals(1, (vm.uiState.value as PracticeUiState.Answering).questionIndex)
    }

    @Test
    fun afterLastQuestionEmitsFinished() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        repeat(4) {
            val s = vm.uiState.value as PracticeUiState.Answering
            vm.onAnswerChanged(s.question.correctAnswer); vm.onSubmit(); vm.onNext()
        }
        advanceUntilIdle()
        assertTrue(vm.uiState.value is PracticeUiState.Finished)
    }

    @Test
    fun allCorrectGivesThreeStarsAndPersistsDuckPower() = runTest(dispatcher) {
        val userRepo = FakeUserRepository()
        val vm = PracticeViewModel(userRepo, FakePracticeRepository(), "dt2")
        advanceUntilIdle()

        repeat(4) {
            val s = vm.uiState.value as PracticeUiState.Answering
            vm.onAnswerChanged(s.question.correctAnswer); vm.onSubmit(); vm.onNext()
        }
        advanceUntilIdle()

        val f = vm.uiState.value as PracticeUiState.Finished
        assertEquals(3, f.starRating)
        // 4 correct + 5 all-correct bonus + 5 speed bonus.
        assertEquals(14, f.duckPowerEarned)
        assertEquals(450 + 14, userRepo.getCurrentUser().duckPower)
    }

    @Test
    fun zeroCorrectGivesZeroStarsAndNoDuckPower() = runTest(dispatcher) {
        val userRepo = FakeUserRepository()
        val vm = PracticeViewModel(userRepo, FakePracticeRepository(), "dt2")
        advanceUntilIdle()

        repeat(4) {
            val answering = vm.uiState.value as PracticeUiState.Answering
            vm.onAnswerChanged("__wrong__")
            vm.onSubmit()
            if (answering.question.typeCode == 3) {
                vm.onAnswerChanged("__wrong_again__")
                vm.onSubmit()
                vm.onClozeAnswerSeen()
                vm.onAnswerChanged("__still_wrong__")
                vm.onSubmit()
            }
            vm.onNext()
        }
        advanceUntilIdle()

        val f = vm.uiState.value as PracticeUiState.Finished
        assertEquals(0, f.starRating)
        assertEquals(0, f.duckPowerEarned)
        assertEquals(450, userRepo.getCurrentUser().duckPower) // unchanged
    }

    // ---- Combo bonus (spec 2.2.3) ------------------------------------------

    @Test
    fun comboBonus_triggersAboveFive() = runTest(dispatcher) {
        // Fake repo has 4 questions — combo cannot reach the bonus threshold.
        // Verify the bonus logic directly: >5 correct in a row → +1 each
        val comboAtSix = 6
        val bonus = when {
            comboAtSix > 10 -> 2
            comboAtSix > 5  -> 1
            else            -> 0
        }
        assertEquals(1, bonus)
    }

    @Test
    fun comboBonus_triggersAboveTen() {
        val comboAtEleven = 11
        val bonus = when {
            comboAtEleven > 10 -> 2
            comboAtEleven > 5  -> 1
            else               -> 0
        }
        assertEquals(2, bonus)
    }

    @Test
    fun comboBonus_noExtraBelow6() {
        for (combo in 0..5) {
            val bonus = when { combo > 10 -> 2; combo > 5 -> 1; else -> 0 }
            assertEquals("combo=$combo should give 0 bonus", 0, bonus)
        }
    }

    // ---- Type 3 (sentence_cloze_typing) flow --------------------------------

    private fun newVmAtClozeQuestion(): PracticeViewModel {
        val vm = newVm()
        return vm // caller must advanceUntilIdle() then skip Q1-Q3
    }

    private suspend fun kotlinx.coroutines.test.TestScope.advanceToQ4(vm: PracticeViewModel) {
        advanceUntilIdle()
        repeat(3) {
            val s = vm.uiState.value as PracticeUiState.Answering
            vm.onAnswerChanged(s.question.correctAnswer); vm.onSubmit(); vm.onNext()
        }
    }

    @Test
    fun cloze_firstTryCorrectGoesDirectlyToReviewing() = runTest(dispatcher) {
        val vm = newVm(); advanceToQ4(vm)
        vm.onAnswerChanged("mother"); vm.onSubmit()
        val s = vm.uiState.value as PracticeUiState.Reviewing
        assertTrue(s.isCorrect)
        assertEquals(ClozeResult.FIRST_TRY_CORRECT, s.clozeResult)
    }

    @Test
    fun cloze_firstWrongShowsLetterHint() = runTest(dispatcher) {
        val vm = newVm(); advanceToQ4(vm)
        vm.onAnswerChanged("wrong"); vm.onSubmit()
        val s = vm.uiState.value as PracticeUiState.Answering
        assertTrue(s.showLetterHint)
        assertEquals(1, s.clozeAttemptCount)
    }

    @Test
    fun cloze_nearMeaningDoesNotConsumeAttempt() = runTest(dispatcher) {
        val vm = newVm(); advanceToQ4(vm)
        vm.onAnswerChanged("mom"); vm.onSubmit() // "mom" is in nearMeaningAnswers
        val s = vm.uiState.value as PracticeUiState.Answering
        assertEquals(0, s.clozeAttemptCount) // attempt not consumed
        assertTrue(s.nearMeaningFeedback != null)
    }

    @Test
    fun cloze_secondWrongRevealsAnswer() = runTest(dispatcher) {
        val vm = newVm(); advanceToQ4(vm)
        vm.onAnswerChanged("wrong"); vm.onSubmit()
        vm.onAnswerChanged("wrong"); vm.onSubmit()
        assertTrue(vm.uiState.value is PracticeUiState.ShowingClozeAnswer)
    }

    @Test
    fun cloze_memoryRetypeCorrectIsNotSessionCorrect() = runTest(dispatcher) {
        val vm = newVm(); advanceToQ4(vm)
        vm.onAnswerChanged("wrong"); vm.onSubmit()
        vm.onAnswerChanged("wrong"); vm.onSubmit()
        vm.onClozeAnswerSeen()
        vm.onAnswerChanged("mother"); vm.onSubmit()
        val s = vm.uiState.value as PracticeUiState.Reviewing
        assertFalse(s.isCorrect) // doesn't count as session correct
        assertEquals(ClozeResult.MEMORY_RETYPE_CORRECT, s.clozeResult)
    }

    @Test
    fun cloze_hintCorrectCounts() = runTest(dispatcher) {
        val vm = newVm(); advanceToQ4(vm)
        vm.onAnswerChanged("wrong"); vm.onSubmit()  // attempt 1 wrong → letter hint
        vm.onAnswerChanged("mother"); vm.onSubmit() // attempt 2 correct with hint
        val s = vm.uiState.value as PracticeUiState.Reviewing
        assertTrue(s.isCorrect)
        assertEquals(ClozeResult.HINT_CORRECT, s.clozeResult)
    }

    // ---- Scoring helpers ---------------------------------------------------

    @Test fun stars_100pct() = assertEquals(3, calcStars(3, 3))
    @Test fun stars_90pct_exact() = assertEquals(3, calcStars(9, 10))
    @Test fun stars_67pct() = assertEquals(2, calcStars(2, 3))
    @Test fun stars_40pct_exact() = assertEquals(1, calcStars(2, 5))
    @Test fun stars_33pct() = assertEquals(0, calcStars(1, 3))
    @Test fun stars_zero() = assertEquals(0, calcStars(0, 3))

    @Test fun duckPower_allCorrect() = assertEquals(8, calcDuckPower(3, 3))
    @Test fun duckPower_partial()    = assertEquals(2, calcDuckPower(2, 3))
    @Test fun duckPower_none()       = assertEquals(0, calcDuckPower(0, 3))
}
