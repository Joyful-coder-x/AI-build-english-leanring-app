package com.example.firsttest.ui.mistakes

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Badge
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.model.MistakeWord

/**
 * 错词本 tab screen (spec 2.3).
 *
 * Displays all words the user has answered incorrectly during practice.
 * Each word shows its Ebbinghaus review stage and next-review date.
 * Empty state is shown when no mistakes exist (spec 2.3.1: "用户无错词的情况下，
 * 错词本初始状态为空").
 *
 * TODO PHASE 3: "开始复习" per-word or "全部复习" button should launch a
 *   targeted practice session for due words (filtered by reviewStage/date).
 * TODO PHASE 3: words are added here when PracticeViewModel.onSubmit()
 *   records a wrong answer (needs Supabase mistake_words table).
 */
@Composable
fun MistakesScreen(
    modifier: Modifier = Modifier,
    viewModel: MistakesViewModel = viewModel(factory = MistakesViewModel.Factory),
) {
    val uiState by viewModel.uiState.collectAsState()
    when (val s = uiState) {
        is MistakesUiState.Loading ->
            Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }

        is MistakesUiState.Empty ->
            EmptyState(modifier)

        is MistakesUiState.Error ->
            ErrorState(s.message, onRetry = viewModel::retry, modifier = modifier)

        is MistakesUiState.Success ->
            Column(modifier.fillMaxSize()) {
                // Header
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        "错词本",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        "共 ${s.words.size} 个单词",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(
                        horizontal = 16.dp, vertical = 4.dp
                    ),
                ) {
                    items(s.words, key = { it.wordId }) { word ->
                        MistakeWordCard(word)
                    }
                }
            }
    }
}

@Composable
private fun ErrorState(message: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("⚠️", style = MaterialTheme.typography.displaySmall)
        Spacer(Modifier.height(8.dp))
        Text("加载失败", style = MaterialTheme.typography.titleMedium)
        Text(
            message,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        Button(onClick = onRetry) { Text("重试") }
    }
}

@Composable
private fun EmptyState(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("🦆", fontSize = 56.sp)
        Text(
            "暂无错词，继续保持！",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        Text(
            "答题遇到不会的单词会自动出现在这里",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun MistakeWordCard(word: MistakeWord) {
    Card(Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Word info
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    word.headword,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    word.phonetic,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    word.definitionZh,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            // Review info
            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                StageBadge(word.reviewStage)
                Text(
                    word.nextReviewLabel,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** Shows the Ebbinghaus review stage as a coloured badge. */
@Composable
private fun StageBadge(stage: Int) {
    val label = when (stage) {
        0 -> "新错误"
        1 -> "第1遍"
        2 -> "第2遍"
        3 -> "第3遍"
        4 -> "第4遍"
        else -> "第5遍"
    }
    // Stages 0-1 = primary (urgent), 2-3 = secondary, 4-5 = muted
    val containerColor = when (stage) {
        0, 1 -> MaterialTheme.colorScheme.errorContainer
        2, 3 -> MaterialTheme.colorScheme.secondaryContainer
        else -> MaterialTheme.colorScheme.surfaceVariant
    }
    val contentColor = when (stage) {
        0, 1 -> MaterialTheme.colorScheme.onErrorContainer
        2, 3 -> MaterialTheme.colorScheme.onSecondaryContainer
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Badge(containerColor = containerColor, contentColor = contentColor) {
        Text(label, style = MaterialTheme.typography.labelSmall)
    }
}
