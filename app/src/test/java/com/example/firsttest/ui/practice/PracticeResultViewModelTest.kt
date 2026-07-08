package com.example.firsttest.ui.practice

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
class PracticeResultViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun loadLevelWordsOnlyLoadsOnceWhenReady() = runTest(dispatcher) {
        val repository = CountingLevelStatusRepository()
        val vm = PracticeResultViewModel(repository)

        vm.loadLevelWords(1)
        advanceUntilIdle()
        vm.loadLevelWords(1)
        advanceUntilIdle()

        val state = vm.wordList.value as LevelWordListState.Ready
        assertEquals(1, repository.calls)
        assertEquals(listOf("achieve"), state.words.map { it.word })
    }

    @Test
    fun errorCanRetryOnNextLoad() = runTest(dispatcher) {
        val repository = FlakyPracticeResultRepository()
        val vm = PracticeResultViewModel(repository)

        vm.loadLevelWords(1)
        advanceUntilIdle()
        assertTrue(vm.wordList.value is LevelWordListState.Error)

        vm.loadLevelWords(1)
        advanceUntilIdle()

        val state = vm.wordList.value as LevelWordListState.Ready
        assertEquals(listOf("benefit"), state.words.map { it.word })
    }
}

private class CountingLevelStatusRepository(
    private val delegate: FakeVocabRepository = FakeVocabRepository(),
) : VocabRepository by delegate {
    var calls: Int = 0
        private set

    override suspend fun getLevelWordStatuses(levelNumber: Int): List<LevelWordStatus> {
        calls++
        return listOf(
            LevelWordStatus(
                senseId = "s1",
                word = "achieve",
                definitionZh = "reach a goal",
                status = "learning",
                wrongCount = 0,
                isDue = false,
            )
        )
    }
}

private class FlakyPracticeResultRepository(
    private val delegate: FakeVocabRepository = FakeVocabRepository(),
) : VocabRepository by delegate {
    private var calls = 0

    override suspend fun getLevelWordStatuses(levelNumber: Int): List<LevelWordStatus> {
        calls++
        if (calls == 1) error("temporary failure")
        return listOf(
            LevelWordStatus(
                senseId = "s2",
                word = "benefit",
                definitionZh = "advantage",
                status = "reviewing",
                wrongCount = 1,
                isDue = true,
            )
        )
    }
}
