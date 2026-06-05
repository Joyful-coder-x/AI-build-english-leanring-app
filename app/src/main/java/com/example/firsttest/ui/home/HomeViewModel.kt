package com.example.firsttest.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.PracticeCard
import com.example.firsttest.data.repository.FakePracticeRepository
import com.example.firsttest.data.repository.FakeUserRepository
import com.example.firsttest.data.repository.PracticeRepository
import com.example.firsttest.data.repository.UserRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** UI state for the Home / 每日练习 screen. */
sealed interface HomeUiState {
    data object Loading : HomeUiState
    data class Success(
        val duckPower: Int,      // 鸭力值 — top status row
        val streakDays: Int,     // 当前连胜天数
        val streakGoal: Int,     // 连胜目标
        val cards: List<PracticeCard>,  // 学习路径卡片 (display order)
    ) : HomeUiState
}

/**
 * Drives the Home learning-path screen. Reads the streak/鸭力值 status from a
 * [UserRepository] and the learning-path cards from a [PracticeRepository] —
 * both fakes in Phase 1. Swapping to real repos later changes only [Factory].
 */
class HomeViewModel(
    private val userRepository: UserRepository,
    private val practiceRepository: PracticeRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<HomeUiState>(HomeUiState.Loading)
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    init { load() }

    private fun load() {
        viewModelScope.launch {
            val user = userRepository.getCurrentUser()
            val cards = practiceRepository.getDailyPractice()
            _uiState.value = HomeUiState.Success(
                duckPower = user.duckPower,
                streakDays = user.streak.currentDays,
                streakGoal = user.streak.goalDays,
                cards = cards,
            )
        }
    }

    companion object {
        /** Phase 1: wires the in-memory fakes. */
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer { HomeViewModel(FakeUserRepository(), FakePracticeRepository()) }
        }
    }
}
