package com.example.firsttest.data.model

/**
 * One dynamically-built Meaning Choice question.
 *
 * Questions are generated at runtime from word_senses + level_sense_assignments
 * (not pre-stored in the questions table), so [questionId] is a locally-created
 * UUID and has no FK in Supabase.
 *
 * [options] always contains exactly 4 entries (1 correct + 3 distractors),
 * already shuffled into display order.
 */
data class MeaningChoiceQuestion(
    val questionId: String,
    val levelNumber: Int,
    val senseId: String,
    val position: Int = 0,
    val promptHint: String = "",
    val stem: String = "",
    val wordText: String,
    val partOfSpeech: String,
    val definitionZh: String,
    val options: List<MeaningChoiceOption>,
    val correctOptionId: String = "",
    val typeCode: Int = 2,
    val questionTypeKey: String = "option_recognition",
    val answerForm: String = "option",
    val expectedTimeMs: Int = 12_000,
    val attemptCount: Int = 0,
    val hintUsed: Boolean = false,
    val nearMeaningFeedback: String = "",
    val revealedAnswer: String? = null,
)
