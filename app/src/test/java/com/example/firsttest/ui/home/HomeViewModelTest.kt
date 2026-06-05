package com.example.firsttest.ui.home

import com.example.firsttest.data.model.CardState
import com.example.firsttest.data.model.PracticeCardType
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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for [HomeViewModel]'s data flow over the fake repositories.
 * A [StandardTestDispatcher] stands in for Dispatchers.Main so viewModelScope
 * work is controllable and deterministic.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun newViewModel() = HomeViewModel(FakeUserRepository(), FakePracticeRepository())

    @Test
    fun startsInLoadingState() {
        // Before the dispatcher runs the init coroutine, state is Loading.
        val vm = newViewModel()
        assertEquals(HomeUiState.Loading, vm.uiState.value)
    }

    @Test
    fun emitsSuccessWithStatusRowAndSixCards() = runTest(dispatcher) {
        val vm = newViewModel()
        advanceUntilIdle()

        val state = vm.uiState.value
        assertTrue("expected Success but was $state", state is HomeUiState.Success)
        state as HomeUiState.Success

        assertEquals(450, state.duckPower)
        assertEquals(5, state.streakDays)
        assertEquals(7, state.streakGoal)
        assertEquals(6, state.cards.size)
    }

    @Test
    fun cardsAreInExpectedOrderAndStates() = runTest(dispatcher) {
        val vm = newViewModel()
        advanceUntilIdle()
        val cards = (vm.uiState.value as HomeUiState.Success).cards

        // 0 — 鸭力训练 1: completed, 3 stars
        assertEquals("dt1", cards[0].id)
        assertEquals(PracticeCardType.DUCK_TRAINING, cards[0].type)
        assertEquals(CardState.PRACTICED, cards[0].state)
        assertEquals(3, cards[0].starRating)

        // 1 — 鸭力训练 2: unlocked, not practiced
        assertEquals("dt2", cards[1].id)
        assertEquals(PracticeCardType.DUCK_TRAINING, cards[1].type)
        assertEquals(CardState.UNLOCKED_UNPRACTICED, cards[1].state)

        // 2 — 刮刮卡: unlocked
        assertEquals(PracticeCardType.SCRATCH_CARD, cards[2].type)
        assertEquals(CardState.UNLOCKED_UNPRACTICED, cards[2].state)

        // 3 — 挑战赛: unlocked
        assertEquals(PracticeCardType.CHALLENGE, cards[3].type)
        assertEquals(CardState.UNLOCKED_UNPRACTICED, cards[3].state)

        // 4 — 鸭力训练 3: locked
        assertEquals(PracticeCardType.DUCK_TRAINING, cards[4].type)
        assertEquals(CardState.LOCKED, cards[4].state)

        // 5 — 解锁更多: locked
        assertEquals(PracticeCardType.UNLOCK_MORE, cards[5].type)
        assertEquals(CardState.LOCKED, cards[5].state)
    }
}
