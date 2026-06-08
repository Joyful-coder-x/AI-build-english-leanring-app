package com.example.firsttest.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Row shape for `public.questions` (DATA_DESIGN.md §4.6).
 * Only the columns needed by Phase 2 are mapped; extra DB columns are ignored.
 */
@Serializable
data class DbQuestion(
    val id: String,
    @SerialName("type_code")      val typeCode: Int,
    @SerialName("prompt_hint")    val promptHint: String,
    val stem: String,
    @SerialName("correct_answer") val correctAnswer: String,
    @SerialName("translation_zh") val translationZh: String,
    @SerialName("expected_time_ms") val expectedTimeMs: Int,
    @SerialName("is_active")      val isActive: Boolean,
)

/**
 * Row shape for `public.question_options` (DATA_DESIGN.md §4.6).
 * Used to build the option list for MCQ questions (type_code = 2).
 */
@Serializable
data class DbQuestionOption(
    @SerialName("question_id") val questionId: String,
    @SerialName("option_text") val optionText: String,
    @SerialName("is_correct")  val isCorrect: Boolean,
    @SerialName("sort_order")  val sortOrder: Int,
)
