package com.example.firsttest.data.model

/**
 * A logged-in user's profile and progress.
 *
 * This is "app data" — it will live in Supabase later (Phase 4). For now it is
 * served by FakeUserRepository. See ARCHITECTURE.md.
 */
data class User(
    val id: String,                 // 用户ID — unique, system-assigned, immutable
    val nickname: String,           // 昵称
    val avatarUrl: String?,         // null -> use default avatar
    val phone: String?,             // null -> not bound yet
    val duckPower: Int,             // 鸭力值 — total EXP earned by answering
    val userLevel: UserLevel,       // 当前英语等级
    val abilityRadar: AbilityRadar, // 能力雷达图
    val streak: StreakInfo,         // 夸夸连胜
    val props: List<Prop>,          // 我的道具
) {
    /** 鸭力称号 — derived from [duckPower] (not stored separately). */
    val duckTitle: DuckTitle get() = DuckTitle.forDuckPower(duckPower)
}
