package com.example.firsttest.ui.practice

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel

/**
 * The answering flow for one practice session. Cycles through questions
 * showing Answering → Reviewing per question, then calls [onSessionComplete]
 * when all questions are done.
 *
 * Hosted inside MainScreen's Scaffold — no separate Scaffold here.
 */
@Composable
fun PracticeQuestionScreen(
    cardId: String,
    onBack: () -> Unit,
    onSessionComplete: (correctCount: Int, totalCount: Int, starRating: Int, duckPowerEarned: Int) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: PracticeViewModel = viewModel(
        key = cardId,
        factory = PracticeViewModel.factory(cardId),
    ),
) {
    val uiState by viewModel.uiState.collectAsState()

    if (uiState is PracticeUiState.Finished) {
        val f = uiState as PracticeUiState.Finished
        LaunchedEffect(f) {
            onSessionComplete(f.correctCount, f.totalCount, f.starRating, f.duckPowerEarned)
        }
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        when (val state = uiState) {
            is PracticeUiState.Loading -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }

            is PracticeUiState.Error -> {
                Column(
                    modifier = Modifier.fillMaxSize().padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text("⚠️", style = MaterialTheme.typography.displaySmall)
                    Spacer(Modifier.height(8.dp))
                    Text("加载题目失败", style = MaterialTheme.typography.titleMedium)
                    Text(
                        state.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(16.dp))
                    Button(onClick = viewModel::retry) { Text("重试") }
                    Spacer(Modifier.height(8.dp))
                    TextButton(onClick = onBack) { Text("返回") }
                }
            }

            is PracticeUiState.Answering -> {
                var remainingSecs by remember(state.question.id) {
                    mutableStateOf(state.question.expectedTimeMs / 1000)
                }
                LaunchedEffect(state.question.id) {
                    while (remainingSecs > 0) {
                        delay(1_000L)
                        remainingSecs--
                    }
                }
                TopBar(
                    onBack = onBack,
                    current = state.questionIndex + 1,
                    total = state.totalQuestions,
                    comboCount = state.comboCount,
                    remainingSecs = remainingSecs,
                )
                PromptHint(state.question.promptHint)
                QuestionStem(state.question.stem)
                Spacer(Modifier.height(8.dp))
                AnswerArea(
                    typeCode = state.question.typeCode,
                    options = state.question.options,
                    currentAnswer = state.currentAnswer,
                    onAnswerChanged = viewModel::onAnswerChanged,
                )
                if (state.showLetterHint) {
                    Text(
                        "提示：${state.question.correctAnswer.length} 个字母",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (state.nearMeaningFeedback != null) {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        ),
                    ) {
                        Text(
                            state.nearMeaningFeedback,
                            modifier = Modifier.padding(12.dp),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSecondaryContainer,
                        )
                    }
                }
                Spacer(Modifier.height(8.dp))
                Button(
                    onClick = viewModel::onSubmit,
                    enabled = state.submitEnabled,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("提交") }
            }

            is PracticeUiState.ShowingClozeAnswer -> {
                TopBar(
                    onBack = onBack,
                    current = state.questionIndex + 1,
                    total = state.totalQuestions,
                    comboCount = state.comboCount,
                )
                PromptHint(state.question.promptHint)
                QuestionStem(state.question.stem)
                Spacer(Modifier.height(8.dp))
                ClozeAnswerRevealCard(
                    targetWord = state.question.correctAnswer,
                    translationZh = state.question.translationZh,
                    onReady = viewModel::onClozeAnswerSeen,
                )
            }

            is PracticeUiState.ClozeMemoryRetype -> {
                TopBar(
                    onBack = onBack,
                    current = state.questionIndex + 1,
                    total = state.totalQuestions,
                    comboCount = state.comboCount,
                )
                PromptHint(state.question.promptHint)
                QuestionStem(state.question.stem)
                Spacer(Modifier.height(4.dp))
                Text(
                    "现在从记忆中作答：",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                KeyboardInput(
                    value = state.currentAnswer,
                    onValueChange = viewModel::onAnswerChanged,
                )
                Spacer(Modifier.height(8.dp))
                Button(
                    onClick = viewModel::onSubmit,
                    enabled = state.submitEnabled,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("提交") }
            }

            is PracticeUiState.Reviewing -> {
                TopBar(
                    onBack = onBack,
                    current = state.questionIndex + 1,
                    total = state.totalQuestions,
                    comboCount = state.comboCount,
                )
                PromptHint(state.question.promptHint)
                QuestionStem(state.question.stem)
                Spacer(Modifier.height(8.dp))
                ResultPanel(
                    isCorrect = state.isCorrect,
                    givenAnswer = state.givenAnswer,
                    correctAnswer = state.question.correctAnswer,
                    translationZh = state.question.translationZh,
                    clozeResult = state.clozeResult,
                )
                Spacer(Modifier.height(8.dp))
                val isLastQuestion = state.questionIndex + 1 == state.totalQuestions
                Button(
                    onClick = viewModel::onNext,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(if (isLastQuestion) "查看结果" else "下一题") }
            }

            is PracticeUiState.Finished -> { /* handled above */ }
        }
    }
}

