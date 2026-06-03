package com.example.firsttest.data.model

/** 我的道具 — a stack of one item type the user owns. Source: spec 2.4 / 2.2.2. */
data class Prop(
    val type: PropType,
    val count: Int,
)

enum class PropType(val displayName: String) {
    STREAK_PROTECTION("连胜保护"),  // max 2 (spec 2.4.1)
    CHALLENGE_KEY("挑战赛钥匙"),
}
