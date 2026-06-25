package com.example.firsttest.ui.level

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
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.model.LevelPracticeQuestion
import com.example.firsttest.data.model.MeaningChoiceOption

@Composable
fun LevelPracticeScreen(
    levelNumber: Int,
    attemptId: Long,
    onBack: () -> Unit,
    onSessionComplete: (correctCount: Int, totalCount: Int, starRating: Int, duckPowerEarned: Int) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: LevelPracticeViewModel = viewModel(
        key = "lp_level_${levelNumber}_attempt_$attemptId",
        factory = LevelPracticeViewModel.factory(levelNumber),
    ),
) {
    val uiState by viewModel.uiState.collectAsState()

    if (uiState is LevelPracticeUiState.Finished) {
        val f = uiState as LevelPracticeUiState.Finished
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
            is LevelPracticeUiState.Loading ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }

            is LevelPracticeUiState.Error ->
                ErrorContent(state.message, viewModel::retry, onBack)

            is LevelPracticeUiState.Answering -> {
                TopBar(
                    levelNumber = levelNumber,
                    current = state.questionIndex + 1,
                    total = state.totalQuestions,
                    comboCount = state.comboCount,
                    onBack = onBack,
                )
                QuestionCard(state.question)
                Spacer(Modifier.height(4.dp))
                if (state.question.answerForm == "keyboard") {
                    ClozeInput(
                        value = state.typedAnswer,
                        onValueChange = viewModel::onTypedAnswerChanged,
                        onSubmit = viewModel::onSubmit,
                        enabled = !state.isSubmitting,
                    )
                } else {
                    OptionList(
                        options = state.question.options,
                        selectedId = state.selectedOptionId,
                        reviewingCorrectId = null,
                        reviewingSelectedId = null,
                        onSelect = viewModel::onOptionSelected,
                    )
                }
                Spacer(Modifier.height(4.dp))
                Button(
                    onClick = viewModel::onSubmit,
                    enabled = state.submitEnabled,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("提交") }
            }

            is LevelPracticeUiState.Reviewing -> {
                TopBar(
                    levelNumber = levelNumber,
                    current = state.questionIndex + 1,
                    total = state.totalQuestions,
                    comboCount = state.comboCount,
                    onBack = onBack,
                )
                QuestionCard(state.question)
                Spacer(Modifier.height(4.dp))
                if (state.question.answerForm == "keyboard") {
                    ClozeReview(
                        submittedAnswer = state.submittedAnswer,
                        correctAnswer   = state.correctAnswer ?: "",
                        isCorrect       = state.isCorrect,
                    )
                } else {
                    OptionList(
                        options = state.question.options,
                        selectedId = null,
                        reviewingCorrectId = state.correctOptionId,
                        reviewingSelectedId = state.submittedAnswer,
                        onSelect = {},
                    )
                }
                Spacer(Modifier.height(4.dp))
                ReviewPanel(
                    answerOutcome = state.answerOutcome,
                    translationZh = state.question.translationZh,
                )
                Spacer(Modifier.height(4.dp))
                val isLast = state.questionIndex + 1 == state.totalQuestions
                Button(
                    onClick = viewModel::onNext,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(if (isLast) "查看结果" else "下一题") }
            }

            is LevelPracticeUiState.Finished -> { /* handled above via LaunchedEffect */ }
        }
    }
}

// ---- Sub-components ---------------------------------------------------------

@Composable
private fun TopBar(
    levelNumber: Int,
    current: Int,
    total: Int,
    comboCount: Int,
    onBack: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TextButton(onClick = onBack) { Text("‹ 返回") }
        Spacer(Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                "Level $levelNumber 练习",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "$current / $total",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
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
private fun QuestionCard(question: LevelPracticeQuestion) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                text = question.promptHint.ifBlank {
                    if (question.answerForm == "keyboard") "填写正确的单词" else "选择正确的释义"
                },
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = question.stem,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun ClozeInput(
    value: String,
    onValueChange: (String) -> Unit,
    onSubmit: () -> Unit,
    enabled: Boolean,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text("输入单词") },
        singleLine = true,
        enabled = enabled,
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { if (value.isNotBlank()) onSubmit() }),
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun ClozeReview(
    submittedAnswer: String,
    correctAnswer: String,
    isCorrect: Boolean,
) {
    val labelColor = if (isCorrect) MaterialTheme.colorScheme.primary
                     else MaterialTheme.colorScheme.error
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = "你的答案：$submittedAnswer",
            style = MaterialTheme.typography.bodyMedium,
            color = labelColor,
            fontWeight = FontWeight.SemiBold,
        )
        if (!isCorrect) {
            Text(
                text = "正确答案：$correctAnswer",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

@Composable
private fun OptionList(
    options: List<MeaningChoiceOption>,
    selectedId: String?,
    reviewingCorrectId: String?,
    reviewingSelectedId: String?,
    onSelect: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { option ->
            OptionButton(
                option = option,
                isSelected = option.optionId == selectedId,
                isReviewingCorrect = option.optionId == reviewingCorrectId,
                isReviewingWrongSelection = option.optionId == reviewingSelectedId &&
                        option.optionId != reviewingCorrectId,
                onClick = { onSelect(option.optionId) },
            )
        }
    }
}

@Composable
private fun OptionButton(
    option: MeaningChoiceOption,
    isSelected: Boolean,
    isReviewingCorrect: Boolean,
    isReviewingWrongSelection: Boolean,
    onClick: () -> Unit,
) {
    val containerColor = when {
        isReviewingCorrect        -> MaterialTheme.colorScheme.primaryContainer
        isReviewingWrongSelection -> MaterialTheme.colorScheme.errorContainer
        isSelected                -> MaterialTheme.colorScheme.secondaryContainer
        else                      -> MaterialTheme.colorScheme.surface
    }
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = containerColor),
    ) {
        Text(
            text = option.text,
            fontWeight = if (isSelected || isReviewingCorrect) FontWeight.SemiBold else FontWeight.Normal,
            fontSize = 14.sp,
        )
    }
}

@Composable
private fun ReviewPanel(answerOutcome: String, translationZh: String) {
    val isCorrect = answerOutcome == "full_correct" || answerOutcome == "assisted_correct"
    val bgColor = if (isCorrect) MaterialTheme.colorScheme.primaryContainer
                  else MaterialTheme.colorScheme.errorContainer
    val textColor = if (isCorrect) MaterialTheme.colorScheme.onPrimaryContainer
                    else MaterialTheme.colorScheme.onErrorContainer
    val headline = when (answerOutcome) {
        "full_correct"          -> "✅ 回答正确！"
        "assisted_correct"      -> "✅ 辅助正确"
        "remediation_completed" -> "📖 已复习"
        else                    -> "❌ 回答错误"
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = bgColor),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                headline,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = textColor,
            )
            if (translationZh.isNotBlank()) {
                Text(
                    "释义：$translationZh",
                    style = MaterialTheme.typography.bodySmall,
                    color = textColor,
                )
            }
        }
    }
}

@Composable
private fun ErrorContent(message: String, onRetry: () -> Unit, onBack: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("⚠️", style = MaterialTheme.typography.displaySmall)
        Spacer(Modifier.height(8.dp))
        Text("加载题目失败", style = MaterialTheme.typography.titleMedium)
        Text(
            message,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        Button(onClick = onRetry) { Text("重试") }
        Spacer(Modifier.height(8.dp))
        TextButton(onClick = onBack) { Text("返回") }
    }
}
