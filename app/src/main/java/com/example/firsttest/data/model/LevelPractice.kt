package com.example.firsttest.data.model

data class LevelPracticeQuestion(
    val questionId: String,
    val senseId: String,
    val position: Int,
    val promptHint: String,
    val stem: String,
    val answerForm: String,        // "option" | "keyboard"
    val questionTypeKey: String,   // "option_recognition" | "sentence_cloze_typing"
    val translationZh: String,
    val options: List<MeaningChoiceOption>,  // empty for cloze questions
)

data class LevelPracticeRound(
    val roundId: String,
    val levelNumber: Int,
    val questions: List<LevelPracticeQuestion>,
)

data class LevelPracticeAnswerResult(
    val isCorrect: Boolean,
    val answerOutcome: String,     // "full_correct" | "assisted_correct" | "remediation_completed" | "wrong"
    val correctOptionId: String?,  // non-null for option questions
    val correctAnswer: String?,    // non-null for cloze questions
    val learningState: String?,
    val reviewStage: Int?,
)
