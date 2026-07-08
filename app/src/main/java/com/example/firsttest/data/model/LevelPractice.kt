package com.example.firsttest.data.model

data class LevelPracticeQuestion(
    val questionId: String,
    val senseId: String,
    val position: Int,
    val promptHint: String,
    val stem: String,
    val answerForm: String,        // "option" | "keyboard"; speaking V1 uses option self-check
    val questionTypeKey: String,   // meaning_choice, sentence_cloze_typing, listening_choice, etc.
    val typeCode: Int = 2,
    val expectedTimeMs: Int = 12_000,
    val attemptCount: Int = 0,
    val hintUsed: Boolean = false,
    val letterCount: Int? = null,
    val revealedAnswer: String? = null,
    val translationZh: String,
    val options: List<MeaningChoiceOption>,  // empty for cloze questions
    val audioText: String? = null,
)

data class LevelPracticeRound(
    val roundId: String,
    val levelNumber: Int,
    val questions: List<LevelPracticeQuestion>,
)

data class LevelPracticeAnswerResult(
    val isCorrect: Boolean?,
    val answerOutcome: String,     // "full_correct" | "assisted_correct" | "remediation_completed" | "wrong"
    val correctOptionId: String?,  // non-null for option questions
    val correctAnswer: String?,    // non-null for cloze questions
    val learningState: String?,
    val reviewStage: Int?,
    val action: String = "completed",
    val attemptCount: Int = 0,
    val letterCount: Int? = null,
    val feedback: String = "",
    val revealedAnswer: String? = null,
)
