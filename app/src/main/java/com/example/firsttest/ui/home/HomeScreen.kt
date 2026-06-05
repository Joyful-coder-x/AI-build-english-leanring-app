package com.example.firsttest.ui.home

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.example.firsttest.ui.common.PlaceholderScreen

/**
 * 每日练习 (首页) — the core learning-path screen.
 *
 * Phase 1 placeholder: the real learning path (2.2.2) wired to
 * [com.example.firsttest.data.repository.FakePracticeRepository] lands next.
 */
@Composable
fun HomeScreen(modifier: Modifier = Modifier) {
    PlaceholderScreen(
        title = "每日练习",
        subtitle = "首页 · 学习路径 (2.2) — 即将到来",
        modifier = modifier,
    )
}
