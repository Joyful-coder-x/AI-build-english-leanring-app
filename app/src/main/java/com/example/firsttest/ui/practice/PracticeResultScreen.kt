package com.example.firsttest.ui.practice

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel

/**
 * Session summary shown after all questions are answered. Displays accuracy,
 * star rating, and duck power earned. [onReturnHome] navigates back to the
 * learning path.
 */
@Composable
fun PracticeResultScreen(
    levelNumber: Int?,
    correctCount: Int,
    totalCount: Int,
    starRating: Int,
    duckPowerEarned: Int,
    onRepeat: (() -> Unit)?,
    onReturnHome: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: PracticeResultViewModel = viewModel(
        factory = PracticeResultViewModel.Factory,
    ),
) {
    var wordListExpanded by remember { mutableStateOf(false) }
    val wordListState by viewModel.wordList.collectAsState()

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp, vertical = 20.dp),
    ) {
        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            item {
                Text(
                    "练习完成！",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                )
            }

            item {
                Text(
                    starsString(starRating),
                    fontSize = 48.sp,
                    textAlign = TextAlign.Center,
                )
            }

            item {
                Card(Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        StatLine("✅  答对题数", "$correctCount / $totalCount")
                        StatLine(
                            "📊  正确率",
                            if (totalCount > 0) "${(correctCount * 100 / totalCount)}%" else "—",
                        )
                        StatLine("⚡  获得鸭力值", "+$duckPowerEarned")
                    }
                }
            }

            item {
                Text(
                    encouragement(starRating),
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (levelNumber != null) {
                item {
                    OutlinedButton(
                        onClick = {
                            wordListExpanded = !wordListExpanded
                            if (wordListExpanded) viewModel.loadLevelWords(levelNumber)
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(if (wordListExpanded) "收起本关单词" else "本关单词与状态")
                    }
                }

                if (wordListExpanded) {
                    when (val state = wordListState) {
                        LevelWordListState.Idle,
                        LevelWordListState.Loading -> item {
                            CircularProgressIndicator()
                        }

                        is LevelWordListState.Error -> item {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(state.message, color = MaterialTheme.colorScheme.error)
                                TextButton(onClick = { viewModel.loadLevelWords(levelNumber) }) {
                                    Text("重试")
                                }
                            }
                        }

                        is LevelWordListState.Ready -> {
                            items(
                                count = state.words.size,
                                key = { state.words[it].senseId },
                            ) { index ->
                                val word = state.words[index]
                                Card(Modifier.fillMaxWidth()) {
                                    Column(
                                        Modifier.padding(14.dp),
                                        verticalArrangement = Arrangement.spacedBy(4.dp),
                                    ) {
                                        androidx.compose.foundation.layout.Row(
                                            Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                        ) {
                                            Text(word.word, fontWeight = FontWeight.Bold)
                                            Text(
                                                if (word.isDue) "${word.status} · 待复习"
                                                else word.status,
                                                color = MaterialTheme.colorScheme.primary,
                                            )
                                        }
                                        Text(
                                            word.definitionZh,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                        if (word.wrongCount > 0) {
                                            Text(
                                                "累计答错 ${word.wrongCount} 次",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.error,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (levelNumber != null && onRepeat != null) {
                Button(onClick = onRepeat, modifier = Modifier.fillMaxWidth()) {
                    Text("再练一轮（重新组题）")
                }
            }

            OutlinedButton(onClick = onReturnHome, modifier = Modifier.fillMaxWidth()) {
                Text("返回首页")
            }
        }
    }
}

@Composable
private fun StatLine(label: String, value: String) {
    androidx.compose.foundation.layout.Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge)
        Text(value, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Bold)
    }
}

private fun starsString(rating: Int): String {
    val r = rating.coerceIn(0, 3)
    return "★".repeat(r) + "☆".repeat(3 - r)
}

private fun encouragement(stars: Int): String = when (stars) {
    3 -> "太棒了！满分完成，鸭力值暴涨！🎉"
    2 -> "做得不错！继续练习，马上就能三星！💪"
    1 -> "继续加油！多练几遍，你一定可以的！🦆"
    else -> "没关系，每一次练习都是进步！重新来过！"
}
