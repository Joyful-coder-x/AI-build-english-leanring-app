package com.example.firsttest.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.repository.UserBootstrapState
import com.example.firsttest.di.AppRepositories

@Composable
fun OnboardingScreen(
    bootstrap: UserBootstrapState,
    onCompleted: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: OnboardingViewModel = viewModel(
        key = "onboarding-${bootstrap.currentQuestionIndex}",
        factory = OnboardingViewModel.factory(AppRepositories.onboarding, bootstrap),
    ),
) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(uiState) {
        if (uiState == OnboardingUiState.Completed) {
            onCompleted()
        }
    }

    when (val state = uiState) {
        is OnboardingUiState.Question -> QuestionPage(
            state = state,
            onAnswer = viewModel::onAnswer,
            onRetry = viewModel::retry,
            modifier = modifier,
        )
        OnboardingUiState.Completed -> {
            Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
    }
}

@Composable
private fun QuestionPage(
    state: OnboardingUiState.Question,
    onAnswer: (OnboardingOption) -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val currentQuestion = ONBOARDING_QUESTIONS[state.currentIndex]
    val scrollState = rememberScrollState()

    LaunchedEffect(state.currentIndex) {
        scrollState.animateScrollTo(scrollState.maxValue)
    }

    Column(modifier = modifier.fillMaxSize()) {
        LinearProgressIndicator(
            progress = { (state.currentIndex + 1f) / ONBOARDING_QUESTIONS.size },
            modifier = Modifier.fillMaxWidth(),
        )
        Text(
            text = "${state.currentIndex + 1} / ${ONBOARDING_QUESTIONS.size}",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        )

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(scrollState)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "IELTS readiness setup",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
            ONBOARDING_QUESTIONS.take(state.currentIndex).forEach { question ->
                val savedValue = state.answers[question.key] ?: return@forEach
                AppBubble(question.text)
                UserBubble(question.options.firstOrNull { it.value == savedValue }?.label ?: savedValue)
            }
            AppBubble(currentQuestion.text)
            Spacer(Modifier.height(8.dp))
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            state.errorMessage?.let { message ->
                Text(
                    text = message,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
                TextButton(onClick = onRetry, enabled = !state.isSaving) {
                    Text("Retry")
                }
            }
            currentQuestion.options.forEach { option ->
                OutlinedButton(
                    onClick = { onAnswer(option) },
                    enabled = !state.isSaving,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(option.label)
                }
            }
            if (state.isSaving) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator()
                    Text("Saving...", modifier = Modifier.padding(start = 12.dp))
                }
            }
        }
    }
}

@Composable
private fun AppBubble(text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start,
        verticalAlignment = Alignment.Top,
    ) {
        Text("App", style = MaterialTheme.typography.titleMedium)
        Box(
            modifier = Modifier
                .padding(start = 8.dp)
                .widthIn(max = 280.dp)
                .background(
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    shape = RoundedCornerShape(4.dp, 8.dp, 8.dp, 8.dp),
                )
                .padding(12.dp),
        ) {
            Text(text, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun UserBubble(text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
    ) {
        Box(
            modifier = Modifier
                .widthIn(max = 240.dp)
                .background(
                    color = MaterialTheme.colorScheme.primary,
                    shape = RoundedCornerShape(8.dp, 4.dp, 8.dp, 8.dp),
                )
                .padding(12.dp),
        ) {
            Text(
                text = text,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onPrimary,
            )
        }
    }
}
