package com.example.firsttest.data.model

/**
 * 用户英语等级 — IELTS-band-based level. Source: spec 2.2.1 用户等级.
 * Levels run Lv1..Lv240, grouped into IELTS bands 4.0..8.0 (a band every 0.5).
 *
 * Note: the UI only ever shows level/progress going *up*. If the AI lowers a
 * user's level on a bad day, the front end keeps the current value (spec 2.2.1).
 */
data class UserLevel(
    val levelNumber: Int,   // e.g. 20  -> "LV 20"
    val ieltsBand: Double,  // e.g. 5.5
    val levelName: String,  // 等级名称, e.g. "脆皮新生"
    val progress: Float,    // 0f..1f progress within the current level
)
