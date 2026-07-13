package com.example.firsttest.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.model.DuckTitle
import com.example.firsttest.data.model.Level

/**
 * Home: a duck-themed daily learning path. The current IELTS band renders as a
 * scrolling path of 鸭力训练 (drill) cards with 刮刮卡 (scratch-card) and 挑战赛
 * (challenge) waypoints interspersed; other bands collapse into compact
 * sections. Source styling: 第一期原型图+文档/2.2 每日练习（首页）.
 */
@Composable
fun HomeScreen(
    modifier: Modifier = Modifier,
    refreshToken: Int = 0,
    onLevelClick: (levelNumber: Int) -> Unit = {},
    onBandTestClick: (targetBand: Double) -> Unit = {},
    onOverallAssessmentClick: () -> Unit = {},
    onScratchCardClick: (cardId: String) -> Unit = {},
    viewModel: HomeViewModel = viewModel(factory = HomeViewModel.Factory),
) {
    LaunchedEffect(refreshToken) {
        viewModel.refreshWhenVisible()
    }
    val uiState by viewModel.uiState.collectAsState()
    when (val state = uiState) {
        is HomeUiState.Loading ->
            Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }

        is HomeUiState.Success ->
            Column(modifier.fillMaxSize()) {
                DuckGreetingBar()
                StatusRow(
                    duckPower = state.duckPower,
                    streakDays = state.streakDays,
                    streakGoal = state.streakGoal,
                )
                AssessmentPrompt(onClick = onOverallAssessmentClick)
                Spacer(Modifier.height(4.dp))
                BandList(
                    bands = state.bands,
                    onLevelClick = onLevelClick,
                    onBandTestClick = onBandTestClick,
                    onScratchCardClick = onScratchCardClick,
                    modifier = Modifier.weight(1f),
                )
            }

        is HomeUiState.Error ->
            ErrorState(
                message = state.message,
                onRetry = viewModel::retry,
                modifier = modifier,
            )
    }
}

// ---- Duck theme palette -------------------------------------------------------

private val DuckAvatarBg = Color(0xFFFFF3CD)
private val DuckBlueLight = Color(0xFFE3F2FD)
private val DuckBlueBorder = Color(0xFF42A5F5)
private val DuckGold = Color(0xFFFFD54F)
private val DuckOrange = Color(0xFFFFCC80)
private val StarGold = Color(0xFFFFA000)

// ---- Greeting + top status row -------------------------------------------------

