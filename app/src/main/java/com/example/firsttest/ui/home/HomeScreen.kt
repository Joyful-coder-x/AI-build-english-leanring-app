package com.example.firsttest.ui.home

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.model.Level

/**
 * Home: status row above IELTS difficulty sections. The current
 * difficulty opens by default; other unlocked difficulties can be expanded,
 * and locked difficulties expose their upgrade-exam action.
 */
@Composable
fun HomeScreen(
    modifier: Modifier = Modifier,
    refreshToken: Int = 0,
    onLevelClick: (levelNumber: Int) -> Unit = {},
    onBandTestClick: (targetBand: Double) -> Unit = {},
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
                StatusRow(
                    duckPower = state.duckPower,
                    streakDays = state.streakDays,
                    streakGoal = state.streakGoal,
                )
                BandList(
                    bands = state.bands,
                    onLevelClick = onLevelClick,
                    onBandTestClick = onBandTestClick,
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

// ---- Top status row ----------------------------------------------------------

@Composable
private fun StatusRow(duckPower: Int, streakDays: Int, streakGoal: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        StatusChip(Modifier.weight(1f), "Streak", "$streakDays days", "Goal $streakGoal days")
        StatusChip(Modifier.weight(1f), "Power", "$duckPower", "Practice points")
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

// ---- Difficulty bands and levels --------------------------------------------

@Composable
private fun BandList(
    bands: List<BandSection>,
    onLevelClick: (levelNumber: Int) -> Unit,
    onBandTestClick: (targetBand: Double) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(bands, key = { it.score }) { band ->
            BandCard(
                band = band,
                onLevelClick = onLevelClick,
                onBandTestClick = onBandTestClick,
            )
        }
    }
}

@Composable
private fun BandCard(
    band: BandSection,
    onLevelClick: (levelNumber: Int) -> Unit,
    onBandTestClick: (targetBand: Double) -> Unit,
) {
    var expanded by rememberSaveable(band.score) { mutableStateOf(band.isCurrent) }

    Card(
        modifier = Modifier.fillMaxWidth(),
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
                Text(if (band.isUnlocked) "Open" else "Locked", fontSize = 16.sp)
                Column(Modifier.weight(1f)) {
                    Text(
                        band.label,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        when {
                            band.isCurrent ->
                                "Current band - ${band.unlockedLevelCount}/${band.levels.size} levels unlocked"
                            band.isUnlocked ->
                                "${band.completedLevelCount}/${band.levels.size} levels completed"
                            else ->
                                "Pass the previous band exam to unlock"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (band.isUnlocked) {
                    TextButton(onClick = { expanded = !expanded }) {
                        Text(if (expanded) "Collapse" else "Expand")
                    }
                } else {
                    OutlinedButton(onClick = { onBandTestClick(band.score) }) {
                        Text("Band exam")
                    }
                }
            }

            if (expanded && band.isUnlocked) {
                band.levels.forEachIndexed { index, level ->
                    LevelRow(
                        level = level,
                        displayTitle = levelTopicDisplayName(band.levels, index),
                        onClick = { onLevelClick(level.number) },
                    )
                }
            }
        }
    }
}

@Composable
private fun LevelRow(level: Level, displayTitle: String, onClick: () -> Unit) {
    val statusText = when {
        level.isCompleted -> buildString {
            append("Completed")
            if (level.completedSessionCount > 0) {
                append(" - best accuracy ")
                append((level.bestAccuracy * 100).toInt())
                append("%")
                append(" - ")
                append(level.bestStarRating)
                append(" stars")
                append(" - practiced ")
                append(level.completedSessionCount)
                append(" times")
            }
        }
        level.isUnlocked && level.completedSessionCount > 0 ->
            "In progress - best accuracy ${(level.bestAccuracy * 100).toInt()}% - " +
                "${level.bestStarRating} stars - practiced ${level.completedSessionCount} times"
        level.isUnlocked -> "Unlocked - not practiced yet"
        else -> "Locked"
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (level.isUnlocked) 1f else 0.55f)
            .then(if (level.isUnlocked) Modifier.clickable(onClick = onClick) else Modifier),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                when {
                    level.isCompleted -> "Done"
                    level.isUnlocked -> "Start"
                    else -> "Locked"
                },
                fontSize = 22.sp,
            )
            Column(Modifier.weight(1f)) {
                Text(
                    displayTitle,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    statusText,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                text = if (level.isUnlocked) "Open" else "Locked",
                style = MaterialTheme.typography.labelMedium,
                color = if (level.isUnlocked) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant,
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
        Text("!")
        Spacer(Modifier.height(8.dp))
        Text("Unable to load", style = MaterialTheme.typography.titleMedium)
        Text(
            message,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        Button(onClick = onRetry) { Text("Retry") }
    }
}
