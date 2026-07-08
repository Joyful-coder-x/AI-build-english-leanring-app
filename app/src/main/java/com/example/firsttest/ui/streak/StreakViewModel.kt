package com.example.firsttest.ui.streak

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.PropType
import com.example.firsttest.data.repository.UserRepository
import com.example.firsttest.data.repository.VocabRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.util.Calendar

enum class DayState { CHECKED, TODAY, MISSED, FUTURE }

data class CalendarDay(val dayOfMonth: Int, val state: DayState)

sealed interface StreakUiState {
    data object Loading : StreakUiState
    data class Success(
        val currentDays: Int,
        val goalDays: Int,
        val monthLabel: String,
        val calendarDays: List<CalendarDay?>,
        val checkedThisMonth: Int,
        val streakProtectionCount: Int,
        val challengeKeyCount: Int,
    ) : StreakUiState
}

/**
 * Drives the streak screen.
 *
 * Streak counters come from [UserRepository.userFlow]. Calendar check marks use
 * completed practice-session dates from [VocabRepository.getPracticeSessionDates],
 * which is also the source used by the Profile practice heatmap. The backend
 * round-completion RPC owns streak/reward updates; this screen reads the result.
 */
class StreakViewModel(
    userRepository: UserRepository,
    private val vocabRepository: VocabRepository,
) : ViewModel() {

    private val sessionDates = MutableStateFlow<List<LocalDate>>(emptyList())

    val uiState: StateFlow<StreakUiState> = combine(
        userRepository.userFlow(),
        sessionDates,
    ) { user, dates ->
        val now = Calendar.getInstance()
        val checkedDaysOfMonth = dates
            .filter { it.year == now.get(Calendar.YEAR) && it.monthValue == now.get(Calendar.MONTH) + 1 }
            .map { it.dayOfMonth }
            .toSet()
        StreakUiState.Success(
            currentDays = user.streak.currentDays,
            goalDays = user.streak.goalDays,
            monthLabel = formatMonth(now),
            calendarDays = buildCalendar(checkedDaysOfMonth, now),
            checkedThisMonth = checkedDaysOfMonth.size,
            streakProtectionCount = user.props.firstOrNull { it.type == PropType.STREAK_PROTECTION }?.count ?: 0,
            challengeKeyCount = user.props.firstOrNull { it.type == PropType.CHALLENGE_KEY }?.count ?: 0,
        )
    }.stateIn(viewModelScope, SharingStarted.Eagerly, StreakUiState.Loading)

    init {
        viewModelScope.launch {
            val dayOfMonth = Calendar.getInstance().get(Calendar.DAY_OF_MONTH)
            sessionDates.value = runCatching {
                vocabRepository.getPracticeSessionDates(recentDays = dayOfMonth)
            }.getOrDefault(emptyList())
        }
    }

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer { StreakViewModel(AppRepositories.user, AppRepositories.vocab) }
        }

        private fun formatMonth(cal: Calendar): String {
            val year = cal.get(Calendar.YEAR)
            val month = cal.get(Calendar.MONTH) + 1
            return "%04d-%02d".format(year, month)
        }

        /**
         * Builds a nullable 7-column calendar grid. Null entries pad the first
         * and last weeks so day cells align to Monday-based weeks.
         */
        internal fun buildCalendar(checkedDaysOfMonth: Set<Int>, today: Calendar): List<CalendarDay?> {
            val todayDom = today.get(Calendar.DAY_OF_MONTH)
            val daysInMonth = today.getActualMaximum(Calendar.DAY_OF_MONTH)
            val first = Calendar.getInstance().also {
                it.set(today.get(Calendar.YEAR), today.get(Calendar.MONTH), 1)
            }
            val leadingEmpties = (first.get(Calendar.DAY_OF_WEEK) - Calendar.MONDAY + 7) % 7

            val days = mutableListOf<CalendarDay?>()
            repeat(leadingEmpties) { days.add(null) }
            for (dom in 1..daysInMonth) {
                val state = when {
                    dom > todayDom -> DayState.FUTURE
                    dom == todayDom -> DayState.TODAY
                    dom in checkedDaysOfMonth -> DayState.CHECKED
                    else -> DayState.MISSED
                }
                days.add(CalendarDay(dom, state))
            }
            while (days.size % 7 != 0) days.add(null)
            return days
        }
    }
}
