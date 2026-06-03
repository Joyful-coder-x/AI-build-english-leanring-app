package com.example.firsttest.data.model

/**
 * A single card in the home daily-practice learning path (首页学习路径).
 * Source: spec 2.2.2 学习路径.
 */
data class PracticeCard(
    val id: String,
    val type: PracticeCardType,
    val state: CardState,
    val starRating: Int = 0,       // 0..3, shown on a practiced 鸭力训练 card
    val duckPowerReward: Int = 0,  // 可获得的鸭力值
    val subtitle: String? = null,  // 小标题 — encouragement text (鸭力训练 cards)
)

/** 鸭力训练 (drill), 刮刮卡 (scratch card), 挑战赛 (challenge), 解锁更多 (unlock more). */
enum class PracticeCardType { DUCK_TRAINING, SCRATCH_CARD, CHALLENGE, UNLOCK_MORE }

/** 未解锁 / 已解锁未练习 / 已练习. */
enum class CardState { LOCKED, UNLOCKED_UNPRACTICED, PRACTICED }
