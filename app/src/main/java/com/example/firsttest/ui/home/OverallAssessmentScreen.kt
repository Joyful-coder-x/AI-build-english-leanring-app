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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.model.MeaningChoiceOption
import com.example.firsttest.data.model.OverallAssessment
import com.example.firsttest.data.model.OverallAssessmentQuestion
import java.util.Locale

@Composable
fun OverallAssessmentScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: OverallAssessmentViewModel = viewModel(factory = OverallAssessmentViewModel.Factory),
) {
    val uiState by viewModel.uiState.collectAsState()
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

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        when (val state = uiState) {
            OverallAssessmentUiState.Confirm -> {
                AssessmentHeader(onBack = onBack)
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(
                            text = "总体评测",
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                        )
                        Text("本评测共100题，约需20-25分钟，请确保有充足时间。")
                        Text(
                            "题目将从听力、阅读、口语、拼写四个方面各抽取25题，" +
                                "帮助你了解当前的词汇水平。评测结果不影响关卡进度和连胜。",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                Button(onClick = viewModel::start, modifier = Modifier.fillMaxWidth()) {
                    Text("开始评测")
                }
            }

            OverallAssessmentUiState.Loading -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }

            is OverallAssessmentUiState.Error -> {
                AssessmentHeader(onBack = onBack)
                Text(
                    text = state.message,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
                Button(onClick = viewModel::retry, modifier = Modifier.fillMaxWidth()) {
                    Text("Retry")
                }
            }

            is OverallAssessmentUiState.Answering -> {
                AssessmentHeader(onBack = onBack)
                LinearProgressIndicator(
                    progress = (state.questionIndex + 1).toFloat() / state.assessment.questions.size.toFloat(),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    text = "第 ${state.questionIndex + 1} / ${state.assessment.questions.size} 题",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                AssessmentQuestionCard(question = state.question, tts = ttsEngine, autoSpeak = true)
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
                    AssessmentOptionList(
                        options = state.question.options,
                        selectedId = state.selectedOptionId,
                        onSelect = viewModel::onOptionSelected,
                    )
                }
                Button(
                    onClick = viewModel::onSubmit,
                    enabled = state.submitEnabled,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(if (state.questionIndex + 1 == state.assessment.questions.size) "完成评测" else "下一题")
                }
            }

            is OverallAssessmentUiState.Result -> {
                AssessmentHeader(onBack = onBack)
                AssessmentResultCard(assessment = state.assessment)
                Button(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
                    Text("返回首页")
                }
            }
        }
    }
}

@Composable
private fun AssessmentHeader(onBack: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TextButton(onClick = onBack) { Text("‹ 返回") }
        Spacer(Modifier.weight(1f))
        Text(
            text = "总体评测",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
        )
    }
}

@Composable
private fun AssessmentQuestionCard(
    question: OverallAssessmentQuestion,
    tts: TextToSpeech?,
    autoSpeak: Boolean,
) {
    val isListening = question.questionTypeKey == "listening_choice" || question.questionTypeKey == "listening_fill"
    val speechText = question.headword.ifBlank { question.stem }.englishOnly()

    if (isListening && autoSpeak && speechText != null && tts != null) {
        LaunchedEffect(question.questionId) {
            tts.speak(speechText, TextToSpeech.QUEUE_FLUSH, null, question.questionId)
        }
    }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                text = skillLabel(question.skillCategory),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = question.promptHint.ifBlank { "Answer the question." },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (isListening) {
                OutlinedButton(
                    onClick = {
                        if (speechText != null && tts != null) {
                            tts.speak(speechText, TextToSpeech.QUEUE_FLUSH, null, "${question.questionId}_replay")
                        }
                    },
                    enabled = speechText != null && tts != null,
                ) {
                    Text("🔊 再听一次")
                }
            } else {
                Text(
                    text = question.stem.ifBlank { question.headword },
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                )
            }
            if (question.translationZh.isNotBlank()) {
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
private fun AssessmentOptionList(
    options: List<MeaningChoiceOption>,
    selectedId: String?,
    onSelect: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { option ->
            OutlinedButton(
                onClick = { onSelect(option.optionId) },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = if (option.optionId == selectedId) "> ${option.text}" else option.text,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun AssessmentResultCard(assessment: OverallAssessment) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                text = "总体评测结果",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            SkillResultRow("听力", assessment.listeningCorrect, assessment.listeningTotal, assessment.listeningBand)
            SkillResultRow("阅读", assessment.readingCorrect, assessment.readingTotal, assessment.readingBand)
            SkillResultRow("口语", assessment.speakingCorrect, assessment.speakingTotal, assessment.speakingBand)
            SkillResultRow("拼写", assessment.spellingCorrect, assessment.spellingTotal, assessment.spellingBand)
            Text(
                text = "综合估算：雅思 ${assessment.overallBand?.let { "%.1f".format(it) } ?: "N/A"} 分词汇水平",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = "注意：这是基于词汇练习的参考估算，不等同于官方雅思成绩。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SkillResultRow(label: String, correct: Int?, total: Int?, band: Double?) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodyLarge)
        Text(
            text = if (total != null && total > 0) {
                "${correct ?: 0}/$total  ≈ 雅思 ${band?.let { "%.1f".format(it) } ?: "N/A"} 分"
            } else {
                "N/A"
            },
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun skillLabel(skillCategory: String): String = when (skillCategory) {
    "listening" -> "听力 Listening"
    "reading" -> "阅读 Reading"
    "speaking" -> "口语 Speaking"
    "spelling" -> "拼写 Spelling"
    else -> skillCategory.replaceFirstChar { it.uppercase() }
}

private fun String.englishOnly(): String? =
    replace(Regex("[^\\x00-\\x7F]+"), " ")
        .replace(Regex("\\s+"), " ")
        .trim()
        .takeIf { it.isNotBlank() }
