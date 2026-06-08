package com.example.firsttest.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.model.CardState
import com.example.firsttest.data.model.PracticeCard
import com.example.firsttest.data.model.PracticeCardType

/**
 * Home / 每日练习 (首页). A top status row (连胜 + 鸭力值) over a vertical
 * learning-path of practice cards. All data is fake (Phase 1) — see
 * [HomeViewModel]. Hosted inside MainScreen's Scaffold, which already supplies
 * window-inset + bottom-nav padding, so this screen adds none of its own.
 */
@Composable
fun HomeScreen(
    modifier: Modifier = Modifier,
    onDrillClick: (cardId: String) -> Unit = {},
    viewModel: HomeViewModel = viewModel(factory = HomeViewModel.Factory),
) {
    val uiState by viewModel.uiState.collectAsState()
    when (val state = uiState) {
        is HomeUiState.Loading ->
            Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }

        is HomeUiState.Success ->
            Column(modifier.fillMaxSize()) {
                StatusRow(
                    duckPower = state.duckPower,
                    streakDays = state.streakDays,
                    streakGoal = state.streakGoal,
                )
                LearningPath(
                    cards = state.cards,
                    onDrillClick = onDrillClick,
                    modifier = Modifier.weight(1f),
                )
            }
    }
}

// ---- Top status row -------------------------------------------------------

@Composable
private fun StatusRow(duckPower: Int, streakDays: Int, streakGoal: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        StatusChip(Modifier.weight(1f), "🔥", "$streakDays 天连胜", "目标 $streakGoal 天")
        StatusChip(Modifier.weight(1f), "⚡", "$duckPower", "鸭力值")
    }
}

@Composable
private fun StatusChip(modifier: Modifier, icon: String, value: String, label: String) {
    Card(modifier) {
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

// ---- Vertical learning path ----------------------------------------------

@Composable
private fun LearningPath(
    cards: List<PracticeCard>,
    onDrillClick: (cardId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Assign display titles; 鸭力训练 cards are numbered in encounter order.
    val titled = remember(cards) {
        var drill = 0
        cards.map { card ->
            val title = when (card.type) {
                PracticeCardType.DUCK_TRAINING -> "鸭力训练 ${++drill}"
                PracticeCardType.SCRATCH_CARD -> "刮刮卡"
                PracticeCardType.CHALLENGE -> "挑战赛"
                PracticeCardType.UNLOCK_MORE -> "解锁更多"
            }
            card to title
        }
    }
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(titled, key = { it.first.id }) { (card, title) ->
            PathCard(card = card, title = title, onDrillClick = onDrillClick)
        }
    }
}

@Composable
private fun PathCard(
    card: PracticeCard,
    title: String,
    onDrillClick: (cardId: String) -> Unit,
) {
    val locked = card.state == CardState.LOCKED
    // Only unlocked DUCK_TRAINING cards are tappable in Phase 2.
    val isClickable = !locked && card.type == PracticeCardType.DUCK_TRAINING
    val icon = when (card.type) {
        PracticeCardType.DUCK_TRAINING -> "🦆"
        PracticeCardType.SCRATCH_CARD -> "🎁"
        PracticeCardType.CHALLENGE -> "⚡"
        PracticeCardType.UNLOCK_MORE -> "🔓"
    }
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (locked) 0.5f else 1f)
            .then(
                if (isClickable) Modifier.clickable { onDrillClick(card.id) }
                else Modifier
            ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(if (locked) "🔒" else icon, fontSize = 28.sp)
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                SecondaryLine(card, locked)
            }
            Text(
                text = stateBadge(card.state),
                style = MaterialTheme.typography.labelMedium,
                color = if (card.state == CardState.UNLOCKED_UNPRACTICED) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
        }
    }
}

/** Second line of a card: stars when practiced, else subtitle, else reward. */
@Composable
private fun SecondaryLine(card: PracticeCard, locked: Boolean) {
    val subtitle = card.subtitle
    when {
        card.type == PracticeCardType.DUCK_TRAINING && card.state == CardState.PRACTICED ->
            Text(stars(card.starRating), fontSize = 16.sp)

        !locked && subtitle != null ->
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

        !locked && card.duckPowerReward > 0 ->
            Text(
                "可获得 ⚡${card.duckPowerReward}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
    }
}

private fun stars(rating: Int): String {
    val r = rating.coerceIn(0, 3)
    return "★".repeat(r) + "☆".repeat(3 - r)
}

private fun stateBadge(state: CardState): String = when (state) {
    CardState.PRACTICED -> "已完成"
    CardState.UNLOCKED_UNPRACTICED -> "待练习"
    CardState.LOCKED -> "未解锁"
}
