package com.example.firsttest.ui.level

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.model.LevelWordStatus

private val ColorMastered = Color(0xFF66BB6A)
private val ColorStarted = Color(0xFFFFB300)

@Composable
fun LevelProgressScreen(
    levelNumber: Int,
    onBack: () -> Unit,
    onStartPractice: (levelNumber: Int) -> Unit,
    viewModel: LevelProgressViewModel = viewModel(
        key = "level_progress_$levelNumber",
        factory = LevelProgressViewModel.factory(levelNumber),
    ),
) {
    val uiState by viewModel.uiState.collectAsState()

    Column(Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 4.dp, end = 16.dp, top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onBack) { Text("Back") }
            Text(
                "Level $levelNumber",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
        }
        HorizontalDivider()

        when (val state = uiState) {
            is LevelProgressUiState.Loading ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }

            is LevelProgressUiState.Error ->
                Column(
                    Modifier.fillMaxSize().padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text("Unable to load level progress", style = MaterialTheme.typography.titleMedium)
                    Text(
                        state.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(16.dp))
                    Button(onClick = viewModel::retry) { Text("Retry") }
                }

            is LevelProgressUiState.Success ->
                LevelProgressContent(
                    state = state,
                    onStartPractice = { onStartPractice(levelNumber) },
                )
        }
    }
}

@Composable
private fun LevelProgressContent(
    state: LevelProgressUiState.Success,
    onStartPractice: () -> Unit,
) {
    if (!state.isUnlocked) {
        LockedLevelContent()
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SummaryChip(
                modifier = Modifier.weight(1f),
                color = ColorMastered,
                count = state.masteredCount,
                total = state.words.size,
                label = "Mastered",
            )
            SummaryChip(
                modifier = Modifier.weight(1f),
                color = ColorStarted,
                count = state.startedCount,
                total = state.words.size,
                label = "Started",
            )
        }

        Button(
            onClick = onStartPractice,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Start practice", fontSize = 16.sp)
        }

        Text(
            "Words in this level - ${state.words.size}",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        WordGrid(words = state.words)

        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            LegendItem(ColorMastered, "Mastered")
            LegendItem(ColorStarted, "Learning")
            LegendItem(MaterialTheme.colorScheme.surfaceVariant, "Not started")
        }
    }
}

@Composable
private fun LockedLevelContent() {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            "Level locked",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            "Complete the previous level to unlock this one.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun SummaryChip(
    modifier: Modifier = Modifier,
    color: Color,
    count: Int,
    total: Int,
    label: String,
) {
    Card(modifier) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                Modifier
                    .size(16.dp)
                    .background(color, RoundedCornerShape(3.dp)),
            )
            Column {
                Text(
                    "$count / $total",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
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
private fun WordGrid(words: List<LevelWordStatus>) {
    val columns = 9
    val rows = (words.size + columns - 1) / columns

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(rows) { rowIndex ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                repeat(columns) { colIndex ->
                    val index = rowIndex * columns + colIndex
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .aspectRatio(1f)
                            .background(
                                color = if (index < words.size) {
                                    statusColor(words[index])
                                } else {
                                    Color.Transparent
                                },
                                shape = RoundedCornerShape(4.dp),
                            ),
                    )
                }
            }
        }
    }
}

@Composable
private fun statusColor(word: LevelWordStatus): Color = when {
    word.isMasteredStatus() -> ColorMastered
    word.isReviewingStatus() || word.isStartedStatus() -> ColorStarted
    else -> MaterialTheme.colorScheme.surfaceVariant
}

@Composable
private fun LegendItem(color: Color, label: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(
            Modifier
                .size(12.dp)
                .background(color, RoundedCornerShape(2.dp)),
        )
        Text(label, style = MaterialTheme.typography.bodySmall)
    }
}
