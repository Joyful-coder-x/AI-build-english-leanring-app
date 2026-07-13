package com.example.firsttest.ui.session

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.NewAward
import com.example.firsttest.data.model.User
import com.example.firsttest.data.repository.AuthRepository
import com.example.firsttest.data.repository.AuthState
import com.example.firsttest.data.repository.OnboardingFlowState
import com.example.firsttest.data.repository.OnboardingRepository
import com.example.firsttest.data.repository.SessionUserRepository
import com.example.firsttest.data.repository.UserBootstrapState
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface AppSessionState {
    data object RestoringSession : AppSessionState
    data object SignedOut : AppSessionState
    data object LoadingBootstrap : AppSessionState
    data class QuestionnairePending(
        val user: User,
        val bootstrap: UserBootstrapState,
    ) : AppSessionState
    data class Authenticated(
        val user: User,
        val newAwards: List<NewAward> = emptyList(),
    ) : AppSessionState
    data class Error(val message: String) : AppSessionState
}

class AppSessionViewModel(
    private val authRepository: AuthRepository,
    private val userRepository: SessionUserRepository,
    private val onboardingRepository: OnboardingRepository,
) : ViewModel() {
    private val mutableState =
        MutableStateFlow<AppSessionState>(AppSessionState.RestoringSession)
    val uiState: StateFlow<AppSessionState> = mutableState.asStateFlow()
    private var hasRecordedLoginThisSession = false

    init {
        viewModelScope.launch {
            authRepository.authState().collect { auth ->
                when (auth) {
                    AuthState.Restoring -> mutableState.value = AppSessionState.RestoringSession
                    AuthState.SignedOut -> {
                        userRepository.clear()
                        hasRecordedLoginThisSession = false
                        mutableState.value = AppSessionState.SignedOut
                    }
                    is AuthState.SignedIn -> loadBootstrap()
                }
            }
        }
    }

    fun retry() {
        viewModelScope.launch { loadBootstrap() }
    }

    fun signOut() {
        viewModelScope.launch {
            runCatching { authRepository.signOut() }
                .onFailure {
                    mutableState.value = AppSessionState.Error(userFacingMessage(it))
                }
        }
    }

    /** Dismisses the celebration UI after new awards have been shown once. */
    fun clearNewAwards() {
        val current = mutableState.value
        if (current is AppSessionState.Authenticated && current.newAwards.isNotEmpty()) {
            mutableState.value = current.copy(newAwards = emptyList())
        }
    }

    private suspend fun recordLoginOnce(): List<NewAward> {
        if (hasRecordedLoginThisSession) return emptyList()
        hasRecordedLoginThisSession = true
        return runCatching { userRepository.recordLoginAndCheckAwards() }.getOrDefault(emptyList())
    }

    private suspend fun loadBootstrap() {
        mutableState.value = AppSessionState.LoadingBootstrap
        var user: User? = null
        try {
            userRepository.refreshCurrentUser()
            user = userRepository.getCurrentUser()
            val bootstrap = onboardingRepository.getBootstrapState()
            mutableState.value = when (bootstrap.flowState) {
                OnboardingFlowState.QUESTIONNAIRE_PENDING ->
                    AppSessionState.QuestionnairePending(user, bootstrap)
                OnboardingFlowState.ASSESSMENT_PENDING ->
                    AppSessionState.Error(
                        "Account setup is using the retired assessment flow. " +
                            "Apply the latest Supabase migration and retry."
                    )
                OnboardingFlowState.HOME_READY ->
                    AppSessionState.Authenticated(user, newAwards = recordLoginOnce())
                OnboardingFlowState.PLACEMENT_FINALIZED ->
                    AppSessionState.Error("Placement is still being finalized. Please retry.")
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Throwable) {
            mutableState.value =
                if (user != null && isMissingBootstrapRpc(error)) {
                    AppSessionState.Authenticated(user)
                } else {
                    AppSessionState.Error(userFacingMessage(error))
                }
        }
    }

    companion object {
        private fun isMissingBootstrapRpc(error: Throwable): Boolean {
            val raw = error.message.orEmpty()
            return raw.contains("PGRST202", ignoreCase = true) ||
                raw.contains("get_user_bootstrap_state", ignoreCase = true) ||
                raw.contains("schema cache", ignoreCase = true)
        }

        internal fun userFacingMessage(error: Throwable): String {
            val raw = error.message.orEmpty()
            return when {
                isMissingBootstrapRpc(error) ->
                    "Account setup is temporarily unavailable. Please try again later."
                raw.contains("profile was not created", ignoreCase = true) ->
                    "We couldn't finish setting up your account. Please sign out and register again."
                raw.contains("timeout", ignoreCase = true) ||
                    raw.contains("network", ignoreCase = true) ||
                    raw.contains("connection", ignoreCase = true) ->
                    "We couldn't connect to the server. Check your internet connection and try again."
                else -> "We couldn't load your account: ${debugSessionMessage(error, raw)}"
            }
        }

        private fun debugSessionMessage(error: Throwable, raw: String): String {
            val sanitized = raw
                .replace(Regex("https?://\\S+"), "[url]")
                .replace(Regex("(?i)(apikey|authorization)=\\S+"), "$1=[redacted]")
                .replace(Regex("(?i)(headers?:).*"), "$1 [redacted]")
                .trim()
            return sanitized.ifBlank { error::class.simpleName ?: "Unknown error" }
        }

        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                AppSessionViewModel(
                    AppRepositories.auth,
                    AppRepositories.user,
                    AppRepositories.onboarding,
                )
            }
        }
    }
}
