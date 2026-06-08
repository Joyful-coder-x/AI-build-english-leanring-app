package com.example.firsttest.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.PracticeCard
import com.example.firsttest.data.repository.PracticeRepository
import com.example.firsttest.data.repository.UserRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed interface HomeUiState {
    data object Loading : HomeUiState
    data class Success(
        val duckPower: Int,
        val streakDays: Int,
        val streakGoal: Int,
        val cards: List<PracticeCard>,
    ) : HomeUiState
}

/**
 * Drives the Home / 首页 learning-path screen.
 *
 * The status row (duck power, streak) is reactive: it collects
 * [UserRepository.userFlow] so it auto-updates when duck power is earned in a
 * practice session without any manual refresh.
 *
 * The learning-path card list is loaded once (it is static fake data for now).
 * TODO PHASE 3: reload cards from Supabase when user-progress changes
 *   (level unlocks, practiced state persisted in practice_sessions table).
 */
class HomeViewModel(
    private val userRepository: UserRepository,
    private val practiceRepository: PracticeRepository,
) : ViewModel() {

    private val _cards = MutableStateFlow<List<PracticeCard>>(emptyList())

    val uiState: StateFlow<HomeUiState> = combine(
        userRepository.userFlow(),
        _cards,
    ) { user, cards ->
        if (cards.isEmpty()) HomeUiState.Loading
        else HomeUiState.Success(
            duckPower  = user.duckPower,
            streakDays = user.streak.currentDays,
            streakGoal = user.streak.goalDays,
            cards      = cards,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.Eagerly,
        initialValue = HomeUiState.Loading,
    )

    init {
        viewModelScope.launch {
            _cards.value = practiceRepository.getDailyPractice()
        }
    }

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer { HomeViewModel(AppRepositories.user, AppRepositories.practice) }
        }
    }
}
