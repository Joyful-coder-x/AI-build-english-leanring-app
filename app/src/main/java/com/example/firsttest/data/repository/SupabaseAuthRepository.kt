package com.example.firsttest.data.repository

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class SupabaseAuthRepository(
    private val client: SupabaseClient,
) : AuthRepository {

    override fun authState(): Flow<AuthState> =
        client.auth.sessionStatus.map { status ->
            when (status) {
                SessionStatus.Initializing -> AuthState.Restoring
                is SessionStatus.Authenticated -> AuthState.SignedIn(
                    userId = requireNotNull(status.session.user?.id),
                    email = status.session.user?.email.orEmpty(),
                )
                is SessionStatus.NotAuthenticated,
                is SessionStatus.RefreshFailure -> AuthState.SignedOut
            }
        }

    override suspend fun register(username: String, password: String) {
        val normalizedUsername = normalizeUsername(username)
        client.auth.signUpWith(Email, redirectUrl = null) {
            email = internalEmail(normalizedUsername)
            this.password = password
            data = buildJsonObject {
                put("username", normalizedUsername)
                put("nickname", username.trim())
                put("timezone", java.util.TimeZone.getDefault().id)
                put("terms_version", "2026-06-01")
                put("privacy_version", "2026-06-01")
            }
        }
        // With email confirmation disabled, Supabase signs the new user in
        // automatically. End that session so registration returns to login.
        client.auth.signOut()
    }

    override suspend fun signIn(username: String, password: String) {
        client.auth.signInWith(Email) {
            email = internalEmail(normalizeUsername(username))
            this.password = password
        }
    }

    override suspend fun changePassword(currentPassword: String, newPassword: String) {
        require(currentPassword != newPassword) {
            "New password must be different from the current password."
        }
        val email = client.auth.currentUserOrNull()?.email ?: error("No authenticated user.")
        client.auth.signInWith(Email) {
            this.email = email
            password = currentPassword
        }
        client.auth.updateUser {
            password = newPassword
            this.currentPassword = currentPassword
        }
    }

    override suspend fun signOut() {
        client.auth.signOut()
    }

    companion object {
        private const val INTERNAL_EMAIL_DOMAIN = "login.kuakuaduck.invalid"

        fun normalizeUsername(value: String): String = value.trim().lowercase()
        fun internalEmail(username: String): String =
            "${normalizeUsername(username)}@$INTERNAL_EMAIL_DOMAIN"

        fun isInternalEmail(email: String?): Boolean =
            email?.endsWith("@$INTERNAL_EMAIL_DOMAIN", ignoreCase = true) == true
    }
}
