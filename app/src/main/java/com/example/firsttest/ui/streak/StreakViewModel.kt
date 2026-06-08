package com.example.firsttest.ui.streak

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.PropType
import com.example.firsttest.data.repository.UserRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import java.util.Calendar

// ---- Calendar day -----------------------------------------------------------

enum class DayState { CHECKED, TODAY, MISSED, FUTURE }

data class CalendarDay(val dayOfMonth: Int, val state: DayState)

// ---- UI state ---------------------------------------------------------------

sealed interface StreakUiState {
    data object Loading : StreakUiState
    data class Success(
        val currentDays: Int,
        val goalDays: Int,
        val monthLabel: String,                    // "2026年6月"
        val calendarDays: List<CalendarDay?>,      // null = empty alignment slot
        val checkedThisMonth: Int,
        val streakProtectionCount: Int,
        val challengeKeyCount: Int,
    ) : StreakUiState
}

// ---- ViewModel --------------------------------------------------------------

/**
 * Drives the 每日连胜 screen (spec 2.4.1).
 *
 * Streak data comes from [UserRepository.userFlow] so it auto-updates when
 * duck power or other user fields change within the session.
 *
 * Calendar check-in state is derived from [currentDays]: the last N consecutive
 * days (including today) are shown as CHECKED.
 *
 * TODO PHASE 2: after completing a practice session (≥1★), automatically
 *   increment streak and update TODAY's calendar cell.
 *   Spec rule: one check-in per calendar day; check-in earned by ≥1★ in
 *   鸭力训练 OR by completing any 挑战赛 (spec 2.4.1).
 *   Also: if streak breaks and user has 连胜保护, auto-consume it and keep streak.
 * TODO PHASE 3: persist check-in history to Supabase `checkins` table.
 */
class StreakViewModel(
    userRepository: UserRepository,
) : ViewModel() {

    val uiState: StateFlow<StreakUiState> = userRepository
        .userFlow()
        .map { user ->
            val now = Calendar.getInstance()
            StreakUiState.Success(
                currentDays           = user.streak.currentDays,
                goalDays              = user.streak.goalDays,
                monthLabel            = formatMonth(now),
                calendarDays          = buildCalendar(user.streak.currentDays, now),
                checkedThisMonth      = minOf(user.streak.currentDays, now.get(Calendar.DAY_OF_MONTH)),
                streakProtectionCount = user.props.firstOrNull { it.type == PropType.STREAK_PROTECTION }?.count ?: 0,
                challengeKeyCount     = user.props.firstOrNull { it.type == PropType.CHALLENGE_KEY }?.count ?: 0,
            )
        }
        .stateIn(viewModelScope, SharingStarted.Eagerly, StreakUiState.Loading)

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer { StreakViewModel(AppRepositories.user) }
        }

        private fun formatMonth(cal: Calendar): String {
            val year = cal.get(Calendar.YEAR)
            val month = cal.get(Calendar.MONTH) + 1
            return "${year}年${month}月"
        }

        /**
         * Builds a list of nullable [CalendarDay] items for a 7-column grid.
         * null entries are used to pad the start of the first week so day 1
         * falls on the correct column (Mon-based week).
         */
        internal fun buildCalendar(currentDays: Int, today: Calendar): List<CalendarDay?> {
            val todayDom = today.get(Calendar.DAY_OF_MONTH)
            val daysInMonth = today.getActualMaximum(Calendar.DAY_OF_MONTH)

            // First day of this month — Mon=0 … Sun=6
            val first = Calendar.getInstance().also {
                it.set(today.get(Calendar.YEAR), today.get(Calendar.MONTH), 1)
            }
            val leadingEmpties = (first.get(Calendar.DAY_OF_WEEK) - Calendar.MONDAY + 7) % 7

            val firstCheckedDom = maxOf(1, todayDom - currentDays + 1)

            val days = mutableListOf<CalendarDay?>()
            repeat(leadingEmpties) { days.add(null) }
            for (dom in 1..daysInMonth) {
                val state = when {
                    dom > todayDom  -> DayState.FUTURE
                    dom == todayDom -> DayState.TODAY
                    dom >= firstCheckedDom -> DayState.CHECKED
                    else -> DayState.MISSED
                }
                days.add(CalendarDay(dom, state))
            }
            while (days.size % 7 != 0) days.add(null)
            return days
        }
    }
}