// ---- Sub-components ---------------------------------------------------------

@Composable
private fun TopBar(
    onBack: () -> Unit,
    current: Int,
    total: Int,
    comboCount: Int,
    remainingSecs: Int = -1,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TextButton(onClick = onBack) { Text("‹ 返回") }
        Spacer(Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                "$current / $total",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            if (remainingSecs >= 0) {
                Text(
                    "⏱ ${remainingSecs}s",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (remainingSecs <= 5) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.weight(1f))
        Text(
            text = if (comboCount > 1) "🔥 ${comboCount}连击" else "        ",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}

@Composable
private fun PromptHint(hint: String) {
    Text(
        hint,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun QuestionStem(stem: String) {
    Card(Modifier.fillMaxWidth()) {
        Text(
            stem,
            modifier = Modifier.padding(16.dp),
            style = MaterialTheme.typography.bodyLarge,
            lineHeight = 28.sp,
        )
    }
}

@Composable
private fun AnswerArea(
    typeCode: Int,
    options: List<String>,
    currentAnswer: String,
    onAnswerChanged: (String) -> Unit,
) {
    when (typeCode) {
        2 -> MultipleChoiceOptions(
            options = options,
            selected = currentAnswer,
            onSelect = onAnswerChanged,
        )
        1, 3 -> KeyboardInput(
            value = currentAnswer,
            onValueChange = onAnswerChanged,
        )
    }
}

@Composable
private fun MultipleChoiceOptions(
    options: List<String>,
    selected: String,
    onSelect: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { option ->
            val isSelected = option == selected
            OutlinedButton(
                onClick = { onSelect(option) },
                modifier = Modifier.fillMaxWidth(),
                colors = if (isSelected) ButtonDefaults.outlinedButtonColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                ) else ButtonDefaults.outlinedButtonColors(),
            ) {
                Text(
                    option,
                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                )
            }
        }
    }
}

@Composable
private fun KeyboardInput(value: String, onValueChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text("输入答案") },
        singleLine = true,
    )
}

@Composable
private fun ClozeAnswerRevealCard(
    targetWord: String,
    translationZh: String,
    onReady: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.tertiaryContainer,
        ),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                "目标词：$targetWord",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onTertiaryContainer,
            )
            Text(
                translationZh,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onTertiaryContainer,
            )
            Text(
                "花一点时间记住它。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onTertiaryContainer,
            )
        }
    }
    Spacer(Modifier.height(8.dp))
    Button(
        onClick = onReady,
        modifier = Modifier.fillMaxWidth(),
    ) { Text("我记住了，开始作答") }
}

@Composable
private fun ResultPanel(
    isCorrect: Boolean,
    givenAnswer: String,
    correctAnswer: String,
    translationZh: String,
    clozeResult: ClozeResult? = null,
) {
    when (clozeResult) {
        ClozeResult.MEMORY_RETYPE_CORRECT -> {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.secondaryContainer,
                ),
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        "记住了。你从记忆中写出了这个词。",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                    Text(
                        "正确答案：$correctAnswer",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                    Text(
                        translationZh,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                }
            }
        }

        ClozeResult.WRONG -> {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer,
                ),
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        "❌ 回答错误",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                    )
                    Text(
                        "正确答案：$correctAnswer",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                    )
                    Text(
                        translationZh,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                    )
                }
            }
        }

        else -> {
            // Type 1, 2, and type 3 FIRST_TRY_CORRECT / HINT_CORRECT
            val bgColor = if (isCorrect) MaterialTheme.colorScheme.primaryContainer
                          else MaterialTheme.colorScheme.errorContainer
            val textColor = if (isCorrect) MaterialTheme.colorScheme.onPrimaryContainer
                            else MaterialTheme.colorScheme.onErrorContainer
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = bgColor),
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        when {
                            isCorrect && clozeResult == ClozeResult.HINT_CORRECT -> "✅ 回答正确！（提示后）"
                            isCorrect -> "✅ 回答正确！"
                            else -> "❌ 回答错误"
                        },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = textColor,
                    )
                    if (!isCorrect) {
                        Text(
                            "你的答案：$givenAnswer",
                            style = MaterialTheme.typography.bodyMedium,
                            color = textColor,
                        )
                        Text(
                            "正确答案：$correctAnswer",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Bold,
                            color = textColor,
                        )
                    }
                    Text(
                        translationZh,
                        style = MaterialTheme.typography.bodySmall,
                        color = textColor,
                    )
                }
            }
        }
    }
}
