package com.example.firsttest.data.repository

import kotlinx.coroutines.flow.Flow

sealed interface AuthState {
    data object Restoring : AuthState
    data object SignedOut : AuthState
    data class SignedIn(val userId: String, val email: String) : AuthState
}

interface AuthRepository {
    fun authState(): Flow<AuthState>
    suspend fun register(username: String, password: String)
    suspend fun signIn(username: String, password: String)
    suspend fun changePassword(currentPassword: String, newPassword: String)
    suspend fun signOut()
}
