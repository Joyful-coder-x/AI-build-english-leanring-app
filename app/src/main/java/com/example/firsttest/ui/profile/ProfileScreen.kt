package com.example.firsttest.ui.profile

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.model.AbilityRadar
import com.example.firsttest.data.model.DuckTitle
import com.example.firsttest.data.model.Prop
import com.example.firsttest.data.model.PropType
import com.example.firsttest.data.model.StreakInfo
import com.example.firsttest.data.model.User
import com.example.firsttest.data.model.UserLevel
import com.example.firsttest.ui.theme.KuaKuaTheme
import java.time.LocalDate
import java.util.Calendar
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

@Composable
fun ProfileScreen(
    onReassessClick: () -> Unit = {},
    onSignOut: () -> Unit = {},
    viewModel: ProfileViewModel = viewModel(factory = ProfileViewModel.Factory),
    accountViewModel: AccountViewModel = viewModel(factory = AccountViewModel.Factory),
) {
    val uiState by viewModel.uiState.collectAsState()
    val accountState by accountViewModel.uiState.collectAsState()
    Scaffold(contentWindowInsets = WindowInsets(0, 0, 0, 0)) { innerPadding ->
        when (val state = uiState) {
            is ProfileUiState.Loading ->
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) { Text("加载中…") }

            is ProfileUiState.Success ->
                ProfileContent(
                    user = state.user,
                    sessionDates = state.sessionDates,
                    onReassessClick = onReassessClick,
                    onSignOut = onSignOut,
                    accountState = accountState,
                    onCurrentPasswordChanged = accountViewModel::setCurrentPassword,
                    onNewPasswordChanged = accountViewModel::setNewPassword,
                    onChangePassword = accountViewModel::changePassword,
                    modifier = Modifier.padding(innerPadding),
                )
        }
    }
}

@Composable
private fun ProfileContent(
    user: User,
    sessionDates: List<LocalDate>,
    onReassessClick: () -> Unit,
    onSignOut: () -> Unit,
    accountState: AccountUiState,
    onCurrentPasswordChanged: (String) -> Unit,
    onNewPasswordChanged: (String) -> Unit,
    onChangePassword: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        HeroCard(user)
        QuickStatsRow(user)
        StreakCard(user.streak)
        PracticeHeatmapCard(sessionDates)
        RadarCard(user, onReassessClick)
        if (user.props.isNotEmpty()) PropsCard(user.props)
        AccountSecurityCard(
            state = accountState,
            onCurrentPasswordChanged = onCurrentPasswordChanged,
            onNewPasswordChanged = onNewPasswordChanged,
            onChangePassword = onChangePassword,
        )
        OutlinedButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) {
            Text("退出登录")
        }
        Spacer(Modifier.height(8.dp))
    }
}

// ── Hero card ───────────────────────────────────────────────────────────────

@Composable
private fun HeroCard(user: User) {
    val (progress, nextTitle) = nextTitleProgress(user.duckPower, user.duckTitle)
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Text("⚙️", fontSize = 22.sp)
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(72.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("🦆", fontSize = 38.sp)
                }
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        text = user.nickname,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                    Surface(
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
                        shape = MaterialTheme.shapes.small,
                    ) {
                        Text(
                            text = user.duckTitle.displayName,
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 3.dp),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    Text(
                        text = "ID: ${user.id.take(8)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.55f),
                    )
                }
            }

            // Duck power progress to next title
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("⚡", fontSize = 15.sp)
                        Text(
                            text = "${user.duckPower} 鸭力值",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                    }
                    if (nextTitle != null) {
                        Text(
                            text = "→ ${nextTitle.displayName} (${nextTitle.minDuckPower})",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.65f),
                        )
                    } else {
                        Text(
                            text = "已达最高称号！",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(8.dp)
                        .clip(MaterialTheme.shapes.small),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.2f),
                )
            }
        }
    }
}

// ── Quick stats row (3 chips) ────────────────────────────────────────────────

@Composable
private fun QuickStatsRow(user: User) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        QuickStat(Modifier.weight(1f), "🎓", "LV ${user.userLevel.levelNumber}", user.userLevel.levelName)
        QuickStat(Modifier.weight(1f), "🔥", "${user.streak.currentDays}天", "连胜")
        QuickStat(Modifier.weight(1f), "📚", "${user.userLevel.ieltsBand}分", "雅思难度")
    }
}

