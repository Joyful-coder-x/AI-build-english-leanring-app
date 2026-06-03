package com.example.firsttest.data.model

/**
 * 能力雷达图 — 5-axis ability scores (each 0..10), showing current vs previous
 * so the user can see their change. Source: spec 2.1.3 英语水平展示.
 */
data class AbilityRadar(
    val ieltsScore: Double,  // overall, e.g. 5.5 ("词汇达到雅思5.5分水平")
    val vocabulary: Axis,    // 单词
    val listening: Axis,     // 听力
    val speaking: Axis,      // 口语
    val reading: Axis,       // 阅读
    val writing: Axis,       // 写作
) {
    /** One radar axis: [current] highlighted, [previous] shown greyed for comparison. */
    data class Axis(val current: Float, val previous: Float)
}
