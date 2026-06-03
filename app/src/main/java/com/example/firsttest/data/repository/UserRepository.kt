package com.example.firsttest.data.repository

import com.example.firsttest.data.model.User

/**
 * Source of the current user's profile/progress data.
 *
 * Phase 1 uses [FakeUserRepository]. In Phase 4 a `SupabaseUserRepository` will
 * implement this same interface, and the UI/ViewModels will not change.
 * See ARCHITECTURE.md.
 */
interface UserRepository {
    suspend fun getCurrentUser(): User
}
