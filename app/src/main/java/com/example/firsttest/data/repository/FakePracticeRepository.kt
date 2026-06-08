package com.example.firsttest.data.repository

import com.example.firsttest.data.model.CardState
import com.example.firsttest.data.model.PracticeCard
import com.example.firsttest.data.model.PracticeCardType
import com.example.firsttest.data.model.Question

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

    /**
     * Returns three fake questions (2× MCQ, 1× keyboard) for any card.
     * All DUCK_TRAINING cards share the same question pool in Phase 2; a real
     * implementation fetches per-word questions from Supabase.
     */
    override suspend fun getQuestionsForCard(cardId: String): List<Question> = listOf(
        // Type 2 — multiple choice
        Question(
            id = "q1",
            typeCode = 2,
            promptHint = "请选择正确答案",
            stem = "The scientist made an important ___ that changed the world.",
            correctAnswer = "discovery",
            translationZh = "这位科学家做出了一个改变世界的重大发现。",
            options = listOf("discovery", "invention", "experiment", "observation"),
        ),
        // Type 1 — keyboard fill-in (stem shows first letter as hint per spec 2.2.3)
        Question(
            id = "q2",
            typeCode = 1,
            promptHint = "请拼写出完整的单词（首字母已给出）",
            stem = "She tried to a___ the difficult question by changing the subject.",
            correctAnswer = "avoid",
            translationZh = "她试图通过转移话题来回避这个棘手的问题。",
        ),
        // Type 2 — multiple choice
        Question(
            id = "q3",
            typeCode = 2,
            promptHint = "请选择正确答案",
            stem = "Mastering a new language requires great ___ and daily effort.",
            correctAnswer = "patience",
            translationZh = "掌握一门新语言需要极大的耐心和每天的努力。",
            options = listOf("patience", "practice", "passion", "persistence"),
        ),
    )
}
