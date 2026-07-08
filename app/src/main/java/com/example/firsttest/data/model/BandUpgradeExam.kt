package com.example.firsttest.data.model

data class BandUpgradeExam(
    val attemptId: String,
    val sourceBand: Double,
    val targetBand: Double,
    val status: String,
    val questionCount: Int,
    val correctCount: Int?,
    val accuracy: Double?,
    val passed: Boolean?,
    val categoryCounts: Map<String, Int>,
    val questions: List<BandUpgradeQuestion>,
)

data class BandUpgradeQuestion(
    val position: Int,
    val questionId: String,
    val questionTypeKey: String,
    val category: String,
    val answerForm: String,
    val stem: String,
    val promptHint: String,
    val translationZh: String,
    val headword: String,
    val options: List<MeaningChoiceOption>,
    val answered: Boolean,
    val isCorrect: Boolean?,
)

data class BandUpgradeAnswerResult(
    val alreadySaved: Boolean,
    val position: Int,
    val isCorrect: Boolean?,
)
