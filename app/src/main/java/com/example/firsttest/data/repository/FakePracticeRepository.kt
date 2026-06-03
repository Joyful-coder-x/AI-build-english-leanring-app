package com.example.firsttest.data.repository

import com.example.firsttest.data.model.CardState
import com.example.firsttest.data.model.PracticeCard
import com.example.firsttest.data.model.PracticeCardType

/**
 * In-memory fake daily practice, mirroring the home (每日练习/首页) prototype:
 * one practiced drill, one unlocked drill, then locked content.
 */
class FakePracticeRepository : PracticeRepository {
    override suspend fun getDailyPractice(): List<PracticeCard> = listOf(
        PracticeCard(
            id = "dt1",
            type = PracticeCardType.DUCK_TRAINING,
            state = CardState.PRACTICED,
            starRating = 2,
            duckPowerReward = 15,
        ),
        PracticeCard(
            id = "dt2",
            type = PracticeCardType.DUCK_TRAINING,
            state = CardState.UNLOCKED_UNPRACTICED,
            duckPowerReward = 15,
            subtitle = "现在啃单词，以后分数甜！冲鸭～",
        ),
        PracticeCard(
            id = "dt3",
            type = PracticeCardType.DUCK_TRAINING,
            state = CardState.LOCKED,
            duckPowerReward = 15,
        ),
        PracticeCard(id = "sc1", type = PracticeCardType.SCRATCH_CARD, state = CardState.LOCKED),
        PracticeCard(id = "ch1", type = PracticeCardType.CHALLENGE, state = CardState.LOCKED),
        PracticeCard(id = "unlock", type = PracticeCardType.UNLOCK_MORE, state = CardState.LOCKED),
    )
}
