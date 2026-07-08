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
import com.example.firsttest.data.model.Award
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
    onSignOut: () -> Unit = {},
    viewModel: ProfileViewModel = viewModel(factory = ProfileViewModel.Factory),
    accountViewModel: AccountViewModel = viewModel(factory = AccountViewModel.Factory),
) {
    val uiState by viewModel.uiState.collectAsState()
    val accountState by accountViewModel.uiState.collectAsState()

    Scaffold(contentWindowInsets = WindowInsets(0, 0, 0, 0)) { innerPadding ->
        when (val state = uiState) {
            is ProfileUiState.Loading -> Box(
                modifier = Modifier.fillMaxSize().padding(innerPadding),
                contentAlignment = Alignment.Center,
            ) {
                Text("Loading profile...")
            }

            is ProfileUiState.Success -> ProfileContent(
                user = state.user,
                sessionDates = state.sessionDates,
                awards = state.awards,
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
    awards: List<Award>,
    onSignOut: () -> Unit,
    accountState: AccountUiState,
    onCurrentPasswordChanged: (String) -> Unit,
    onNewPasswordChanged: (String) -> Unit,
    onChangePassword: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        HeroCard(user)
        QuickStatsRow(user)
        StreakCard(user.streak)
        PracticeHeatmapCard(sessionDates)
        RadarCard(user)
        if (user.props.isNotEmpty()) PropsCard(user.props)
        if (awards.isNotEmpty()) AwardsCard(awards)
        AccountSecurityCard(
            state = accountState,
            onCurrentPasswordChanged = onCurrentPasswordChanged,
            onNewPasswordChanged = onNewPasswordChanged,
            onChangePassword = onChangePassword,
        )
        OutlinedButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) {
            Text("Sign out")
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun HeroCard(user: User) {
    val (progress, nextTitle) = nextTitleProgress(user.duckPower, user.duckTitle)
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Box(
                    modifier = Modifier.size(72.dp).clip(CircleShape)
                        .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(user.nickname.take(1).uppercase(), fontSize = 32.sp, fontWeight = FontWeight.Bold)
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
                            text = titleLabel(user.duckTitle),
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

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "${user.duckPower} power",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                    Text(
                        text = nextTitle?.let { "Next: ${titleLabel(it)} (${it.minDuckPower})" } ?: "Top title reached",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.65f),
                    )
                }
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth().height(8.dp).clip(MaterialTheme.shapes.small),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.2f),
                )
            }
        }
    }
}

@Composable
private fun QuickStatsRow(user: User) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        QuickStat(Modifier.weight(1f), "LV ${user.userLevel.levelNumber}", user.userLevel.levelName)
        QuickStat(Modifier.weight(1f), "${user.streak.currentDays} days", "Streak")
        QuickStat(Modifier.weight(1f), "Band ${user.userLevel.ieltsBand}", "IELTS target")
    }
}

