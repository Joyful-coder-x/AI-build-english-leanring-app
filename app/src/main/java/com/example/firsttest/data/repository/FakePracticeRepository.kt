package com.example.firsttest.data.repository

import com.example.firsttest.data.model.CardState
import com.example.firsttest.data.model.PracticeCard
import com.example.firsttest.data.model.PracticeCardType

/**
 * In-memory fake daily practice, mirroring the home (每日练习/首页) prototype
 * learning path: a finished drill, an active drill, an unlocked scratch card &
 * challenge, then still-locked content. Order = display order top→bottom.
 */
class FakePracticeRepository : PracticeRepository {
    override suspend fun getDailyPractice(): List<PracticeCard> = listOf(
        // 鸭力训练 1 — completed, 3 stars
        PracticeCard(
            id = "dt1",
            type = PracticeCardType.DUCK_TRAINING,
            state = CardState.PRACTICED,
            starRating = 3,
            duckPowerReward = 15,
        ),
        // 鸭力训练 2 — unlocked, not yet practiced
        PracticeCard(
            id = "dt2",
            type = PracticeCardType.DUCK_TRAINING,
            state = CardState.UNLOCKED_UNPRACTICED,
            duckPowerReward = 15,
            subtitle = "现在啃单词，以后分数甜！冲鸭～",
        ),
        // 刮刮卡 — unlocked
        PracticeCard(
            id = "sc1",
            type = PracticeCardType.SCRATCH_CARD,
            state = CardState.UNLOCKED_UNPRACTICED,
            subtitle = "刮一刮，今日份盲盒惊喜~",
        ),
        // 挑战赛 — unlocked
        PracticeCard(
            id = "ch1",
            type = PracticeCardType.CHALLENGE,
            state = CardState.UNLOCKED_UNPRACTICED,
            subtitle = "拼手速更拼脑速！",
        ),
        // 鸭力训练 3 — locked
        PracticeCard(
            id = "dt3",
            type = PracticeCardType.DUCK_TRAINING,
            state = CardState.LOCKED,
            duckPowerReward = 15,
        ),
        // 解锁更多 — locked until all previous cards are completed
        PracticeCard(id = "unlock", type = PracticeCardType.UNLOCK_MORE, state = CardState.LOCKED),
    )
}
