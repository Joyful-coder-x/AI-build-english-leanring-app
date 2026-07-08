package com.example.firsttest.data.model

/** Home-page 100-question diagnostic (masterplan Feature H). Purely informational. */
data class OverallAssessment(
    val attemptId: String,
    val status: String,
    val questionCount: Int,
    val correctCount: Int?,
    val listeningCorrect: Int?,
    val listeningTotal: Int?,
    val readingCorrect: Int?,
    val readingTotal: Int?,
    val speakingCorrect: Int?,
    val speakingTotal: Int?,
    val spellingCorrect: Int?,
    val spellingTotal: Int?,
    val listeningBand: Double?,
    val readingBand: Double?,
    val speakingBand: Double?,
    val spellingBand: Double?,
    val overallBand: Double?,
    val questions: List<OverallAssessmentQuestion>,
)

data class OverallAssessmentQuestion(
    val position: Int,
    val questionId: String,
    val questionTypeKey: String,
    val skillCategory: String,
    val answerForm: String,
    val stem: String,
    val promptHint: String,
    val translationZh: String,
    val headword: String,
    val options: List<MeaningChoiceOption>,
    val answered: Boolean,
    val isCorrect: Boolean?,
)

data class OverallAssessmentAnswerResult(
    val alreadySaved: Boolean,
    val position: Int,
    val isCorrect: Boolean?,
)
