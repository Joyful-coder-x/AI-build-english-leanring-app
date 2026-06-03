package com.example.firsttest.data.model

/**
 * 夸夸连胜 — the user's consecutive daily check-in streak.
 * Source: spec 2.4.1 任务系统. Goal progression: 1, 3, 7, 14, 20, 30, then +10 each.
 */
data class StreakInfo(
    val currentDays: Int,  // 当前连胜天数
    val goalDays: Int,     // 当前连胜目标
)
