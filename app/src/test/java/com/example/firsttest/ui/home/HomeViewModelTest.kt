package com.example.firsttest.ui.home

import com.example.firsttest.data.repository.FakeUserRepository
import com.example.firsttest.data.repository.FakeVocabRepository
import com.example.firsttest.data.model.Level
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
class HomeViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun newVm() = HomeViewModel(FakeUserRepository(), FakeVocabRepository())

    @Test
    fun startsInLoadingState() {
        assertEquals(HomeUiState.Loading, newVm().uiState.value)
    }

    @Test
    fun emitsSuccessAfterLoad() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        assertTrue(vm.uiState.value is HomeUiState.Success)
    }

    @Test
    fun statusRowHasCorrectFakeValues() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        val s = vm.uiState.value as HomeUiState.Success
        assertEquals(450, s.duckPower)
        assertEquals(5,   s.streakDays)
        assertEquals(7,   s.streakGoal)
    }

    @Test
    fun nineDifficultyBandsShownWithLevelOneUnlocked() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        val bands = (vm.uiState.value as HomeUiState.Success).bands
        val levels = bands.flatMap { it.levels }
        assertEquals(9, bands.size)
        assertEquals(240, levels.size)
        assertTrue(levels.first { it.number == 1 }.isUnlocked)
        assertTrue(levels.filter { it.number > 1 }.all { !it.isUnlocked })
        assertTrue(bands.first { it.score == 4.0 }.isCurrent)
        assertTrue(bands.first { it.score == 4.0 }.isUnlocked)
        assertTrue(!bands.first { it.score == 4.5 }.isUnlocked)
    }

    @Test
    fun levelsAreInAscendingOrder() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        val numbers = (vm.uiState.value as HomeUiState.Success)
            .bands
            .flatMap { it.levels }
            .map { it.number }
        assertEquals((1..240).toList(), numbers)
    }

    @Test
    fun levelsAreGroupedByRealBandRanges() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        val bands = (vm.uiState.value as HomeUiState.Success).bands

        assertEquals(54, bands.first { it.score == 4.0 }.levels.size)
        assertEquals(27, bands.first { it.score == 4.5 }.levels.size)
        assertEquals(1, bands.first { it.score == 4.0 }.levels.first().number)
        assertEquals(55, bands.first { it.score == 4.5 }.levels.first().number)
        assertEquals("IELTS Band 4", bands.first().label)
    }

    @Test
    fun duckPowerUpdateReflectsInStatusRow() = runTest(dispatcher) {
        val userRepo = FakeUserRepository()
        val vm = HomeViewModel(userRepo, FakeVocabRepository())
        advanceUntilIdle()
        assertEquals(450, (vm.uiState.value as HomeUiState.Success).duckPower)

        userRepo.addDuckPower(50)
        advanceUntilIdle()
        assertEquals(500, (vm.uiState.value as HomeUiState.Success).duckPower)
    }

    @Test
    fun bandLabelIncludesSharedSectionName() {
        val levels = listOf(
            Level(1, "Daily Life: people and family", 4.0, true),
            Level(2, "Daily Life: people and family", 4.0, false),
        )

        assertEquals("IELTS Band 4: Daily Life", buildBandSections(levels).single().label)
    }

    @Test
    fun refreshWhenVisibleReloadsUnlockedLevelState() = runTest(dispatcher) {
        val vocabRepo = FakeVocabRepository()
        val vm = HomeViewModel(FakeUserRepository(), vocabRepo)
        advanceUntilIdle()

        var levels = (vm.uiState.value as HomeUiState.Success).bands.flatMap { it.levels }
        assertTrue(levels.first { it.number == 1 }.isUnlocked)
        assertTrue(!levels.first { it.number == 2 }.isUnlocked)

        vocabRepo.replaceLevelsForTest(
            (1..240).map { number ->
                Level(
                    number = number,
                    title = "Level $number",
                    bandScore = when {
                        number <= 54 -> 4.0
                        number <= 81 -> 4.5
                        number <= 99 -> 5.0
                        number <= 126 -> 5.5
                        number <= 144 -> 6.0
                        number <= 162 -> 6.5
                        number <= 180 -> 7.0
                        number <= 210 -> 7.5
                        else -> 8.0
                    },
                    isUnlocked = number <= 2,
                    isCompleted = number == 1,
                    bestAccuracy = if (number == 1) 1f else 0f,
                    bestStarRating = if (number == 1) 3 else 0,
                    completedSessionCount = if (number == 1) 1 else 0,
                )
            },
        )

        vm.refreshWhenVisible()
        advanceUntilIdle()

        levels = (vm.uiState.value as HomeUiState.Success).bands.flatMap { it.levels }
        assertTrue(levels.first { it.number == 1 }.isCompleted)
        assertTrue(levels.first { it.number == 2 }.isUnlocked)
    }

    @Test
    fun homeReflectsLevelOneToFiveUnlockProgressionFromRepository() = runTest(dispatcher) {
        val vocabRepo = FakeVocabRepository()
        vocabRepo.replaceLevelsForTest(
            (1..240).map { number ->
                Level(
                    number = number,
                    title = "Level $number",
                    bandScore = when {
                        number <= 54 -> 4.0
                        number <= 81 -> 4.5
                        number <= 99 -> 5.0
                        number <= 126 -> 5.5
                        number <= 144 -> 6.0
                        number <= 162 -> 6.5
                        number <= 180 -> 7.0
                        number <= 210 -> 7.5
                        else -> 8.0
                    },
                    isUnlocked = number <= 5,
                    isCompleted = number in 1..4,
                    bestAccuracy = if (number in 1..4) 0.95f else 0f,
                    bestStarRating = if (number in 1..4) 3 else 0,
                    completedSessionCount = if (number in 1..4) 1 else 0,
                )
            },
        )
        val vm = HomeViewModel(FakeUserRepository(), vocabRepo)

        advanceUntilIdle()

        val levels = (vm.uiState.value as HomeUiState.Success).bands
            .first { it.score == 4.0 }
            .levels
        assertTrue(levels.filter { it.number in 1..5 }.all { it.isUnlocked })
        assertTrue(levels.filter { it.number in 1..4 }.all { it.isCompleted })
        assertTrue(!levels.first { it.number == 5 }.isCompleted)
        assertTrue(!levels.first { it.number == 6 }.isUnlocked)
    }

    @Test
    fun topicDisplayNumberResetsForEachTopic() {
        val levels = listOf(
            Level(1, "Daily Life: people and family", 4.0, true),
            Level(2, "Daily Life: people and family", 4.0, false),
            Level(3, "Daily Life: home and objects", 4.0, false),
        )

        assertEquals("People and family (1)", levelTopicDisplayName(levels, 0))
        assertEquals("People and family (2)", levelTopicDisplayName(levels, 1))
        assertEquals("Home and objects (1)", levelTopicDisplayName(levels, 2))
    }
}
