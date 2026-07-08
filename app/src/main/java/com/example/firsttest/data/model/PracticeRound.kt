package com.example.firsttest.data.model

data class PracticeRound(
    val roundId: String,
    val levelNumber: Int,
    val questions: List<MeaningChoiceQuestion>,
)

data class PracticeAnswerResult(
    val isCorrect: Boolean? = null,
    val correctOptionId: String = "",
    val answerOutcome: String = "",
    val action: String = "completed",
    val attemptCount: Int = 0,
    val letterCount: Int? = null,
    val feedback: String = "",
    val revealedAnswer: String? = null,
)

data class PracticeRoundResult(
    val correctCount: Int,
    val questionCount: Int,
    val starRating: Int,
    val duckPowerEarned: Int,
    val levelCompleted: Boolean,
    val fullCorrectCount: Int = correctCount,
    val assistedCorrectCount: Int = 0,
    val weightedAccuracy: Double = if (questionCount > 0) correctCount.toDouble() / questionCount else 0.0,
)
