package com.example.firsttest.ui.streak

import com.example.firsttest.data.repository.FakeUserRepository
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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.Calendar

@OptIn(ExperimentalCoroutinesApi::class)
class StreakViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun startsLoading() {
        val vm = StreakViewModel(FakeUserRepository(), FakeVocabRepository())
        assertEquals(StreakUiState.Loading, vm.uiState.value)
    }

    @Test
    fun emitsSuccessWithFakeStreakValues() = runTest(dispatcher) {
        val vm = StreakViewModel(FakeUserRepository(), FakeVocabRepository())
        advanceUntilIdle()
        val s = vm.uiState.value as StreakUiState.Success
        assertEquals(5, s.currentDays)
        assertEquals(7, s.goalDays)
        assertEquals(2, s.streakProtectionCount)
        assertEquals(3, s.challengeKeyCount)
    }

    @Test
    fun calendarHasTodayCell() = runTest(dispatcher) {
        val vm = StreakViewModel(FakeUserRepository(), FakeVocabRepository())
        advanceUntilIdle()
        val s = vm.uiState.value as StreakUiState.Success
        assertTrue(s.calendarDays.filterNotNull().any { it.state == DayState.TODAY })
    }

    @Test
    fun calendarChecksDaysWithCompletedSessions() = runTest(dispatcher) {
        val vm = StreakViewModel(FakeUserRepository(), FakeVocabRepository())
        advanceUntilIdle()
        val s = vm.uiState.value as StreakUiState.Success
        val checkedCount = s.calendarDays.filterNotNull().count { it.state == DayState.CHECKED }
        // FakeVocabRepository always includes "today" among its session dates, and
        // today's cell renders as TODAY rather than CHECKED, so it's excluded here.
        assertEquals(s.checkedThisMonth - 1, checkedCount)
    }

    @Test
    fun buildCalendarReturnsMultipleOfSeven() {
        val cal = Calendar.getInstance()
        val days = StreakViewModel.buildCalendar(setOf(5), cal)
        assertEquals(0, days.size % 7)
    }

    @Test
    fun duckPowerUpdateReflectsInStreak() = runTest(dispatcher) {
        val repo = FakeUserRepository()
        val vm = StreakViewModel(repo, FakeVocabRepository())
        advanceUntilIdle()

        // addDuckPower should not break streak display
        repo.addDuckPower(50)
        advanceUntilIdle()
        assertTrue(vm.uiState.value is StreakUiState.Success)
    }
}
