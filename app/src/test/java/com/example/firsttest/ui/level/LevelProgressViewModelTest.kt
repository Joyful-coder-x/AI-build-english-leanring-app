package com.example.firsttest.ui.level

import com.example.firsttest.data.model.LevelWordStatus
import com.example.firsttest.data.repository.FakeVocabRepository
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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class LevelProgressViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun loadsLevelWordStatusesAndCounts() = runTest(dispatcher) {
        val vm = LevelProgressViewModel(1, FakeVocabRepository())

        advanceUntilIdle()

        val state = vm.uiState.value as LevelProgressUiState.Success
        assertEquals(1, state.levelNumber)
        assertTrue(state.isUnlocked)
        assertEquals(45, state.words.size)
        assertEquals(5, state.masteredCount)
        assertEquals(20, state.startedCount)
    }

    @Test
    fun retryReloadsAfterError() = runTest(dispatcher) {
        val repository = FlakyLevelStatusRepository()
        val vm = LevelProgressViewModel(1, repository)

        advanceUntilIdle()
        assertTrue(vm.uiState.value is LevelProgressUiState.Error)

        vm.retry()
        advanceUntilIdle()

        val state = vm.uiState.value as LevelProgressUiState.Success
        assertEquals(listOf("evidence"), state.words.map { it.word })
    }

    @Test
    fun lockedLevelDoesNotLoadWordStatuses() = runTest(dispatcher) {
        val repository = LockedLevelRepository()
        val vm = LevelProgressViewModel(2, repository)

        advanceUntilIdle()

        val state = vm.uiState.value as LevelProgressUiState.Success
        assertEquals(2, state.levelNumber)
        assertTrue(!state.isUnlocked)
        assertTrue(state.words.isEmpty())
        assertEquals(0, repository.statusCalls)
    }
}

private class FlakyLevelStatusRepository(
    private val delegate: FakeVocabRepository = FakeVocabRepository(),
) : VocabRepository by delegate {
    private var calls = 0

    override suspend fun getLevelWordStatuses(levelNumber: Int): List<LevelWordStatus> {
        calls++
        if (calls == 1) error("temporary failure")
        return listOf(
            LevelWordStatus(
                senseId = "s1",
                word = "evidence",
                definitionZh = "proof",
                status = "learning",
                wrongCount = 0,
                isDue = false,
            )
        )
    }
}

private class LockedLevelRepository(
    private val delegate: FakeVocabRepository = FakeVocabRepository(),
) : VocabRepository by delegate {
    var statusCalls: Int = 0
        private set

    override suspend fun getLevelWordStatuses(levelNumber: Int): List<LevelWordStatus> {
        statusCalls++
        return delegate.getLevelWordStatuses(levelNumber)
    }
}
