package com.example.firsttest.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.User
import com.example.firsttest.data.repository.FakeUserRepository
import com.example.firsttest.data.repository.UserRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** UI state for the Profile (个人中心) screen. */
sealed interface ProfileUiState {
    data object Loading : ProfileUiState
    data class Success(val user: User) : ProfileUiState
}

/**
 * Holds the Profile screen state. Reads from a [UserRepository] (the fake one
 * for now) and exposes an immutable [StateFlow] for the UI to observe.
 */
class ProfileViewModel(
    private val userRepository: UserRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<ProfileUiState>(ProfileUiState.Loading)
    val uiState: StateFlow<ProfileUiState> = _uiState.asStateFlow()

    init {
        loadUser()
    }

    private fun loadUser() {
        viewModelScope.launch {
            val user = userRepository.getCurrentUser()
            _uiState.value = ProfileUiState.Success(user)
        }
    }

    companion object {
        /**
         * Phase 1: wires the in-memory [FakeUserRepository]. In Phase 4 this is
         * the single place that changes to use a real (Supabase) repository.
         */
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer { ProfileViewModel(FakeUserRepository()) }
        }
    }
}
