package com.example.firsttest.data.repository

import com.example.firsttest.data.model.AbilityRadar
import com.example.firsttest.data.model.Prop
import com.example.firsttest.data.model.PropType
import com.example.firsttest.data.model.StreakInfo
import com.example.firsttest.data.model.User
import com.example.firsttest.data.model.UserLevel
import com.example.firsttest.data.remote.DbGrantPropParams
import com.example.firsttest.data.remote.DbGrantPropResult
import com.example.firsttest.data.remote.DbLevelNumber
import com.example.firsttest.data.remote.DbProfile
import com.example.firsttest.data.remote.DbUserProp
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.rpc
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

class SupabaseUserRepository(
    private val client: SupabaseClient,
) : UserRepository, SessionUserRepository {
    private val state = MutableStateFlow(emptyUser())

    override fun userFlow(): Flow<User> = state.asStateFlow()
    override suspend fun getCurrentUser(): User = state.value

    override suspend fun refreshCurrentUser() {
        val authUser = client.auth.currentUserOrNull() ?: error("No authenticated user.")
        var profile: DbProfile? = null
        for (attempt in 1..4) {
            profile = client.from("profiles")
                .select(Columns.list(
                    "id, public_user_code, username, nickname, avatar_path, " +
                        "duck_power, current_streak_days, longest_streak_days, " +
                        "last_practice_date, onboarding_status"
                )) {
                    filter { eq("id", authUser.id) }
                    limit(1)
                }
                .decodeSingleOrNull()
            if (profile != null) break
            delay(250L * attempt)
        }
        val p = requireNotNull(profile) { "Profile was not created for this account." }

        // Highest unlocked level → real userLevel + vocabulary radar axis.
        val highestUnlocked = client.from("user_level_progress")
            .select(Columns.raw("level_number, progress")) {
                filter { eq("is_unlocked", true) }
                order("level_number", Order.DESCENDING)
                limit(1)
            }
            .decodeSingleOrNull<DbLevelNumber>()

        val propRows = client.from("user_props")
            .select(Columns.list("prop_type, count")) {
                filter { eq("user_id", authUser.id) }
            }
            .decodeList<DbUserProp>()

        state.value = p.toDomain(
            email = authUser.email?.takeUnless(SupabaseAuthRepository::isInternalEmail),
            highestLevel = highestUnlocked,
            propRows = propRows,
        )
    }

    override suspend fun clear() {
        state.value = emptyUser()
    }

    // Temporary local behavior until learning/reward RPCs are introduced.
    override suspend fun addDuckPower(amount: Int) {
        state.update { it.copy(duckPower = it.duckPower + amount) }
    }

    override suspend fun checkInToday() {
        state.update { it.copy(streak = it.streak.copy(currentDays = it.streak.currentDays + 1)) }
    }

    override suspend fun addProp(type: PropType, count: Int) {
        val result = client.postgrest.rpc(
            "grant_prop",
            DbGrantPropParams(propType = type.dbValue, count = count),
        ).decodeAs<DbGrantPropResult>()
        state.update { user ->
            val existing = user.props.firstOrNull { it.type == type }
            val props = if (existing == null) user.props + Prop(type, result.count) else {
                user.props.map { if (it.type == type) it.copy(count = result.count) else it }
            }
            user.copy(props = props)
        }
    }

    override suspend fun completeOnboarding() {
        error("Onboarding finalization is server-owned. Use the placement RPC.")
    }

    private fun DbProfile.toDomain(
        email: String?,
        highestLevel: DbLevelNumber?,
        propRows: List<DbUserProp>,
    ) = User(
        id = publicUserCode,
        nickname = nickname,
        avatarUrl = avatarPath,
        phone = null,
        duckPower = duckPower,
        userLevel = highestLevel?.let { levelToDomain(it) }
            ?: UserLevel(1, 4.0, "雅思4分难度", 0f),
        abilityRadar = radarFromLevel(highestLevel),
        streak = StreakInfo(
            currentDays = currentStreakDays,
            goalDays = nextStreakGoal(currentStreakDays),
        ),
        props = propRows.mapNotNull { row ->
            PropType.fromDbValue(row.propType)?.let { Prop(it, row.count) }
        },
        onboardingCompleted = onboardingStatus == "completed" || onboardingStatus == "skipped",
        username = username,
        email = email,
    )

    companion object {
        internal fun bandForLevel(levelNumber: Int): Double = when {
            levelNumber <= 54  -> 4.0
            levelNumber <= 81  -> 4.5
            levelNumber <= 99  -> 5.0
            levelNumber <= 126 -> 5.5
            levelNumber <= 144 -> 6.0
            levelNumber <= 162 -> 6.5
            levelNumber <= 180 -> 7.0
            levelNumber <= 210 -> 7.5
            else               -> 8.0
        }

        private fun levelToDomain(row: DbLevelNumber): UserLevel {
            val band = bandForLevel(row.levelNumber)
            return UserLevel(
                levelNumber = row.levelNumber,
                ieltsBand   = band,
                levelName   = "雅思${formatBand(band)}分难度",
                progress    = row.progress.toFloat(),
            )
        }

        private fun formatBand(band: Double): String =
            if (band % 1.0 == 0.0) band.toInt().toString() else band.toString()

        private fun radarFromLevel(level: DbLevelNumber?): AbilityRadar {
            if (level == null) return zeroRadar()
            val band = bandForLevel(level.levelNumber)
            // Vocabulary axis: maps band 4.0→5.0 … 8.0→10.0 on a 0-10 scale.
            val vocabScore = ((band - 4.0) / 4.0 * 5.0 + 5.0).toFloat()
            return AbilityRadar(
                ieltsScore = band,
                vocabulary = AbilityRadar.Axis(current = vocabScore, previous = 0f),
                // TODO: listening/reading/speaking/writing require dedicated assessments;
                //   no data source exists yet — kept at 0 until those features are built.
                listening  = AbilityRadar.Axis(0f, 0f),
                speaking   = AbilityRadar.Axis(0f, 0f),
                reading    = AbilityRadar.Axis(0f, 0f),
                writing    = AbilityRadar.Axis(0f, 0f),
            )
        }

        private fun zeroRadar() = AbilityRadar(
            ieltsScore = 0.0,
            vocabulary = AbilityRadar.Axis(0f, 0f),
            listening  = AbilityRadar.Axis(0f, 0f),
            speaking   = AbilityRadar.Axis(0f, 0f),
            reading    = AbilityRadar.Axis(0f, 0f),
            writing    = AbilityRadar.Axis(0f, 0f),
        )

        private fun nextStreakGoal(days: Int): Int =
            listOf(1, 3, 7, 14, 20, 30)
                .firstOrNull { it > days }
                ?: (((days / 10) + 1) * 10)

        private fun emptyUser() = User(
            id = "",
            nickname = "",
            avatarUrl = null,
            phone = null,
            duckPower = 0,
            userLevel = UserLevel(1, 4.0, "雅思4分难度", 0f),
            abilityRadar = zeroRadar(),
            streak = StreakInfo(0, 1),
            props = emptyList(),
        )
    }
}
