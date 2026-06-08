package com.example.firsttest.data.repository

import com.example.firsttest.data.model.AbilityRadar
import com.example.firsttest.data.model.Prop
import com.example.firsttest.data.model.PropType
import com.example.firsttest.data.model.StreakInfo
import com.example.firsttest.data.model.User
import com.example.firsttest.data.model.UserLevel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * In-memory [UserRepository] backed by a [MutableStateFlow].
 *
 * Because the state is held in a [MutableStateFlow], any call to [addDuckPower]
 * immediately emits a new [User] on [userFlow], so all collecting ViewModels
 * (Profile, Home status row) update automatically — no manual refresh needed.
 *
 * The initial values mirror the prototype (spec 2.1 personal-centre screen).
 *
 * TODO PHASE 4: replace with SupabaseUserRepository(Supabase.client) in
 *   AppRepositories once the `profiles` table exists. The fake initial values
 *   (nickname, level, radar, streak, props) will come from Supabase at that point.
 */
class FakeUserRepository : UserRepository {

    private val _state = MutableStateFlow(buildInitialUser())

    override fun userFlow(): Flow<User> = _state.asStateFlow()

    override suspend fun getCurrentUser(): User = _state.value

    /** Adds duck power and re-emits on [userFlow] so all UIs reflect the change. */
    override suspend fun addDuckPower(amount: Int) {
        _state.update { it.copy(duckPower = it.duckPower + amount) }
        // duckTitle is a derived property on User, so it auto-updates with duckPower.
    }

    companion object {
        private fun buildInitialUser() = User(
            id = "ksdfj76239skd",
            nickname = "leoninebess",
            avatarUrl = null,
            phone = null,
            duckPower = 450,                 // → 初学鸭 (0–499)
            userLevel = UserLevel(
                levelNumber = 20,
                ieltsBand = 5.5,
                levelName = "脆皮新生",
                progress = 0.4f,
            ),
            // TODO PHASE 4: ability radar will come from assessment_results in Supabase.
            abilityRadar = AbilityRadar(
                ieltsScore = 5.5,
                vocabulary = AbilityRadar.Axis(current = 7f, previous = 5f),
                listening  = AbilityRadar.Axis(current = 6f, previous = 5f),
                speaking   = AbilityRadar.Axis(current = 5f, previous = 4f),
                reading    = AbilityRadar.Axis(current = 6.5f, previous = 5f),
                writing    = AbilityRadar.Axis(current = 5.5f, previous = 4.5f),
            ),
            // TODO PHASE 2: streak must update after each daily check-in (spec 2.4.1).
            streak = StreakInfo(currentDays = 5, goalDays = 7),
            // TODO PHASE 2: props must update when earned via scratch card (spec 2.4).
            props = listOf(
                Prop(PropType.STREAK_PROTECTION, count = 2),
                Prop(PropType.CHALLENGE_KEY, count = 3),
            ),
        )
    }
}
