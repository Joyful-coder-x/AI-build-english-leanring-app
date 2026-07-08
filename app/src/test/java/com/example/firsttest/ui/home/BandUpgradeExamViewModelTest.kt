package com.example.firsttest.ui.home

import com.example.firsttest.data.repository.FakeVocabRepository
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
class BandUpgradeExamViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun newVm() = BandUpgradeExamViewModel(FakeVocabRepository(), targetBand = 4.5)

    @Test
    fun startsInLoadingState() {
        assertEquals(BandUpgradeExamUiState.Loading, newVm().uiState.value)
    }

    @Test
    fun loadsFortyQuestionBandExam() = runTest(dispatcher) {
        val vm = newVm()
        advanceUntilIdle()

        val state = vm.uiState.value as BandUpgradeExamUiState.Answering
        assertEquals(4.0, state.exam.sourceBand, 0.0)
        assertEquals(4.5, state.exam.targetBand, 0.0)
        assertEquals(40, state.exam.questions.size)
        assertEquals(mapOf("meaning" to 10, "listening" to 10, "spelling" to 10, "speaking" to 10), state.exam.categoryCounts)
    }

    @Test
    fun allCorrectAnswersPassExam() = runTest(dispatcher) {
        val vm = newVm()
        advanceUntilIdle()

        repeat(40) {
            answerCurrentCorrectly(vm)
            advanceUntilIdle()
        }

        val result = vm.uiState.value as BandUpgradeExamUiState.Result
        assertTrue(result.exam.passed == true)
        assertEquals(40, result.exam.correctCount)
    }

    @Test
    fun allWrongAnswersFailExam() = runTest(dispatcher) {
        val vm = newVm()
        advanceUntilIdle()

        repeat(40) {
            answerCurrentWrongly(vm)
            advanceUntilIdle()
        }

        val result = vm.uiState.value as BandUpgradeExamUiState.Result
        assertFalse(result.exam.passed == true)
        assertEquals(0, result.exam.correctCount)
    }

    private fun answerCurrentCorrectly(vm: BandUpgradeExamViewModel) {
        val state = vm.uiState.value as BandUpgradeExamUiState.Answering
        if (state.question.answerForm == "keyboard") {
            vm.onTypedAnswerChanged("evidence")
        } else {
            vm.onOptionSelected("fake-${state.question.position}-a")
        }
        vm.onSubmit()
    }

    private fun answerCurrentWrongly(vm: BandUpgradeExamViewModel) {
        val state = vm.uiState.value as BandUpgradeExamUiState.Answering
        if (state.question.answerForm == "keyboard") {
            vm.onTypedAnswerChanged("wrong")
        } else {
            vm.onOptionSelected("fake-${state.question.position}-b")
        }
        vm.onSubmit()
    }
}
