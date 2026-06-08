package com.example.firsttest.ui.streak

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel

/** Day-of-week header labels, Mon-first (matches calendar grid). */
private val DOW_LABELS = listOf("一", "二", "三", "四", "五", "六", "日")

/**
 * 每日连胜 tab screen (spec 2.4.1).
 *
 * Shows streak count, goal progress bar, and a monthly calendar that marks
 * which days the user checked in. Props (连胜保护, 挑战赛钥匙) are shown at
 * the bottom.
 */
@Composable
fun StreakScreen(
    modifier: Modifier = Modifier,
    viewModel: StreakViewModel = viewModel(factory = StreakViewModel.Factory),
) {
    val uiState by viewModel.uiState.collectAsState()
    when (val s = uiState) {
        is StreakUiState.Loading ->
            Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }

        is StreakUiState.Success ->
            Column(
                modifier = modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                // ---- Title --------------------------------------------------
                Text(
                    "夸夸连胜",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                )

                // ---- Streak count + goal progress ---------------------------
                StreakHero(s.currentDays, s.goalDays)

                // ---- Monthly calendar ---------------------------------------
                CalendarCard(
                    monthLabel   = s.monthLabel,
                    calendarDays = s.calendarDays,
                )

                // ---- Stats row ----------------------------------------------
                StatsRow(
                    checkedThisMonth      = s.checkedThisMonth,
                    streakProtectionCount = s.streakProtectionCount,
                    challengeKeyCount     = s.challengeKeyCount,
                )

                Spacer(Modifier.height(8.dp))
            }
    }
}

// ---- Sub-components ---------------------------------------------------------

@Composable
private fun StreakHero(currentDays: Int, goalDays: Int) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("🔥", fontSize = 40.sp)
            Text(
                "${currentDays}天连胜！",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "目标：${goalDays}天",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            LinearProgressIndicator(
                progress = { (currentDays.toFloat() / goalDays).coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                "$currentDays / $goalDays 天",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun CalendarCard(monthLabel: String, calendarDays: List<CalendarDay?>) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                monthLabel,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            // Day-of-week header
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
                DOW_LABELS.forEach { label ->
                    Text(
                        label,
                        modifier = Modifier.weight(1f),
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            // Calendar grid — 7 columns
            calendarDays.chunked(7).forEach { week ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
                    week.forEach { day ->
                        DayCell(day, Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun DayCell(day: CalendarDay?, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .aspectRatio(1f)
            .padding(2.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (day == null) return@Box

        val bgColor = when (day.state) {
            DayState.CHECKED -> MaterialTheme.colorScheme.primary
            DayState.TODAY   -> MaterialTheme.colorScheme.primaryContainer
            else             -> Color.Transparent
        }
        val textColor = when (day.state) {
            DayState.CHECKED -> MaterialTheme.colorScheme.onPrimary
            DayState.TODAY   -> MaterialTheme.colorScheme.onPrimaryContainer
            DayState.FUTURE  -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f)
            DayState.MISSED  -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
        }

        Box(
            modifier = Modifier
                .size(30.dp)
                .clip(CircleShape)
                .background(bgColor),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "${day.dayOfMonth}",
                style = MaterialTheme.typography.labelSmall,
                color = textColor,
                fontWeight = if (day.state == DayState.TODAY) FontWeight.Bold else FontWeight.Normal,
            )
        }
    }
}

@Composable
private fun StatsRow(
    checkedThisMonth: Int,
    streakProtectionCount: Int,
    challengeKeyCount: Int,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        StatChip(Modifier.weight(1f), "📅", "本月打卡", "${checkedThisMonth}天")
        StatChip(Modifier.weight(1f), "🛡️", "连胜保护", "×$streakProtectionCount")
        StatChip(Modifier.weight(1f), "🔑", "挑战钥匙", "×$challengeKeyCount")
    }
}

@Composable
private fun StatChip(modifier: Modifier, icon: String, label: String, value: String) {
    Card(modifier) {
        Column(
            modifier = Modifier.padding(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(icon, fontSize = 20.sp)
            Text(value, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            Text(
                label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}
