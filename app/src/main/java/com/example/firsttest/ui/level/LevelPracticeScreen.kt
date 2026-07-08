package com.example.firsttest.ui.level

import android.speech.tts.TextToSpeech
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.model.LevelPracticeQuestion
import com.example.firsttest.data.model.MeaningChoiceOption
import java.util.Locale

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

    // Android built-in TTS engine for listening question types
    val context = LocalContext.current
    var ttsEngine: TextToSpeech? by remember { mutableStateOf(null) }
    DisposableEffect(context) {
        lateinit var engine: TextToSpeech
        engine = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                engine.language = Locale.US
                ttsEngine = engine
            }
        }
        onDispose {
            engine.shutdown()
            ttsEngine = null
        }
    }

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
                var showHint by remember(state.question.questionId) { mutableStateOf(false) }
                TopBar(
                    levelNumber = levelNumber,
                    current = state.questionIndex + 1,
                    total = state.totalQuestions,
                    comboCount = state.comboCount,
                    onBack = onBack,
                )
                QuestionCard(state.question, tts = ttsEngine, autoSpeak = true)
                Spacer(Modifier.height(4.dp))
                if (state.question.answerForm == "keyboard") {
                    ClozeInput(
                        value = state.typedAnswer,
                        onValueChange = viewModel::onTypedAnswerChanged,
                        onSubmit = viewModel::onSubmit,
                        enabled = !state.isSubmitting,
                        letterCount = state.letterCount,
                        lastWrongAnswer = state.lastWrongAnswer,
                        feedback = state.feedback,
                    )
                    if (showHint && state.question.translationZh.isNotBlank()) {
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                            ),
                        ) {
                            Text(
                                state.question.translationZh,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onTertiaryContainer,
                            )
                        }
                    }
                    TextButton(
                        onClick = { showHint = !showHint },
                        modifier = Modifier.align(Alignment.CenterHorizontally),
                    ) {
                        Text(if (showHint) "隐藏提示" else "查看中文提示")
                    }
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

            is LevelPracticeUiState.SpellingCorrection -> {
                TopBar(
                    levelNumber = levelNumber,
                    current = state.questionIndex + 1,
                    total = state.totalQuestions,
                    comboCount = state.comboCount,
                    onBack = onBack,
                )
                QuestionCard(state.question, tts = ttsEngine)
                SpellingCorrectionPanel(
                    lastWrongAnswer = state.lastWrongAnswer,
                    correctAnswer = state.correctAnswer,
                )
                if (state.retryWrongAnswer.isNotBlank()) {
                    RetryFeedbackPanel(
                        retryWrongAnswer = state.retryWrongAnswer,
                        correctAnswer = state.correctAnswer,
                        tooManyTypos = state.retryTooManyTypos,
                    )
                }
                ClozeInput(
                    value = state.typedAnswer,
                    onValueChange = viewModel::onTypedAnswerChanged,
                    onSubmit = viewModel::onSubmit,
                    enabled = !state.isSubmitting,
                    letterCount = null,
                    lastWrongAnswer = "",
                    feedback = "",
                )
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
                QuestionCard(state.question, tts = ttsEngine)
                Spacer(Modifier.height(4.dp))
                if (state.question.answerForm == "keyboard") {
                    ClozeReview(
                        submittedAnswer = state.submittedAnswer,
                        correctAnswer   = state.correctAnswer ?: "",
                        answerOutcome   = state.answerOutcome,
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
private fun QuestionCard(
    question: LevelPracticeQuestion,
    tts: TextToSpeech? = null,
    autoSpeak: Boolean = false,
) {
    val questionTypeKey = effectiveQuestionTypeKey(question)
    val listeningWord = listeningSpeechText(question, questionTypeKey)
    val replayAudio = {
        listeningWord?.let { speechText ->
            tts?.speak(
                speechText,
                TextToSpeech.QUEUE_FLUSH,
                null,
                question.questionId + "_replay",
            )
        }
        Unit
    }

    // Auto-speak when the question first appears (Answering state only)
    if (autoSpeak && listeningWord != null && tts != null) {
        LaunchedEffect(question.questionId) {
            tts.speak(listeningWord, TextToSpeech.QUEUE_FLUSH, null, question.questionId)
        }
    }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            // Type header
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(questionTypeIcon(questionTypeKey), fontSize = 16.sp)
                Text(
                    text = questionTypeTitle(questionTypeKey),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            Text(
                text = question.promptHint.ifBlank { questionTypeInstruction(questionTypeKey, question.answerForm) },
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Type-specific content area
            when (questionTypeKey) {
                "listening_choice" -> {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                        ),
                    ) {
                        Column(
                            modifier = Modifier
                                .padding(16.dp)
                                .fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Text("🔊", fontSize = 40.sp)
                            Text(
                                "已播放语音，请选择你听到的单词",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onTertiaryContainer.copy(alpha = 0.7f),
                            )
                            OutlinedButton(
                                onClick = replayAudio,
                                enabled = listeningWord != null && tts != null,
                            ) {
                                Text("🔊 再听一次")
                            }
                        }
                    }
                }

                "listening_fill" -> {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                        ),
                    ) {
                        Column(
                            modifier = Modifier
                                .padding(16.dp)
                                .fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Text("🎧", fontSize = 40.sp)
                            if (question.translationZh.isNotBlank()) {
                                Text(
                                    question.translationZh,
                                    style = MaterialTheme.typography.titleMedium,
                                    color = MaterialTheme.colorScheme.onTertiaryContainer,
                                )
                            }
                            Text(
                                "听语音，拼写你听到的英文单词",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onTertiaryContainer.copy(alpha = 0.6f),
                            )
                            OutlinedButton(
                                onClick = replayAudio,
                                enabled = listeningWord != null && tts != null,
                            ) {
                                Text("🔊 再听一次")
                            }
                        }
                    }
                }

                "speaking_repeat" -> {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        ),
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text("🎤", fontSize = 28.sp)
                            Text(
                                text = question.stem,
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSecondaryContainer,
                            )
                        }
                    }
                }

                "open_speaking" -> {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        ),
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text("🗣️", fontSize = 28.sp)
                            Text(
                                text = question.stem,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSecondaryContainer,
                            )
                        }
                    }
                }

                "reading_comprehension" -> {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        ),
                    ) {
                        Text(
                            text = question.stem,
                            style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier.padding(16.dp),
                        )
                    }
                }

                "word_form" -> {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        ),
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Text("🔤", fontSize = 28.sp)
                            Text(
                                text = question.stem,
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                    }
                }

                else -> {
                    Text(
                        text = question.stem,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}

private fun effectiveQuestionTypeKey(question: LevelPracticeQuestion): String {
    if (question.questionTypeKey == "listening_choice" || question.questionTypeKey == "listening_fill") {
        return question.questionTypeKey
    }

    val text = "${question.promptHint} ${question.stem}".lowercase()
    val isListeningPrompt = "listen" in text || "heard word" in text || "word you hear" in text
    if (!isListeningPrompt) return question.questionTypeKey

    return if (question.answerForm == "keyboard" || "type" in text || "spell" in text) {
        "listening_fill"
    } else {
        "listening_choice"
    }
}

private fun listeningSpeechText(
    question: LevelPracticeQuestion,
    questionTypeKey: String,
): String? {
    if (questionTypeKey != "listening_choice" && questionTypeKey != "listening_fill") return null

    val quotedWord = Regex("says\\s+\"([^\"]+)\"", RegexOption.IGNORE_CASE)
        .find(question.stem)
        ?.groupValues
        ?.get(1)

    return (
        question.audioText
            ?: quotedWord
            ?: question.revealedAnswer
            ?: question.stem.takeIf { it.isSingleEnglishWord() }
        )?.englishOnly()
}

private fun String.englishOnly(): String? =
    replace(Regex("[^\\x00-\\x7F]+"), " ")
        .replace(Regex("\\s+"), " ")
        .trim()
        .takeIf { it.isNotBlank() }

private fun String.isSingleEnglishWord(): Boolean =
    trim().matches(Regex("[A-Za-z][A-Za-z'-]*"))

private fun questionTypeIcon(questionTypeKey: String): String = when (questionTypeKey) {
    "meaning_choice", "option_recognition" -> "📖"
    "sentence_cloze_typing" -> "✍️"
    "listening_choice" -> "🔊"
    "listening_fill" -> "🎧"
    "speaking_repeat" -> "🎤"
    "open_speaking" -> "🗣️"
    "word_form" -> "🔤"
    "reading_comprehension" -> "📄"
    else -> "❓"
}

private fun questionTypeTitle(questionTypeKey: String): String = when (questionTypeKey) {
    "meaning_choice", "option_recognition" -> "单词选义"
    "sentence_cloze_typing" -> "句子填空"
    "listening_choice" -> "听力选词"
    "listening_fill" -> "听力拼写"
    "speaking_repeat" -> "口语复读"
    "open_speaking" -> "开口说"
    "word_form" -> "词形变换"
    "reading_comprehension" -> "阅读理解"
    else -> questionTypeKey.replace('_', ' ').replaceFirstChar { it.uppercase() }
}

private fun questionTypeInstruction(questionTypeKey: String, answerForm: String): String =
    when (questionTypeKey) {
        "meaning_choice" -> "选择正确的中文释义"
        "sentence_cloze_typing" -> "填写空格中的目标词"
        "listening_choice" -> "听完后选择你听到的单词"
        "listening_fill" -> "听完后拼写你听到的单词"
        "speaking_repeat" -> "朗读以下单词，然后自评"
        "open_speaking" -> "用这个词说一句话，然后自评"
        "word_form" -> "写出目标词的正确词形"
        "reading_comprehension" -> "阅读短文，回答问题"
        else -> if (answerForm == "keyboard") "填写正确的单词" else "选择正确的选项"
    }

@Composable
private fun RetryFeedbackPanel(
    retryWrongAnswer: String,
    correctAnswer: String,
    tooManyTypos: Boolean,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer,
        ),
    ) {
        Column(
            Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (tooManyTypos) {
                Text(
                    "相差太多，请重新拼写一遍",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
            } else {
                Text(
                    "出错的字母已高亮，请再试一次",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
                LetterDiff(attempted = retryWrongAnswer, correct = correctAnswer)
            }
        }
    }
}

@Composable
private fun SpellingCorrectionPanel(lastWrongAnswer: String, correctAnswer: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Column(
            Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "✏️ 拼写一遍来加深记忆",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (lastWrongAnswer.isNotBlank()) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        "你的答案",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    LetterDiff(attempted = lastWrongAnswer, correct = correctAnswer)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    "正确拼写",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    correctAnswer,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

@Composable
private fun LetterDiff(attempted: String, correct: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(1.dp)) {
        attempted.forEachIndexed { index, char ->
            val matches = index < correct.length &&
                char.lowercaseChar() == correct[index].lowercaseChar()
            Text(
                char.toString(),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = if (matches) Color(0xFF4CAF50) else MaterialTheme.colorScheme.error,
            )
        }
        // Show remaining correct letters as grey underscores if attempted is shorter
        if (attempted.length < correct.length) {
            repeat(correct.length - attempted.length) {
                Text(
                    "_",
                    style = MaterialTheme.typography.headlineSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                )
            }
        }
    }
}

@Composable
private fun ClozeInput(
    value: String,
    onValueChange: (String) -> Unit,
    onSubmit: () -> Unit,
    enabled: Boolean,
    letterCount: Int?,
    lastWrongAnswer: String,
    feedback: String,
) {
    // Visual letter slots
    if (letterCount != null) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            repeat(letterCount) {
                Text(
                    "_",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Light,
                )
            }
            Text(
                "  ($letterCount 个字母)",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    // Previous wrong attempt
    if (lastWrongAnswer.isNotBlank()) {
        Text(
            "✗  $lastWrongAnswer",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.error,
            fontWeight = FontWeight.SemiBold,
        )
    }
    // Server message (near_meaning, etc.)
    if (feedback.isNotBlank()) {
        Text(
            feedback,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.tertiary,
        )
    }
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
    answerOutcome: String,
) {
    val isFullCorrect = answerOutcome == "full_correct" || answerOutcome == "assisted_correct"
    val isRemediation = answerOutcome == "remediation_completed"
    val labelColor = when {
        isFullCorrect  -> MaterialTheme.colorScheme.primary
        isRemediation  -> MaterialTheme.colorScheme.tertiary
        else           -> MaterialTheme.colorScheme.error
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = "你的答案：$submittedAnswer",
            style = MaterialTheme.typography.bodyMedium,
            color = labelColor,
            fontWeight = FontWeight.SemiBold,
        )
        // Only show correct answer when the user genuinely got it wrong (not remediation)
        if (!isFullCorrect && !isRemediation && correctAnswer.isNotBlank()) {
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
    val isRemediation = answerOutcome == "remediation_completed"
    val bgColor = when {
        isCorrect     -> MaterialTheme.colorScheme.primaryContainer
        isRemediation -> MaterialTheme.colorScheme.tertiaryContainer
        else          -> MaterialTheme.colorScheme.errorContainer
    }
    val textColor = when {
        isCorrect     -> MaterialTheme.colorScheme.onPrimaryContainer
        isRemediation -> MaterialTheme.colorScheme.onTertiaryContainer
        else          -> MaterialTheme.colorScheme.onErrorContainer
    }
    val headline = when (answerOutcome) {
        "full_correct"          -> "✅ 回答正确！"
        "assisted_correct"      -> "✅ 辅助正确"
        "remediation_completed" -> "✅ 拼写正确"
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
