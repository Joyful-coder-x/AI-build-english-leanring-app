package com.example.firsttest.ui.home

import android.speech.tts.TextToSpeech
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.model.BandUpgradeExam
import com.example.firsttest.data.model.BandUpgradeQuestion
import com.example.firsttest.ui.common.OptionList
import java.util.Locale

@Composable
fun BandUpgradeExamScreen(
    targetBand: Double,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: BandUpgradeExamViewModel = viewModel(
        key = "band_upgrade_$targetBand",
        factory = BandUpgradeExamViewModel.factory(targetBand),
    ),
) {
    val uiState by viewModel.uiState.collectAsState()
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
    // for the rest of the exam.
    LaunchedEffect(ttsInitAttempt) {
        if (ttsInitAttempt >= 3) return@LaunchedEffect
        kotlinx.coroutines.delay(1500)
        if (ttsEngine == null) ttsInitAttempt++
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        when (val state = uiState) {
            BandUpgradeExamUiState.Loading -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }

            is BandUpgradeExamUiState.Error -> {
                BandExamHeader(targetBand = targetBand, onBack = onBack)
                Text(
                    text = state.message,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
                Button(onClick = viewModel::retry, modifier = Modifier.fillMaxWidth()) {
                    Text("Retry")
                }
            }

            is BandUpgradeExamUiState.Answering -> {
                BandExamHeader(targetBand = state.exam.targetBand, onBack = onBack)
                LinearProgressIndicator(
                    progress = (state.questionIndex + 1).toFloat() / state.exam.questions.size.toFloat(),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    text = "Question ${state.questionIndex + 1} / ${state.exam.questions.size}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                BandExamQuestionCard(
                    question = state.question,
                    tts = ttsEngine,
                    autoSpeak = true,
                    ttsStatusMessage = ttsStatusMessage,
                    onRetryTts = { ttsInitAttempt++ },
                )
                if (state.question.answerForm == "keyboard") {
                    OutlinedTextField(
                        value = state.typedAnswer,
                        onValueChange = viewModel::onTypedAnswerChanged,
                        label = { Text("Type your answer") },
                        singleLine = true,
                        enabled = !state.isSubmitting,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(
                            onDone = { if (state.submitEnabled) viewModel.onSubmit() },
                        ),
                        modifier = Modifier.fillMaxWidth(),
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
                Button(
                    onClick = viewModel::onSubmit,
                    enabled = state.submitEnabled,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(if (state.questionIndex + 1 == state.exam.questions.size) "Finish exam" else "Next")
                }
            }

            is BandUpgradeExamUiState.Result -> {
                BandExamHeader(targetBand = state.exam.targetBand, onBack = onBack)
                BandExamResultCard(exam = state.exam)
                Button(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
                    Text("Return to learning path")
                }
            }
        }
    }
}

@Composable
private fun BandExamHeader(targetBand: Double, onBack: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TextButton(onClick = onBack) { Text("Back") }
        Spacer(Modifier.weight(1f))
        Text(
            text = "IELTS ${formatBandScore(targetBand)} Upgrade Exam",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
        )
    }
}

@Composable
private fun BandExamQuestionCard(
    question: BandUpgradeQuestion,
    tts: TextToSpeech?,
    autoSpeak: Boolean,
    ttsStatusMessage: String? = null,
    onRetryTts: () -> Unit = {},
) {
    val isListening = question.questionTypeKey == "listening_choice"
    val speechText = question.headword.ifBlank { question.stem }.englishOnly()
    val replayAudio = {
        when {
            speechText == null -> Unit
            tts == null -> onRetryTts()
            else -> tts.speak(speechText, TextToSpeech.QUEUE_FLUSH, null, "${question.questionId}_replay")
        }
        Unit
    }

    // TTS initializes async, so include the engine in the key; otherwise
    // questions shown before TTS is ready never play automatically.
    if (isListening && autoSpeak && speechText != null && tts != null) {
        LaunchedEffect(question.questionId, speechText, tts) {
            tts.speak(speechText, TextToSpeech.QUEUE_FLUSH, null, question.questionId)
        }
    }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                text = question.category.replaceFirstChar { it.uppercase() },
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = question.promptHint.ifBlank { defaultPrompt(question) },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            when (question.questionTypeKey) {
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
                                enabled = speechText != null,
                            ) {
                                Text(if (tts == null) "Retry audio" else "🔊 再听一次")
                            }
                            if (tts == null) {
                                Text(
                                    ttsStatusMessage ?: "Audio engine loading. Tap replay to retry.",
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
                                text = visibleStem(question),
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSecondaryContainer,
                            )
                        }
                    }
                }

                else -> {
                    Text(
                        text = visibleStem(question),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }

            // Only sentence_cloze_typing gets the translation as a hint: its
            // stem is a sentence with the word blanked out, which is often
            // not enough context alone. The other types either state the
            // word directly (meaning_choice) or are answered by ear
            // (listening_choice) / by mouth (speaking_repeat).
            if (question.questionTypeKey == "sentence_cloze_typing" &&
                question.translationZh.isNotBlank()
            ) {
                Text(
                    text = question.translationZh,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun BandExamResultCard(exam: BandUpgradeExam) {
    val correct = exam.correctCount ?: 0
    val accuracy = exam.accuracy ?: 0.0
    val passed = exam.passed == true
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (passed) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.errorContainer
            },
        ),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                text = if (passed) "Passed" else "Keep practicing",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Text("Score: $correct / ${exam.questionCount}")
            Text("Accuracy: ${"%.1f".format(accuracy)}%")
            Text("Passing rule: 37 / 40 or higher")
            if (exam.categoryCounts.isNotEmpty()) {
                Text(
                    text = exam.categoryCounts.entries
                        .sortedBy { it.key }
                        .joinToString("  ") { "${it.key}: ${it.value}" },
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Text(
                text = "This exam controls app progression only. It is not an official IELTS score.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

private fun defaultPrompt(question: BandUpgradeQuestion): String = when (question.questionTypeKey) {
    "meaning_choice" -> "Choose the word that matches the meaning."
    "listening_choice" -> "Listen and choose the word you heard."
    "sentence_cloze_typing" -> "Type the English word for the meaning."
    "speaking_repeat" -> "Read the word aloud, then self-check."
    else -> "Answer the question."
}

// listening_choice never reaches this: it has its own card branch above that
// doesn't show the raw stem, since it would leak the answer as text.
private fun visibleStem(question: BandUpgradeQuestion): String =
    question.stem.ifBlank { question.headword }

private fun String.englishOnly(): String? =
    replace(Regex("[^\\x00-\\x7F]+"), " ")
        .replace(Regex("\\s+"), " ")
        .trim()
        .takeIf { it.isNotBlank() }
