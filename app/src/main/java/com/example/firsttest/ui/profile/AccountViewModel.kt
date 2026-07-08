package com.example.firsttest.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.repository.AuthRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class AccountUiState(
    val currentPassword: String = "",
    val newPassword: String = "",
    val isLoading: Boolean = false,
    val message: String? = null,
)

class AccountViewModel(
    private val authRepository: AuthRepository,
) : ViewModel() {
    private val mutableState = MutableStateFlow(AccountUiState())
    val uiState: StateFlow<AccountUiState> = mutableState.asStateFlow()

    fun setCurrentPassword(value: String) =
        mutableState.update { it.copy(currentPassword = value, message = null) }

    fun setNewPassword(value: String) =
        mutableState.update { it.copy(newPassword = value, message = null) }

    fun changePassword() {
        val state = mutableState.value
        val error = when {
            state.currentPassword.isEmpty() -> "Enter your current password."
            state.newPassword.isEmpty() -> "Enter a new password."
            state.currentPassword == state.newPassword ->
                "New password must be different from the current password."
            else -> null
        }
        if (error != null) {
            mutableState.update { it.copy(message = error) }
            return
        }
        viewModelScope.launch {
            mutableState.update { it.copy(isLoading = true, message = null) }
            runCatching {
                authRepository.changePassword(state.currentPassword, state.newPassword)
            }.onSuccess {
                mutableState.value = AccountUiState(message = "Password changed.")
            }.onFailure { throwable ->
                mutableState.update {
                    it.copy(
                        isLoading = false,
                        message = throwable.message ?: "Unable to change password.",
                    )
                }
            }
        }
    }

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer { AccountViewModel(AppRepositories.auth) }
        }
    }
}
