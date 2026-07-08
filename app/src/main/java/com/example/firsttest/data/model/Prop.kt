package com.example.firsttest.data.model

/** 我的道具 — a stack of one item type the user owns. Source: spec 2.4 / 2.2.2. */
data class Prop(
    val type: PropType,
    val count: Int,
)

enum class PropType(val displayName: String, val dbValue: String) {
    STREAK_PROTECTION("连胜保护", "streak_protection"),  // max 2 (spec 2.4.1)
    CHALLENGE_KEY("挑战赛钥匙", "challenge_key");

    companion object {
        fun fromDbValue(value: String): PropType? = entries.firstOrNull { it.dbValue == value }
    }
}
