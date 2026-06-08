package com.example.firsttest.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.User
import com.example.firsttest.data.repository.UserRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

sealed interface ProfileUiState {
    data object Loading : ProfileUiState
    data class Success(val user: User) : ProfileUiState
}

/**
 * Holds the Profile / 个人中心 screen state.
 *
 * Collects [UserRepository.userFlow] so the screen automatically reflects any
 * change made to the user's data — most importantly, duck power earned during a
 * practice session updates here without any explicit refresh call.
 */
class ProfileViewModel(
    userRepository: UserRepository,
) : ViewModel() {

    val uiState: StateFlow<ProfileUiState> = userRepository
        .userFlow()
        .map { user -> ProfileUiState.Success(user) as ProfileUiState }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.Eagerly,
            initialValue = ProfileUiState.Loading,
        )

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer { ProfileViewModel(AppRepositories.user) }
        }
    }
}