@Composable
private fun QuickStat(modifier: Modifier, icon: String, value: String, label: String) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(
            modifier = Modifier
                .padding(10.dp)
                .fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(icon, fontSize = 20.sp)
            Text(
                text = value,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

// ── Streak card with week dots ───────────────────────────────────────────────

@Composable
private fun StreakCard(streak: StreakInfo) {
    // Mon=0 … Sun=6; dayOfWeek: Sun=1 Mon=2 … Sat=7
    val todayIndex = remember {
        val dow = Calendar.getInstance().get(Calendar.DAY_OF_WEEK)
        (dow + 5) % 7
    }
    val dayLabels = listOf("一", "二", "三", "四", "五", "六", "日")

    Card(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("🔥", fontSize = 20.sp)
                    Text(
                        text = "夸夸连胜",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                }
                Text(
                    text = "${streak.currentDays} 天",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.primary,
                )
            }

            // Weekly dot view (Duolingo-style)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                dayLabels.forEachIndexed { index, label ->
                    val daysAgo = todayIndex - index
                    val practiced = daysAgo in 0 until streak.currentDays
                    val isToday = daysAgo == 0
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(36.dp)
                                .clip(CircleShape)
                                .background(
                                    if (practiced) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.surfaceVariant
                                ),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = if (practiced) "✓" else "",
                                color = if (practiced) MaterialTheme.colorScheme.onPrimary
                                        else MaterialTheme.colorScheme.onSurfaceVariant,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                        Text(
                            text = label,
                            style = MaterialTheme.typography.labelSmall,
                            color = if (isToday) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.onSurfaceVariant,
                            fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal,
                        )
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(
                        text = "目标 ${streak.goalDays} 天连胜",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = "${streak.currentDays}/${streak.goalDays}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                LinearProgressIndicator(
                    progress = { (streak.currentDays.toFloat() / streak.goalDays).coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

// ── Practice contribution heatmap ────────────────────────────────────────────

/**
 * GitHub-style 12-week practice heatmap.
 * Columns = weeks (oldest left → newest right), rows = Mon–Sun.
 */
@Composable
private fun PracticeHeatmapCard(sessionDates: List<LocalDate>) {
    val today = remember { LocalDate.now() }
    val dateSet = remember(sessionDates) { sessionDates.toHashSet() }

    // Start from the Monday of the week 12 weeks ago
    val todayDow = today.dayOfWeek.value          // ISO: Mon=1 … Sun=7
    val thisMonday = today.minusDays((todayDow - 1).toLong())
    val windowStart = thisMonday.minusWeeks(11)

    val activeCellColor = MaterialTheme.colorScheme.primary
    val emptyCellColor = MaterialTheme.colorScheme.surfaceVariant

    Card(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "练习记录",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    "近12周打卡",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Grid: 7 rows (Mon–Sun top-to-bottom) × 12 columns (weeks left-to-right)
            val rowLabels = listOf("一", "", "三", "", "五", "", "日")
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                for (dayOfWeek in 0..6) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(2.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        // Day-of-week label (show Mon/Wed/Fri/Sun only for space)
                        Text(
                            text = rowLabels[dayOfWeek],
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.width(14.dp),
                            textAlign = TextAlign.Center,
                        )
                        for (week in 0..11) {
                            val date = windowStart.plusDays((week * 7 + dayOfWeek).toLong())
                            val isFuture = date.isAfter(today)
                            val isToday = date == today
                            val practiced = !isFuture && date in dateSet

                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .aspectRatio(1f)
                                    .clip(RoundedCornerShape(2.dp))
                                    .background(
                                        when {
                                            isFuture -> emptyCellColor.copy(alpha = 0.3f)
                                            practiced || isToday -> activeCellColor.copy(
                                                alpha = if (isToday) 1f else 0.7f,
                                            )
                                            else -> emptyCellColor
                                        }
                                    ),
                            )
                        }
                    }
                }
            }

            // Legend
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "少",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.width(4.dp))
                listOf(0.15f, 0.4f, 0.7f, 1.0f).forEach { alpha ->
                    Spacer(Modifier.width(2.dp))
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(activeCellColor.copy(alpha = alpha)),
                    )
                }
                Spacer(Modifier.width(4.dp))
                Text(
                    "多",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ── Vocabulary radar card ────────────────────────────────────────────────────

@Composable
private fun RadarCard(user: User, onReassessClick: () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = "词汇雷达",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = "达到雅思 ${user.abilityRadar.ieltsScore} 分水平",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                OutlinedButton(onClick = onReassessClick) { Text("评测报告") }
            }
            AbilityRadarChart(
                radar = user.abilityRadar,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(200.dp),
            )
        }
    }
}

// ── Props card ───────────────────────────────────────────────────────────────

@Composable
private fun PropsCard(props: List<Prop>) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "我的道具",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                props.forEach { prop ->
                    val icon = when (prop.type) {
                        PropType.STREAK_PROTECTION -> "🛡️"
                        PropType.CHALLENGE_KEY -> "🔑"
                    }
                    Card(
                        modifier = Modifier.weight(1f),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        ),
                    ) {
                        Column(
                            modifier = Modifier
                                .padding(12.dp)
                                .fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(icon, fontSize = 28.sp)
                            Text(
                                text = "x${prop.count}",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                            )
                            Text(
                                text = prop.type.displayName,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.Center,
                            )
                        }
                    }
                }
            }
        }
    }
}

// ── Account security card ────────────────────────────────────────────────────

@Composable
private fun AccountSecurityCard(
    state: AccountUiState,
    onCurrentPasswordChanged: (String) -> Unit,
    onNewPasswordChanged: (String) -> Unit,
    onChangePassword: () -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = "账户安全",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            OutlinedTextField(
                value = state.currentPassword,
                onValueChange = onCurrentPasswordChanged,
                label = { Text("当前密码") },
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = state.newPassword,
                onValueChange = onNewPasswordChanged,
                label = { Text("新密码") },
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            state.message?.let { Text(it) }
            Button(
                onClick = onChangePassword,
                enabled = !state.isLoading,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (state.isLoading) "修改中..." else "修改密码")
            }
        }
    }
}

