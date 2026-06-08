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

@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun newVm() = HomeViewModel(FakeUserRepository(), FakePracticeRepository())

    @Test
    fun startsInLoadingState() {
        // Before dispatcher advances, combine hasn't emitted cards yet → Loading.
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
    fun sixCardsInCorrectOrderAndStates() = runTest(dispatcher) {
        val vm = newVm(); advanceUntilIdle()
        val cards = (vm.uiState.value as HomeUiState.Success).cards
        assertEquals(6, cards.size)

        // 0 — 鸭力训练 1: completed, 3 stars
        assertEquals(PracticeCardType.DUCK_TRAINING, cards[0].type)
        assertEquals(CardState.PRACTICED,            cards[0].state)
        assertEquals(3,                              cards[0].starRating)

        // 1 — 鸭力训练 2: unlocked
        assertEquals(PracticeCardType.DUCK_TRAINING,     cards[1].type)
        assertEquals(CardState.UNLOCKED_UNPRACTICED,     cards[1].state)

        // 2 — 刮刮卡: unlocked
        assertEquals(PracticeCardType.SCRATCH_CARD,      cards[2].type)
        assertEquals(CardState.UNLOCKED_UNPRACTICED,     cards[2].state)

        // 3 — 挑战赛: unlocked
        assertEquals(PracticeCardType.CHALLENGE,         cards[3].type)
        assertEquals(CardState.UNLOCKED_UNPRACTICED,     cards[3].state)

        // 4 — 鸭力训练 3: locked
        assertEquals(PracticeCardType.DUCK_TRAINING,     cards[4].type)
        assertEquals(CardState.LOCKED,                   cards[4].state)

        // 5 — 解锁更多: locked
        assertEquals(PracticeCardType.UNLOCK_MORE,       cards[5].type)
        assertEquals(CardState.LOCKED,                   cards[5].state)
    }

    @Test
    fun duckPowerUpdateReflectsInStatusRow() = runTest(dispatcher) {
        val userRepo = FakeUserRepository()
        val vm = HomeViewModel(userRepo, FakePracticeRepository())
        advanceUntilIdle()
        assertEquals(450, (vm.uiState.value as HomeUiState.Success).duckPower)

        userRepo.addDuckPower(50)
        advanceUntilIdle()
        assertEquals(500, (vm.uiState.value as HomeUiState.Success).duckPower)
    }
}
