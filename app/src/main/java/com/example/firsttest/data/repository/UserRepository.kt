package com.example.firsttest.data.repository

import com.example.firsttest.data.model.Award
import com.example.firsttest.data.model.PropType
import com.example.firsttest.data.model.User
import kotlinx.coroutines.flow.Flow

/**
 * Source of the current user's profile and progress data.
 *
 * [userFlow] emits the latest [User] whenever any property changes (e.g. after
 * [addDuckPower]). ViewModels that display user state should collect this Flow
 * so they automatically reflect updates made by other ViewModels in the same
 * session.
 *
 * Phase 1-3 uses [FakeUserRepository] (shared singleton via AppRepositories).
 *
 * TODO PHASE 4: implement SupabaseUserRepository backed by the `profiles` table.
 *   - [getCurrentUser]: SELECT from profiles WHERE id = auth.uid()
 *   - [addDuckPower]:   UPDATE profiles SET duck_power = duck_power + amount WHERE id = auth.uid()
 *   - [userFlow]:       either re-read after each write, or use Supabase Realtime
 *   NOTE: the `profiles` table does not yet exist in Supabase — create it from
 *   docs/architecture/DATA_MODEL_AND_CAPACITY.md §5 before implementing this.
 */
interface UserRepository {
    /** Returns a hot [Flow] that re-emits whenever the user's data changes. */
    fun userFlow(): Flow<User>

    /** Latest snapshot — use [userFlow] for reactive UIs. */
    suspend fun getCurrentUser(): User

    /**
     * Adds [amount] 鸭力值 to the user's total.
     * Called by [com.example.firsttest.ui.practice.PracticeViewModel] at the end
     * of a practice session (spec 2.4.2 积分系统).
     *
     * TODO PHASE 4: persist via Supabase UPDATE on `profiles.duck_power`.
     */
    suspend fun addDuckPower(amount: Int)

    /** Records today's check-in. Increments streak and advances goal if the current goal is reached. */
    suspend fun checkInToday()

    /** Adds [count] of [type] to the user's prop inventory. */
    suspend fun addProp(type: PropType, count: Int = 1)

    /** Marks onboarding complete; [userFlow] will emit a user with [User.onboardingCompleted] = true. */
    suspend fun completeOnboarding()

    /** All badges earned so far (masterplan Feature J), most recent first. */
    suspend fun getAwards(): List<Award>
}