// ── Ability radar chart ──────────────────────────────────────────────────────

@Composable
private fun AbilityRadarChart(radar: AbilityRadar, modifier: Modifier = Modifier) {
    val axes = listOf(
        "单词" to radar.vocabulary,
        "听力" to radar.listening,
        "阅读" to radar.reading,
        "口语" to radar.speaking,
        "写作" to radar.writing,
    )
    val maxValue = 10f
    val currentColor = MaterialTheme.colorScheme.primary
    val gridColor = MaterialTheme.colorScheme.outlineVariant
    val previousColor = MaterialTheme.colorScheme.outline
    val labelColor = MaterialTheme.colorScheme.onSurfaceVariant
    val labelPx = with(LocalDensity.current) { 12.sp.toPx() }

    Canvas(modifier = modifier) {
        val n = axes.size
        val center = Offset(size.width / 2f, size.height / 2f)
        val radius = (size.minDimension / 2f) * 0.70f

        fun vertex(index: Int, r: Float): Offset {
            val angle = (-PI / 2 + 2 * PI * index / n).toFloat()
            return Offset(center.x + r * cos(angle), center.y + r * sin(angle))
        }

        fun polygon(values: List<Float>): Path = Path().apply {
            values.forEachIndexed { i, v ->
                val p = vertex(i, radius * (v / maxValue).coerceIn(0f, 1f))
                if (i == 0) moveTo(p.x, p.y) else lineTo(p.x, p.y)
            }
            close()
        }

        listOf(0.33f, 0.66f, 1f).forEach { ring ->
            val path = Path()
            for (i in 0 until n) {
                val p = vertex(i, radius * ring)
                if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y)
            }
            path.close()
            drawPath(path, color = gridColor, style = Stroke(width = 1.dp.toPx()))
        }
        for (i in 0 until n) {
            drawLine(gridColor, center, vertex(i, radius), strokeWidth = 1.dp.toPx())
        }
        drawPath(polygon(axes.map { it.second.previous }), color = previousColor, style = Stroke(width = 1.5.dp.toPx()))
        val current = polygon(axes.map { it.second.current })
        drawPath(current, color = currentColor.copy(alpha = 0.25f))
        drawPath(current, color = currentColor, style = Stroke(width = 2.dp.toPx()))
        drawIntoCanvas { canvas ->
            val paint = android.graphics.Paint().apply {
                color = labelColor.toArgb()
                textSize = labelPx
                textAlign = android.graphics.Paint.Align.CENTER
                isAntiAlias = true
            }
            for (i in 0 until n) {
                val p = vertex(i, radius + labelPx * 1.1f)
                canvas.nativeCanvas.drawText(axes[i].first, p.x, p.y + labelPx / 3f, paint)
            }
        }
    }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

private fun nextTitleProgress(duckPower: Int, currentTitle: DuckTitle): Pair<Float, DuckTitle?> {
    val all = DuckTitle.values()
    val idx = all.indexOf(currentTitle)
    if (idx == all.size - 1) return 1f to null
    val next = all[idx + 1]
    val progress = (duckPower - currentTitle.minDuckPower).toFloat() /
                   (next.minDuckPower - currentTitle.minDuckPower)
    return progress.coerceIn(0f, 1f) to next
}

// ── Preview ──────────────────────────────────────────────────────────────────

@Preview(showBackground = true, heightDp = 1400)
@Composable
private fun ProfileContentPreview() {
    KuaKuaTheme {
        ProfileContent(
            user = previewUser,
            sessionDates = listOf(
                LocalDate.now(), LocalDate.now().minusDays(1), LocalDate.now().minusDays(3),
                LocalDate.now().minusDays(7), LocalDate.now().minusDays(14),
            ),
            onReassessClick = {},
            onSignOut = {},
            accountState = AccountUiState(),
            onCurrentPasswordChanged = {},
            onNewPasswordChanged = {},
            onChangePassword = {},
        )
    }
}

private val previewUser = User(
    id = "ksdfj76239skd",
    nickname = "leoninebess",
    avatarUrl = null,
    phone = null,
    duckPower = 450,
    userLevel = UserLevel(levelNumber = 20, ieltsBand = 5.5, levelName = "脆皮新生", progress = 0.4f),
    abilityRadar = AbilityRadar(
        ieltsScore = 5.5,
        vocabulary = AbilityRadar.Axis(7f, 5f),
        listening = AbilityRadar.Axis(6f, 5f),
        speaking = AbilityRadar.Axis(5f, 4f),
        reading = AbilityRadar.Axis(6.5f, 5f),
        writing = AbilityRadar.Axis(5.5f, 4.5f),
    ),
    streak = StreakInfo(currentDays = 5, goalDays = 7),
    props = listOf(
        Prop(PropType.STREAK_PROTECTION, 2),
        Prop(PropType.CHALLENGE_KEY, 3),
    ),
)
