package com.example.firsttest.ui.profile

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.model.AbilityRadar
import com.example.firsttest.data.model.Prop
import com.example.firsttest.data.model.PropType
import com.example.firsttest.data.model.StreakInfo
import com.example.firsttest.data.model.User
import com.example.firsttest.data.model.UserLevel
import com.example.firsttest.ui.theme.KuaKuaTheme
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
    // Hosted inside MainScreen's Scaffold, which already supplies window insets
    // and the bottom-nav padding; opt out here to avoid double-counting them.
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
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // TODO: ⚙️ settings screen not built — tapping does nothing.
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            Text("⚙️", fontSize = 22.sp)
        }

        // Identity: avatar + nickname + ID
        Row(verticalAlignment = Alignment.CenterVertically) {
            // TODO: avatar — no upload flow yet; show placeholder until storage + crop built.
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center,
            ) { Text("头像", style = MaterialTheme.typography.labelMedium) }
            Spacer(Modifier.width(16.dp))
            Column {
                Text(user.nickname, style = MaterialTheme.typography.titleLarge)
                Text(
                    text = "ID:${user.id}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        // Stats grid (2 x 2)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatCard(Modifier.weight(1f), "⚡", "${user.duckPower}", "总鸭力值")
            StatCard(Modifier.weight(1f), "🦆", user.duckTitle.displayName, "鸭力称号")
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatCard(Modifier.weight(1f), "🏭", "LV ${user.userLevel.levelNumber}", "当前等级")
            StatCard(Modifier.weight(1f), "🎓", user.userLevel.levelName, "等级名称")
        }

        // TODO: AssessmentCard radar axes (听力/阅读/口语/写作) require dedicated
        //   assessment features — no data source exists. Only vocabulary axis is live.
        AssessmentCard(user, onReassessClick)
        StreakCard(user.streak)
        // TODO: PropsCard — props (连胜保护/挑战钥匙) not persisted to Supabase yet.
        //   Requires a user_props table or columns on profiles; always shows empty for now.
        PropsCard(user.props)
        AccountSecurityCard(
            state = accountState,
            onCurrentPasswordChanged = onCurrentPasswordChanged,
            onNewPasswordChanged = onNewPasswordChanged,
            onChangePassword = onChangePassword,
        )
        OutlinedButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) {
            Text("Sign out")
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
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Account security", style = MaterialTheme.typography.titleMedium)
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
            Button(
                onClick = onChangePassword,
                enabled = !state.isLoading,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (state.isLoading) "Changing..." else "Change password")
            }
        }
    }
}

@Composable
private fun StatCard(modifier: Modifier, icon: String, value: String, label: String) {
    Card(modifier) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(icon, fontSize = 26.sp)
            Column {
                Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text(
                    text = label,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun AssessmentCard(user: User, onReassessClick: () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "词汇达到\n雅思 ${user.abilityRadar.ieltsScore} 分水平",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                OutlinedButton(onClick = onReassessClick) { Text("重新评测") }
            }
            AbilityRadarChart(
                radar = user.abilityRadar,
                modifier = Modifier.fillMaxWidth().height(220.dp),
            )
            Button(onClick = onReassessClick, modifier = Modifier.fillMaxWidth()) {
                Text("评测报告")
            }
        }
    }
}

@Composable
private fun StreakCard(streak: StreakInfo) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("夸夸连胜", style = MaterialTheme.typography.titleMedium)
                Text(
                    text = "🙌 ${streak.currentDays} 天连胜!",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
            }
            Text(
                text = "连胜目标：${streak.goalDays} 天",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            LinearProgressIndicator(
                progress = { (streak.currentDays.toFloat() / streak.goalDays).coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun PropsCard(props: List<Prop>) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("我的道具", style = MaterialTheme.typography.titleMedium)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                props.forEach { prop ->
                    val icon = when (prop.type) {
                        PropType.STREAK_PROTECTION -> "🛡️"
                        PropType.CHALLENGE_KEY -> "🔑"
                    }
                    Card(Modifier.weight(1f)) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(icon, fontSize = 24.sp)
                            Column {
                                Text("x${prop.count}", fontWeight = FontWeight.Bold)
                                Text(
                                    text = prop.type.displayName,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Simplified 能力雷达图 (ability radar). Draws a 5-axis pentagon with the
 * current scores filled and the previous scores as a grey outline.
 * TODO (later phase): polish styling/animation per the prototype.
 */
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

        // Grid rings
        listOf(0.33f, 0.66f, 1f).forEach { ring ->
            val path = Path()
            for (i in 0 until n) {
                val p = vertex(i, radius * ring)
                if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y)
            }
            path.close()
            drawPath(path, color = gridColor, style = Stroke(width = 1.dp.toPx()))
        }
        // Spokes
        for (i in 0 until n) {
            drawLine(gridColor, center, vertex(i, radius), strokeWidth = 1.dp.toPx())
        }
        // Previous scores (grey outline)
        drawPath(polygon(axes.map { it.second.previous }), color = previousColor, style = Stroke(width = 1.5.dp.toPx()))
        // Current scores (filled + outline)
        val current = polygon(axes.map { it.second.current })
        drawPath(current, color = currentColor.copy(alpha = 0.25f))
        drawPath(current, color = currentColor, style = Stroke(width = 2.dp.toPx()))
        // Axis labels
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

@Preview(showBackground = true, heightDp = 1200)
@Composable
private fun ProfileContentPreview() {
    KuaKuaTheme {
        ProfileContent(
            user = previewUser,
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
