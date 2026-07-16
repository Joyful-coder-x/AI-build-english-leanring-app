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
import com.example.firsttest.ui.common.OptionList
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
    var ttsInitAttempt by remember { mutableStateOf(0) }
    var ttsStatusMessage: String? by remember { mutableStateOf("Audio engine loading...") }
    DisposableEffect(context, ttsInitAttempt) {
        lateinit var engine: TextToSpeech
        engine = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val languageResult = engine.setLanguage(Locale.US)
                if (
                    languageResult == TextToSpeech.LANG_MISSING_DATA ||
                    languageResult == TextToSpeech.LANG_NOT_SUPPORTED
                ) {
                    ttsEngine = null
                    ttsStatusMessage = "US English voice data is not available on this device."
                } else {
                    ttsEngine = engine
                    ttsStatusMessage = null
                }
            } else {
                ttsEngine = null
                ttsStatusMessage = "Audio engine is not ready."
            }
        }
        onDispose {
            engine.shutdown()
            ttsEngine = null
        }
    }
    // TTS init is async and occasionally reports non-SUCCESS on first bind;
    // retry a few times after a short delay instead of leaving playback dead
    // for the rest of the session.
    LaunchedEffect(ttsInitAttempt) {
        if (ttsInitAttempt >= 3) return@LaunchedEffect
        kotlinx.coroutines.delay(1500)
        if (ttsEngine == null) ttsInitAttempt++
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
                TopBar(
                    levelNumber = levelNumber,
                    current = state.questionIndex + 1,
                    total = state.totalQuestions,
                    comboCount = state.comboCount,
                    onBack = onBack,
                )
                QuestionCard(
                    question = state.question,
                    tts = ttsEngine,
                    autoSpeak = true,
                    ttsStatusMessage = ttsStatusMessage,
                    onRetryTts = { ttsInitAttempt++ },
                )
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
                    if (state.question.translationZh.isNotBlank()) {
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
                } else {
                    val options = speakingSelfCheckOptions(
                        state.question,
                        hintStage = state.selfCheckHintStage,
                    )
                    OptionList(
                        options = options,
                        selectedId = state.selectedOptionId,
                        reviewingCorrectId = null,
                        reviewingSelectedId = null,
                        onSelect = { optionId ->
                            val selected = options.firstOrNull { it.optionId == optionId }
                            if (state.question.isReadAloudSelfCheck() &&
                                selected?.isDisplayedSelfCheckHint() == true
                            ) {
                                speakReadAloudHint(state.question, ttsEngine)
                            }
                            viewModel.onOptionSelected(optionId)
                        },
                    )
                    if (state.selfCheckHintStage > 0 || state.isHintLoading) {
                        SelfCheckHintPanel(
                            definitionZh = state.selfCheckDefinitionZh,
                            exampleSentence = state.selfCheckExampleSentence,
                            isLoading = state.isHintLoading,
                            hasExample = state.selfCheckHintStage >= 2,
                            isReadAloud = state.question.isReadAloudSelfCheck(),
                        )
                    }
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
                QuestionCard(
                    question = state.question,
                    tts = ttsEngine,
                    ttsStatusMessage = ttsStatusMessage,
                    onRetryTts = { ttsInitAttempt++ },
                )
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
                val reviewListeningText = state.correctOptionId?.let { correctId ->
                    state.question.options.firstOrNull { it.optionId == correctId }?.text
                }
                QuestionCard(
                    question = state.question,
                    tts = ttsEngine,
                    speechTextOverride = reviewListeningText,
                    ttsStatusMessage = ttsStatusMessage,
                    onRetryTts = { ttsInitAttempt++ },
                )
                Spacer(Modifier.height(4.dp))
                if (state.question.answerForm == "keyboard") {
                    ClozeReview(
                        submittedAnswer = state.submittedAnswer,
                        correctAnswer   = state.correctAnswer ?: "",
                        answerOutcome   = state.answerOutcome,
                    )
                } else {
                    OptionList(
                        options = speakingSelfCheckOptions(state.question),
                        selectedId = null,
                        reviewingCorrectId = if (state.question.isSpeakingSelfCheck()) {
                            null
                        } else {
                            state.correctOptionId
                        },
                        reviewingSelectedId = state.submittedAnswer,
                        onSelect = {},
                    )
                }
                Spacer(Modifier.height(4.dp))
                ReviewPanel(
                    answerOutcome = state.answerOutcome,
                    translationZh = state.question.translationZh,
                    isSpeakingSelfCheck = state.question.isSpeakingSelfCheck(),
                    selfCheckHintUsed = state.selfCheckHintUsed,
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

private fun speakingSelfCheckOptions(
    question: LevelPracticeQuestion,
    hintStage: Int = 0,
): List<MeaningChoiceOption> {
    if (!question.isSpeakingSelfCheck()) {
        return question.options
    }

    val hint = question.options.firstOrNull {
        it.text == "I need hint" || it.text == "I need more practice."
    }
    val known = question.options.firstOrNull {
        it.text == "I know how to use" ||
            it.text == "I used it clearly." ||
            it.text == "I know how to read" ||
            it.text == "I know it"
    } ?: question.options.firstOrNull { option ->
        option.isCorrect && option.optionId != hint?.optionId
    }
    val readAloud = question.isReadAloudSelfCheck()

    return listOfNotNull(
        hint?.let {
            it.copy(
                text = when {
                    readAloud && hintStage > 0 -> "\uD83D\uDD0A Hear it again"
                    readAloud -> "\uD83D\uDD0A I need hint"
                    hintStage == 1 -> "I need more hint"
                    else -> it.text
                },
            )
        },
        known?.let {
            it.copy(
                text = if (readAloud) "I know it" else "I know how to use",
            )
        } ?: MeaningChoiceOption(
            optionId = SELF_CHECK_KNOWN_OPTION_ID,
            senseId = question.senseId,
            text = if (readAloud) "I know it" else "I know how to use",
            isCorrect = true,
        ),
    ).ifEmpty { question.options.take(2) }
}

private const val SELF_CHECK_KNOWN_OPTION_ID = "__self_check_known__"

private fun LevelPracticeQuestion.isSpeakingSelfCheck(): Boolean =
    questionTypeKey == "open_speaking" ||
        questionTypeKey == "speaking_repeat" ||
        typeCode == 105 ||
        typeCode == 106 ||
        stem.startsWith("Say one short sentence using:", ignoreCase = true)

private fun LevelPracticeQuestion.isReadAloudSelfCheck(): Boolean =
    questionTypeKey == "speaking_repeat" ||
        typeCode == 105 ||
        stem.startsWith("Say this word aloud:", ignoreCase = true)

private fun MeaningChoiceOption.isDisplayedSelfCheckHint(): Boolean =
    text == "I need hint" ||
        text == "I need more practice." ||
        text == "\uD83D\uDD0A I need hint" ||
        text == "\uD83D\uDD0A Hear it again"

private fun speakReadAloudHint(question: LevelPracticeQuestion, tts: TextToSpeech?) {
    val word = readAloudSpeechText(question) ?: return
    tts?.speak(word, TextToSpeech.QUEUE_FLUSH, null, "${question.questionId}_read_hint")
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
    speechTextOverride: String? = null,
    ttsStatusMessage: String? = null,
    onRetryTts: () -> Unit = {},
) {
    val questionTypeKey = effectiveQuestionTypeKey(question)
    val listeningWord = listeningSpeechText(question, questionTypeKey, speechTextOverride)
    val replayAudio = {
        val speechText = listeningWord
        when {
            speechText == null -> Unit
            tts == null -> onRetryTts()
            else -> tts.speak(
                speechText,
                TextToSpeech.QUEUE_FLUSH,
                null,
                question.questionId + "_replay",
            )
        }
        Unit
    }
    val replayStatusMessage = when {
        questionTypeKey != "listening_choice" && questionTypeKey != "listening_fill" -> null
        listeningWord == null ->
            "Audio target missing. Apply the audio_text migration, then start a new round.\n" +
                "(${listeningWordMissingDetail(question)})"
        tts == null -> ttsStatusMessage ?: "Audio engine loading. Tap replay to retry."
        else -> null
    }

    // Auto-speak when the question first appears. TTS initializes async, so
    // include the engine in the key; otherwise questions shown before TTS is
    // ready never play automatically.
    if (autoSpeak && listeningWord != null && tts != null) {
        LaunchedEffect(question.questionId, listeningWord, tts) {
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
                                enabled = listeningWord != null,
                            ) {
                                Text(if (tts == null) "Retry audio" else "🔊 再听一次")
                            }
                            replayStatusMessage?.let {
                                Text(
                                    it,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onTertiaryContainer.copy(alpha = 0.7f),
                                )
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
                                enabled = listeningWord != null,
                            ) {
                                Text(if (tts == null) "Retry audio" else "🔊 再听一次")
                            }
                            replayStatusMessage?.let {
                                Text(
                                    it,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onTertiaryContainer.copy(alpha = 0.7f),
                                )
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

private fun listeningWordMissingDetail(question: LevelPracticeQuestion): String {
    val hasQuotedWord = Regex("says\\s+\"([^\"]+)\"", RegexOption.IGNORE_CASE).containsMatchIn(question.stem)
    return "qid=${question.questionId} type=${question.questionTypeKey} " +
        "audio_text=${question.audioText ?: "null"} quoted_stem=$hasQuotedWord " +
        "revealed_answer=${question.revealedAnswer ?: "null"} stem_is_single_word=${question.stem.isSingleEnglishWord()}"
}

private fun listeningSpeechText(
    question: LevelPracticeQuestion,
    questionTypeKey: String,
    speechTextOverride: String? = null,
): String? {
    if (questionTypeKey != "listening_choice" && questionTypeKey != "listening_fill") return null

    val quotedWord = Regex("says\\s+\"([^\"]+)\"", RegexOption.IGNORE_CASE)
        .find(question.stem)
        ?.groupValues
        ?.get(1)

    return (
        speechTextOverride
            ?: question.audioText
            ?: quotedWord
            ?: question.revealedAnswer
            ?: question.stem.takeIf { it.isSingleEnglishWord() }
        )?.englishOnly()
}

private fun readAloudSpeechText(question: LevelPracticeQuestion): String? {
    val promptedWord = Regex(
        "(?:say\\s+this\\s+word\\s+aloud|read\\s+this\\s+word|repeat\\s+aloud)\\s*:\\s*([A-Za-z][A-Za-z'-]*)",
        RegexOption.IGNORE_CASE,
    )
        .find(question.stem)
        ?.groupValues
        ?.get(1)

    return (
        question.audioText
            ?: promptedWord
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
private fun SelfCheckHintPanel(
    definitionZh: String,
    exampleSentence: String?,
    isLoading: Boolean,
    hasExample: Boolean,
    isReadAloud: Boolean = false,
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
        ) {
            Text(
                "Hint",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onTertiaryContainer,
            )
            if (definitionZh.isNotBlank()) {
                Text(
                    "Chinese meaning: $definitionZh",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onTertiaryContainer,
                )
            }
            when {
                isLoading -> Text(
                    "Loading example...",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onTertiaryContainer,
                )
                hasExample && !exampleSentence.isNullOrBlank() -> Text(
                    "Example: $exampleSentence",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onTertiaryContainer,
                )
                hasExample -> Text(
                    "No example sentence is available for this word yet.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onTertiaryContainer,
                )
                isReadAloud -> Text(
                    "Tap the speaker hint again to hear the word, or select I know it when ready.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onTertiaryContainer,
                )
                else -> Text(
                    "Select I need hint again for an example, or select I know how to use when ready.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onTertiaryContainer,
                )
            }
        }
    }
}

@Composable
private fun ReviewPanel(
    answerOutcome: String,
    translationZh: String,
    isSpeakingSelfCheck: Boolean = false,
    selfCheckHintUsed: Boolean = false,
) {
    if (isSpeakingSelfCheck) {
        val bgColor = if (selfCheckHintUsed) {
            MaterialTheme.colorScheme.tertiaryContainer
        } else {
            MaterialTheme.colorScheme.surfaceVariant
        }
        val textColor = if (selfCheckHintUsed) {
            MaterialTheme.colorScheme.onTertiaryContainer
        } else {
            MaterialTheme.colorScheme.onSurfaceVariant
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
                    if (selfCheckHintUsed) "Needs more practice" else "Self-check saved",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = textColor,
                )
                Text(
                    if (selfCheckHintUsed) {
                        "You used a hint, so this word should stay in review."
                    } else {
                        "You marked that you can use this word."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = textColor,
                )
                if (translationZh.isNotBlank()) {
                    Text(
                        "Chinese meaning: $translationZh",
                        style = MaterialTheme.typography.bodySmall,
                        color = textColor,
                    )
                }
            }
        }
        return
    }

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
