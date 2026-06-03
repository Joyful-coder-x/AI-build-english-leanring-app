package com.example.firsttest.data.repository

import com.example.firsttest.data.model.AbilityRadar
import com.example.firsttest.data.model.Prop
import com.example.firsttest.data.model.PropType
import com.example.firsttest.data.model.StreakInfo
import com.example.firsttest.data.model.User
import com.example.firsttest.data.model.UserLevel

/**
 * In-memory fake user, mirroring the values shown in the 2.1 个人中心 prototype.
 * No backend involved — lets us build and preview the Profile screen immediately.
 */
class FakeUserRepository : UserRepository {
    override suspend fun getCurrentUser(): User = User(
        id = "ksdfj76239skd",
        nickname = "leoninebess",
        avatarUrl = null,
        phone = null,
        duckPower = 450,                 // -> 初学鸭 (0–499)
        userLevel = UserLevel(
            levelNumber = 20,
            ieltsBand = 5.5,
            levelName = "脆皮新生",
            progress = 0.4f,
        ),
        abilityRadar = AbilityRadar(
            ieltsScore = 5.5,
            vocabulary = AbilityRadar.Axis(current = 7f, previous = 5f),
            listening = AbilityRadar.Axis(current = 6f, previous = 5f),
            speaking = AbilityRadar.Axis(current = 5f, previous = 4f),
            reading = AbilityRadar.Axis(current = 6.5f, previous = 5f),
            writing = AbilityRadar.Axis(current = 5.5f, previous = 4.5f),
        ),
        streak = StreakInfo(currentDays = 5, goalDays = 7),
        props = listOf(
            Prop(PropType.STREAK_PROTECTION, count = 2),
            Prop(PropType.CHALLENGE_KEY, count = 3),
        ),
    )
}
