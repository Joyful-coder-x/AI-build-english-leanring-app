package com.example.firsttest.ui.streak

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
import java.util.Calendar

@OptIn(ExperimentalCoroutinesApi::class)
class StreakViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun startsLoading() {
        assertEquals(StreakUiState.Loading, StreakViewModel(FakeUserRepository()).uiState.value)
    }

    @Test
    fun emitsSuccessWithFakeStreakValues() = runTest(dispatcher) {
        val vm = StreakViewModel(FakeUserRepository())
        advanceUntilIdle()
        val s = vm.uiState.value as StreakUiState.Success
        assertEquals(5, s.currentDays)
        assertEquals(7, s.goalDays)
        assertEquals(2, s.streakProtectionCount)
        assertEquals(3, s.challengeKeyCount)
    }

    @Test
    fun calendarHasTodayCell() = runTest(dispatcher) {
        val vm = StreakViewModel(FakeUserRepository())
        advanceUntilIdle()
        val s = vm.uiState.value as StreakUiState.Success
        assertTrue(s.calendarDays.filterNotNull().any { it.state == DayState.TODAY })
    }

    @Test
    fun calendarCheckedDayCountMatchesCurrentDays() = runTest(dispatcher) {
        val vm = StreakViewModel(FakeUserRepository())
        advanceUntilIdle()
        val s = vm.uiState.value as StreakUiState.Success
        // TODAY + CHECKED days together should equal currentDays (5)
        val checkedAndToday = s.calendarDays.filterNotNull()
            .count { it.state == DayState.CHECKED || it.state == DayState.TODAY }
        assertEquals(s.currentDays, checkedAndToday)
    }

    @Test
    fun buildCalendarReturnsMultipleOfSeven() {
        val cal = Calendar.getInstance()
        val days = StreakViewModel.buildCalendar(5, cal)
        assertEquals(0, days.size % 7)
    }

    @Test
    fun duckPowerUpdateReflectsInStreak() = runTest(dispatcher) {
        val repo = FakeUserRepository()
        val vm = StreakViewModel(repo)
        advanceUntilIdle()

        // addDuckPower should not break streak display
        repo.addDuckPower(50)
        advanceUntilIdle()
        assertTrue(vm.uiState.value is StreakUiState.Success)
    }
}