@Composable
private fun DuckGreetingBar() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .background(DuckAvatarBg, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text("🦆", fontSize = 24.sp)
        }
        Card(
            shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        ) {
            Text(
                "今天也要继续加油鸭～!",
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

@Composable
private fun StatusRow(duckPower: Int, streakDays: Int, streakGoal: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        StatusChip(Modifier.weight(1f), "🔥", "$streakDays 天", "连续打卡 · 目标 $streakGoal 天")
        StatusChip(
            Modifier.weight(1f),
            "⚡",
            "$duckPower",
            "鸭力值 · ${DuckTitle.forDuckPower(duckPower).displayName}",
        )
    }
}

@Composable
private fun StatusChip(modifier: Modifier, icon: String, value: String, label: String) {
    Card(modifier, shape = RoundedCornerShape(14.dp)) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(icon, fontSize = 24.sp)
            Column {
                Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text(
                    label,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun AssessmentPrompt(onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp)
            .clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            "📊 想重新看看自己的雅思水平？",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            "去测评 ›",
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}

// ---- Difficulty bands and levels --------------------------------------------

@Composable
private fun BandList(
    bands: List<BandSection>,
    onLevelClick: (levelNumber: Int) -> Unit,
    onBandTestClick: (targetBand: Double) -> Unit,
    onScratchCardClick: (cardId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        itemsIndexed(bands, key = { _, band -> band.score }) { index, band ->
            BandCard(
                band = band,
                nextBand = bands.getOrNull(index + 1),
                onLevelClick = onLevelClick,
                onBandTestClick = onBandTestClick,
                onScratchCardClick = onScratchCardClick,
            )
        }
    }
}

@Composable
private fun BandCard(
    band: BandSection,
    nextBand: BandSection?,
    onLevelClick: (levelNumber: Int) -> Unit,
    onBandTestClick: (targetBand: Double) -> Unit,
    onScratchCardClick: (cardId: String) -> Unit,
) {
    var expanded by rememberSaveable(band.score) { mutableStateOf(band.isCurrent) }
    var showChallengeComingSoon by remember(band.score) { mutableStateOf(false) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (band.isCurrent) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.surfaceVariant
            },
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(if (band.isUnlocked) "🔓" else "🔒", fontSize = 18.sp)
                Column(Modifier.weight(1f)) {
                    Text(
                        "雅思 ${formatBandScore(band.score)} 分词汇 · ${bandDuckTitle(band.score)}",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        when {
                            band.isCurrent ->
                                "当前主线 · 已解锁 ${band.unlockedLevelCount}/${band.levels.size} 关"
                            band.isUnlocked ->
                                "已完成 ${band.completedLevelCount}/${band.levels.size} 关"
                            else ->
                                "完成上一等级的闯关测试即可解锁"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (band.isUnlocked) {
                    TextButton(onClick = { expanded = !expanded }) {
                        Text(if (expanded) "收起" else "展开")
                    }
                } else {
                    OutlinedButton(onClick = { onBandTestClick(band.score) }) {
                        Text("闯关测试")
                    }
                }
            }

            if (band.isCurrent) {
                Text(
                    bandMotivation(band.score),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (expanded && band.isUnlocked) {
                val pathItems = remember(band.levels) { buildPathItems(band.score, band.levels) }
                pathItems.forEach { item ->
                    when (item) {
                        is PathItem.LevelItem -> LevelPathCard(
                            level = item.level,
                            displayTitle = item.displayTitle,
                            onClick = { onLevelClick(item.level.number) },
                        )
                        is PathItem.ScratchItem -> ScratchPathCard(
                            item = item,
                            onClick = { if (item.isUnlocked) onScratchCardClick(item.id) },
                        )
                        is PathItem.ChallengeItem -> ChallengePathCard(
                            item = item,
                            onClick = { if (item.isUnlocked) showChallengeComingSoon = true },
                        )
                    }
                }

                if (nextBand != null && !nextBand.isUnlocked) {
                    UnlockMoreCard(nextBand = nextBand, onClick = { onBandTestClick(nextBand.score) })
                }
            }
        }
    }

    if (showChallengeComingSoon) {
        AlertDialog(
            onDismissRequest = { showChallengeComingSoon = false },
            confirmButton = {
                TextButton(onClick = { showChallengeComingSoon = false }) { Text("知道了") }
            },
            title = { Text("挑战赛") },
            text = { Text("挑战赛马上就要开抢啦，敬请期待鸭！") },
        )
    }
}

// ---- Path items: 鸭力训练 / 刮刮卡 / 挑战赛 -----------------------------------

private sealed interface PathItem {
    data class LevelItem(val level: Level, val displayTitle: String) : PathItem
    data class ScratchItem(val id: String, val isUnlocked: Boolean) : PathItem
    data class ChallengeItem(val id: String, val isUnlocked: Boolean) : PathItem
}

/**
 * Interleaves drill levels with scratch-card and challenge waypoints, following
 * spec 2.2.2's placement rules (a scratch card every 4 drills, or before the
 * last drill when the band only has 4-5; one challenge waypoint once a band
 * has more than 6 drills).
 */
private fun buildPathItems(bandScore: Double, levels: List<Level>): List<PathItem> {
    val items = mutableListOf<PathItem>()
    levels.forEachIndexed { index, level ->
        items += PathItem.LevelItem(level, levelTopicDisplayName(levels, index))
        val position = index + 1
        when {
            levels.size in 4..5 && position == levels.size - 1 ->
                items += PathItem.ScratchItem("scratch_${bandScore}_$position", level.isUnlocked)
            levels.size > 5 && position % 4 == 0 ->
                items += PathItem.ScratchItem("scratch_${bandScore}_$position", level.isUnlocked)
        }
        if (levels.size > 6 && position == 6) {
            items += PathItem.ChallengeItem("challenge_${bandScore}_$position", level.isUnlocked)
        }
    }
    return items
}

private val CARD_SUBTITLES = listOf(
    "现在啃单词以后分数甜！冲鸭～",
    "背词不怕慢，坚持就上岸！夸夸～",
    "平时多努力，烤鸭变锦鲤！",
    "今天刷的题，都是明天夸自己的底气",
    "每天学一点，分数偷偷往上涨～",
    "多练就是上分密码！夸夸～",
    "现在刷题苦，考完烤鸭香！～",
    "早晚各一遍！碎片时间啃单词",
    "背词就像吃火锅，每个单词'涮'三遍～",
    "你背的每个单词，都是未来考试的秘密武器",
)

private fun cardSubtitle(levelNumber: Int): String = CARD_SUBTITLES[levelNumber % CARD_SUBTITLES.size]

/** 雅思分数段 → 等级称号 (spec 2.2.1 用户等级页). */
private fun bandDuckTitle(score: Double): String = when (score) {
    4.0 -> "脆皮萌鸭"
    4.5 -> "词圈鸭仔"
    5.0 -> "鸭闯词关"
    5.5 -> "鸭学启程"
    6.0 -> "鸭题先锋"
    6.5 -> "鸭行辞海"
    7.0 -> "鸭掌全局"
    7.5 -> "鸭系词霸"
    8.0 -> "鸭学词宗"
    else -> "神秘鸭"
}

/** 雅思分数段 → 鼓励文案 (spec 2.2.1 用户等级页 - 进行中状态). */
private fun bandMotivation(score: Double): String = when {
    score <= 5.5 -> "现在啃的每个单词刷的每道题，都是未来上岸的底气～你超有潜力的，冲鸭！"
    score <= 6.5 -> "你的努力藏在每天默默刷过的题里！冲鸭～稳一稳就能摸到 7 分的门槛啦！"
    else -> "踮踮脚就能触碰更高分！别小看自己的潜力，带着这份从容继续加油鸭！"
}

@Composable
private fun LevelPathCard(level: Level, displayTitle: String, onClick: () -> Unit) {
    var showComingSoonDialog by remember(level.number) { mutableStateOf(false) }
    val isActive = level.isUnlocked && !level.isCompleted && !level.isComingSoon
    val isReachable = level.isUnlocked && !level.isComingSoon

    val icon = when {
        level.isComingSoon -> "⏳"
        level.isCompleted -> "🏅"
        level.isUnlocked -> "🦆"
        else -> "🔒"
    }
    val trailingLabel = when {
        level.isComingSoon -> "敬请期待"
        level.isCompleted -> "重新练习"
        level.isUnlocked -> "开始"
        else -> "未解锁"
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (isReachable) 1f else 0.6f)
            .then(
                if (isActive) {
                    Modifier.border(2.dp, DuckBlueBorder, RoundedCornerShape(16.dp))
                } else {
                    Modifier
                },
            )
            .then(
                when {
                    level.isComingSoon -> Modifier.clickable { showComingSoonDialog = true }
                    level.isUnlocked -> Modifier.clickable(onClick = onClick)
                    else -> Modifier
                },
            ),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (isActive) DuckBlueLight else MaterialTheme.colorScheme.surface,
        ),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(icon, fontSize = 26.sp)
            Column(Modifier.weight(1f)) {
                Text(
                    "鸭力训练 · $displayTitle",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                when {
                    level.isCompleted || (level.isUnlocked && level.completedSessionCount > 0) -> {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            repeat(3) { i ->
                                Text(
                                    if (i < level.bestStarRating) "★" else "☆",
                                    color = StarGold,
                                    fontSize = 13.sp,
                                )
                            }
                            Spacer(Modifier.width(6.dp))
                            Text(
                                "正确率 ${(level.bestAccuracy * 100).toInt()}%",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    level.isComingSoon -> Text(
                        "新关卡制作中，即将上线～",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    level.isUnlocked -> Text(
                        cardSubtitle(level.number),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    else -> Text(
                        "完成上一关即可解锁",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    trailingLabel,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (isReachable) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (isReachable) {
                    Text(
                        "鸭力值 +50",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }

    if (showComingSoonDialog) {
        AlertDialog(
            onDismissRequest = { showComingSoonDialog = false },
            confirmButton = {
                TextButton(onClick = { showComingSoonDialog = false }) { Text("知道了") }
            },
            title = { Text("即将上线") },
            text = { Text("这个关卡即将上线，敬请期待！") },
        )
    }
}

@Composable
private fun ScratchPathCard(item: PathItem.ScratchItem, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (item.isUnlocked) 1f else 0.6f)
            .then(if (item.isUnlocked) Modifier.clickable(onClick = onClick) else Modifier),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (item.isUnlocked) DuckGold else MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("🎁", fontSize = 26.sp)
            Column(Modifier.weight(1f)) {
                Text("刮刮卡", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                Text(
                    if (item.isUnlocked) "Good Luck！轻触刮开，好运翻倍～" else "完成前面的鸭力训练即可解锁",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (item.isUnlocked) {
                Text("刮一刮", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun ChallengePathCard(item: PathItem.ChallengeItem, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (item.isUnlocked) 1f else 0.6f)
            .then(if (item.isUnlocked) Modifier.clickable(onClick = onClick) else Modifier),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (item.isUnlocked) DuckOrange else MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("🏃", fontSize = 26.sp)
            Column(Modifier.weight(1f)) {
                Text("极速挑战赛", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                Text(
                    if (item.isUnlocked) "滴答滴答读秒加速～拼手速更是拼脑速！" else "完成前面的鸭力训练即可解锁",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (item.isUnlocked) {
                Text("挑战", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun UnlockMoreCard(nextBand: BandSection, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text("🔑", fontSize = 28.sp)
            Text("解锁更多", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            Text(
                "完成闯关测试，解锁「雅思 ${formatBandScore(nextBand.score)} 分 · ${bandDuckTitle(nextBand.score)}」",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

// ---- Error state ------------------------------------------------------------

@Composable
private fun ErrorState(message: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("🦆")
        Spacer(Modifier.height(8.dp))
        Text("加载失败了鸭", style = MaterialTheme.typography.titleMedium)
        Text(
            message,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        Button(onClick = onRetry) { Text("重试") }
    }
}
