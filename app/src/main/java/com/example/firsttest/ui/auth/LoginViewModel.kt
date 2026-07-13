package com.example.firsttest.ui.auth

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

enum class AuthMode { SIGN_IN, REGISTER }

data class LoginUiState(
    val mode: AuthMode = AuthMode.SIGN_IN,
    val username: String = "",
    val password: String = "",
    val confirmPassword: String = "",
    val acceptedTerms: Boolean = false,
    val isLoading: Boolean = false,
    val message: String? = null,
)

class LoginViewModel(
    private val authRepository: AuthRepository,
) : ViewModel() {
    private val mutableState = MutableStateFlow(LoginUiState())
    val uiState: StateFlow<LoginUiState> = mutableState.asStateFlow()

    fun setMode(mode: AuthMode) = mutableState.update {
        LoginUiState(mode = mode, username = it.username)
    }
    fun setUsername(value: String) = mutableState.update { it.copy(username = value, message = null) }
    fun setPassword(value: String) = mutableState.update { it.copy(password = value, message = null) }
    fun setConfirmPassword(value: String) =
        mutableState.update { it.copy(confirmPassword = value, message = null) }
    fun setAcceptedTerms(value: Boolean) =
        mutableState.update { it.copy(acceptedTerms = value, message = null) }

    fun submit() {
        val state = mutableState.value
        val error = validate(state)
        if (error != null) {
            mutableState.update { it.copy(message = error) }
            return
        }
        if (state.isLoading) return
        viewModelScope.launch {
            mutableState.update { it.copy(isLoading = true, message = null) }
            runCatching {
                if (state.mode == AuthMode.REGISTER) {
                    authRepository.register(state.username, state.password)
                    "Account created. Please sign in."
                } else {
                    authRepository.signIn(state.username, state.password)
                    null
                }
            }.onSuccess { message ->
                mutableState.update {
                    it.copy(
                        isLoading = false,
                        mode = if (message != null) AuthMode.SIGN_IN else it.mode,
                        password = "",
                        confirmPassword = "",
                        message = message,
                    )
                }
            }.onFailure { throwable ->
                mutableState.update {
                    it.copy(isLoading = false, message = authMessage(throwable))
                }
            }
        }
    }

    private fun validate(state: LoginUiState): String? {
        if (!USERNAME_REGEX.matches(state.username.trim().lowercase())) {
            return "Username must be 3-24 characters: letters, numbers, or underscore."
        }
        if (state.password.isEmpty()) return "Enter your password."
        if (state.mode == AuthMode.REGISTER) {
            if (state.password.length < MIN_PASSWORD_LENGTH) {
                return "Password must be at least $MIN_PASSWORD_LENGTH characters."
            }
            if (state.password != state.confirmPassword) return "Passwords do not match."
            if (!state.acceptedTerms) return "Accept the terms and privacy policy."
        }
        return null
    }

    companion object {
        private val USERNAME_REGEX = Regex("^[a-z][a-z0-9_]{2,23}$")
        private const val MIN_PASSWORD_LENGTH = 6

        internal fun authMessage(error: Throwable): String {
            val raw = error.message.orEmpty()
            return when {
                raw.contains("invalid login", ignoreCase = true) ->
                    "Incorrect username or password."
                raw.contains("already", ignoreCase = true) ->
                    "That username is already registered."
                raw.contains("weak_password", ignoreCase = true) ||
                    (raw.contains("password", ignoreCase = true) &&
                        raw.contains("characters", ignoreCase = true)) ->
                    "Password must be at least $MIN_PASSWORD_LENGTH characters."
                else -> "Authentication failed: ${debugAuthMessage(error, raw)}"
            }
        }

        private fun debugAuthMessage(error: Throwable, raw: String): String {
            val sanitized = raw
                .replace(Regex("https?://\\S+"), "[url]")
                .replace(Regex("(?i)(apikey|authorization)=\\S+"), "$1=[redacted]")
                .replace(Regex("(?i)(headers?:).*"), "$1 [redacted]")
                .trim()
            return sanitized.ifBlank { error::class.simpleName ?: "Unknown error" }
        }

        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer { LoginViewModel(AppRepositories.auth) }
        }
    }
}
