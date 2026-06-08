package com.example.firsttest.ui.mistakes

import com.example.firsttest.data.model.MistakeWord
import com.example.firsttest.data.repository.FakeMistakeRepository
import com.example.firsttest.data.repository.MistakeRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MistakesViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun startsLoading() {
        assertEquals(MistakesUiState.Loading, MistakesViewModel(FakeMistakeRepository()).uiState.value)
    }

    @Test
    fun emitsSuccessWithFiveFakeWords() = runTest(dispatcher) {
        val vm = MistakesViewModel(FakeMistakeRepository())
        advanceUntilIdle()
        val s = vm.uiState.value as MistakesUiState.Success
        assertEquals(5, s.words.size)
    }

    @Test
    fun firstWordIsStageZeroReviewToday() = runTest(dispatcher) {
        val vm = MistakesViewModel(FakeMistakeRepository())
        advanceUntilIdle()
        val first = (vm.uiState.value as MistakesUiState.Success).words.first()
        assertEquals(0, first.reviewStage)
        assertEquals("今天复习", first.nextReviewLabel)
    }

    @Test
    fun emptyRepositoryEmitsEmptyState() = runTest(dispatcher) {
        val emptyRepo = object : MistakeRepository {
            override suspend fun getMistakeWords(): List<MistakeWord> = emptyList()
        }
        val vm = MistakesViewModel(emptyRepo)
        advanceUntilIdle()
        assertEquals(MistakesUiState.Empty, vm.uiState.value)
    }

    @Test
    fun allEbinghausStagesPresent() = runTest(dispatcher) {
        val vm = MistakesViewModel(FakeMistakeRepository())
        advanceUntilIdle()
        val stages = (vm.uiState.value as MistakesUiState.Success).words.map { it.reviewStage }
        assertTrue(stages.containsAll(listOf(0, 1, 2, 3, 4)))
    }
}