@Composable
private fun QuickStat(modifier: Modifier, value: String, label: String) {
    Card(modifier = modifier, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(
            modifier = Modifier.padding(10.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(text = value, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun StreakCard(streak: StreakInfo) {
    val todayIndex = remember {
        val dow = Calendar.getInstance().get(Calendar.DAY_OF_WEEK)
        (dow + 5) % 7
    }
    val dayLabels = listOf("M", "T", "W", "T", "F", "S", "S")

    Card(Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(text = "Daily streak", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text(
                    text = "${streak.currentDays} days",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.primary,
                )
            }

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                dayLabels.forEachIndexed { index, label ->
                    val daysAgo = todayIndex - index
                    val practiced = daysAgo in 0 until streak.currentDays
                    val isToday = daysAgo == 0
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Box(
                            modifier = Modifier.size(36.dp).clip(CircleShape).background(
                                if (practiced) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
                            ),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = if (practiced) "✓" else "",
                                color = if (practiced) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                        Text(
                            text = label,
                            style = MaterialTheme.typography.labelSmall,
                            color = if (isToday) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                            fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal,
                        )
                    }
                }
            }

            LinearProgressIndicator(
                progress = { (streak.currentDays.toFloat() / streak.goalDays).coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun PracticeHeatmapCard(sessionDates: List<LocalDate>) {
    val today = remember { LocalDate.now() }
    val dateSet = remember(sessionDates) { sessionDates.toHashSet() }
    val todayDow = today.dayOfWeek.value
    val thisMonday = today.minusDays((todayDow - 1).toLong())
    val windowStart = thisMonday.minusWeeks(11)
    val activeCellColor = MaterialTheme.colorScheme.primary
    val emptyCellColor = MaterialTheme.colorScheme.surfaceVariant

    Card(Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("Practice history", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text("Last 12 weeks", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            val rowLabels = listOf("M", "", "W", "", "F", "", "S")
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                for (dayOfWeek in 0..6) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(2.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
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
                                modifier = Modifier.weight(1f).aspectRatio(1f).clip(RoundedCornerShape(2.dp)).background(
                                    when {
                                        isFuture -> emptyCellColor.copy(alpha = 0.3f)
                                        practiced || isToday -> activeCellColor.copy(alpha = if (isToday) 1f else 0.7f)
                                        else -> emptyCellColor
                                    },
                                ),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RadarCard(user: User) {
    Card(Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(text = "IELTS readiness", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text(
                    text = "Estimated Band ${user.abilityRadar.ieltsScore}. Skill axes are informational in Phase 1.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            AbilityRadarChart(radar = user.abilityRadar, modifier = Modifier.fillMaxWidth().height(200.dp))
        }
    }
}

@Composable
private fun PropsCard(props: List<Prop>) {
    Card(Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(text = "Items", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                props.forEach { prop ->
                    Card(
                        modifier = Modifier.weight(1f),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                    ) {
                        Column(
                            modifier = Modifier.padding(12.dp).fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(text = "x${prop.count}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                            Text(
                                text = itemLabel(prop.type),
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

@Composable
private fun AwardsCard(awards: List<Award>) {
    Card(Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(text = "我的成就", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            awards.forEach { award ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(text = "🏅", fontSize = 24.sp)
                    Column {
                        Text(text = award.nameZh, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                        award.descriptionZh?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AccountSecurityCard(
    state: AccountUiState,
    onCurrentPasswordChanged: (String) -> Unit,
    onNewPasswordChanged: (String) -> Unit,
    onChangePassword: () -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(text = "Account security", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            OutlinedTextField(
                value = state.currentPassword,
                onValueChange = onCurrentPasswordChanged,
                label = { Text("Current password") },
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = state.newPassword,
                onValueChange = onNewPasswordChanged,
                label = { Text("New password") },
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            state.message?.let { Text(it) }
            Button(onClick = onChangePassword, enabled = !state.isLoading, modifier = Modifier.fillMaxWidth()) {
                Text(if (state.isLoading) "Changing..." else "Change password")
            }
        }
    }
}

@Composable
private fun AbilityRadarChart(radar: AbilityRadar, modifier: Modifier = Modifier) {
    val axes = listOf(
        "Vocab" to radar.vocabulary,
        "Listen" to radar.listening,
        "Read" to radar.reading,
        "Speak" to radar.speaking,
        "Write" to radar.writing,
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

private fun nextTitleProgress(duckPower: Int, currentTitle: DuckTitle): Pair<Float, DuckTitle?> {
    val all = DuckTitle.entries
    val idx = all.indexOf(currentTitle)
    if (idx == all.size - 1) return 1f to null
    val next = all[idx + 1]
    val progress = (duckPower - currentTitle.minDuckPower).toFloat() / (next.minDuckPower - currentTitle.minDuckPower)
    return progress.coerceIn(0f, 1f) to next
}

private fun titleLabel(title: DuckTitle): String = when (title) {
    DuckTitle.BEGINNER -> "Beginner"
    DuckTitle.HARD_WORKING -> "Hard-working"
    DuckTitle.PROGRESSING -> "Progressing"
    DuckTitle.SKILLED -> "Skilled"
    DuckTitle.SUPER -> "Advanced"
    DuckTitle.EXCELLENT -> "Excellent"
    DuckTitle.INVINCIBLE -> "Expert"
    DuckTitle.MASTER -> "Master"
}

private fun itemLabel(type: PropType): String = when (type) {
    PropType.STREAK_PROTECTION -> "Streak protection"
    PropType.CHALLENGE_KEY -> "Challenge key"
}

@Preview(showBackground = true, heightDp = 1400)
@Composable
private fun ProfileContentPreview() {
    KuaKuaTheme {
        ProfileContent(
            user = previewUser,
            sessionDates = listOf(
                LocalDate.now(),
                LocalDate.now().minusDays(1),
                LocalDate.now().minusDays(3),
                LocalDate.now().minusDays(7),
                LocalDate.now().minusDays(14),
            ),
            awards = listOf(
                Award("bronze_duck", "第一只鸭！", "完成首次登录", "2026-07-01T00:00:00Z"),
            ),
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
    nickname = "demo_student",
    avatarUrl = null,
    phone = null,
    duckPower = 450,
    userLevel = UserLevel(levelNumber = 20, ieltsBand = 5.5, levelName = "IELTS Core", progress = 0.4f),
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
