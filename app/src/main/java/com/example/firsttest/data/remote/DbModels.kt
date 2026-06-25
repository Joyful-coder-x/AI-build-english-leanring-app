package com.example.firsttest.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

// ---- Vocabulary content (word_senses / level_sense_assignments / words / levels) ----

@Serializable
data class DbLevel(
    @SerialName("level_number") val levelNumber: Int,
    @SerialName("band_id") val bandId: Int,
    val title: String,
)

@Serializable
data class DbLevelProgress(
    @SerialName("level_number") val levelNumber: Int,
    @SerialName("is_unlocked") val isUnlocked: Boolean,
    @SerialName("is_completed") val isCompleted: Boolean,
    val progress: Double,
    @SerialName("best_star_rating") val bestStarRating: Int,
    @SerialName("completed_session_count") val completedSessionCount: Int,
)

/**
 * Row from level_sense_assignments with word_senses and words joined inline.
 * Select string: "sense_id, level_number, word_senses(id, part_of_speech,
 *   definition_en, definition_zh, word_id, words(id, headword))"
 */
@Serializable
data class DbLevelSenseRow(
    @SerialName("sense_id") val senseId: String,
    @SerialName("level_number") val levelNumber: Int,
    @SerialName("word_senses") val sense: DbSenseWithWord,
)

@Serializable
data class DbSenseWithWord(
    val id: String,
    @SerialName("part_of_speech") val partOfSpeech: String,
    @SerialName("definition_en") val definitionEn: String,
    @SerialName("definition_zh") val definitionZh: String,
    @SerialName("word_id") val wordId: String,
    val words: DbWordHeadword,
)

@Serializable
data class DbWordHeadword(
    val id: String,
    val headword: String,
)

@Serializable
data class DbProfile(
    val id: String,
    @SerialName("public_user_code") val publicUserCode: String,
    val username: String,
    val nickname: String,
    @SerialName("avatar_path") val avatarPath: String? = null,
    @SerialName("duck_power") val duckPower: Int,
    @SerialName("current_streak_days") val currentStreakDays: Int = 0,
    @SerialName("longest_streak_days") val longestStreakDays: Int = 0,
    @SerialName("last_practice_date") val lastPracticeDate: String? = null,
    @SerialName("onboarding_status") val onboardingStatus: String,
)

@Serializable
data class DbUserBootstrapState(
    val profile: DbProfile,
    @SerialName("flow_state") val flowState: String,
    @SerialName("current_question_index") val currentQuestionIndex: Int,
    @SerialName("onboarding_answers") val onboardingAnswers: JsonObject,
    @SerialName("placement_status") val placementStatus: String,
    @SerialName("current_level") val currentLevel: Int? = null,
    @SerialName("highest_unlocked_level") val highestUnlockedLevel: Int? = null,
)

@Serializable
data class FinalizePlacementParams(
    @SerialName("p_ielts_band") val ieltsBand: Float,
    @SerialName("p_skip") val skip: Boolean = false,
)

@Serializable
data class SaveOnboardingAnswerParams(
    @SerialName("requested_questionnaire_version") val questionnaireVersion: String,
    @SerialName("requested_answer_key") val answerKey: String,
    @SerialName("requested_answer_value") val answerValue: String,
    @SerialName("requested_expected_question_index") val expectedQuestionIndex: Int,
)

// ---- RPC parameter payloads (Meaning Choice answer persistence) ---------------

@Serializable
data class DbSaveMeaningChoiceAnswerParams(
    @SerialName("p_level_number")      val levelNumber: Int,
    @SerialName("p_sense_id")          val senseId: String,
    @SerialName("p_selected_sense_id") val selectedSenseId: String,
    @SerialName("p_is_correct")        val isCorrect: Boolean,
    @SerialName("p_response_time_ms")  val responseTimeMs: Int,
)

@Serializable
data class DbCompleteMeaningChoiceSessionParams(
    @SerialName("p_level_number")      val levelNumber: Int,
    @SerialName("p_correct_count")     val correctCount: Int,
    @SerialName("p_total_count")       val totalCount: Int,
    @SerialName("p_star_rating")       val starRating: Int,
    @SerialName("p_duck_power_earned") val duckPowerEarned: Int,
)

@Serializable
data class DbStartPracticeRoundParams(
    @SerialName("p_level_number") val levelNumber: Int,
)

@Serializable
data class DbPracticeRoundOption(
    @SerialName("option_id") val optionId: String,
    @SerialName("option_text") val optionText: String,
)

@Serializable
data class DbPracticeRoundQuestion(
    val position: Int,
    @SerialName("question_id") val questionId: String,
    @SerialName("sense_id") val senseId: String,
    val stem: String,
    @SerialName("prompt_hint") val promptHint: String,
    @SerialName("translation_zh") val translationZh: String,
    @SerialName("question_skill") val questionSkill: String,
    val options: List<DbPracticeRoundOption> = emptyList(),
    @SerialName("type_code") val typeCode: Int = 2,
    @SerialName("question_type_key") val questionTypeKey: String = "option_recognition",
    @SerialName("answer_form") val answerForm: String = "option",
    @SerialName("expected_time_ms") val expectedTimeMs: Int = 12_000,
    @SerialName("attempt_count") val attemptCount: Int = 0,
    @SerialName("hint_used") val hintUsed: Boolean = false,
    @SerialName("letter_count") val letterCount: Int? = null,
    @SerialName("revealed_answer") val revealedAnswer: String? = null,
    @SerialName("answer_given") val answerGiven: String? = null,
    @SerialName("is_answered") val isAnswered: Boolean = false,
)

@Serializable
data class DbPracticeRound(
    @SerialName("round_id") val roundId: String,
    @SerialName("level_number") val levelNumber: Int,
    val status: String,
    @SerialName("question_count") val questionCount: Int,
    @SerialName("new_sense_count") val newSenseCount: Int,
    @SerialName("review_sense_count") val reviewSenseCount: Int,
    val questions: List<DbPracticeRoundQuestion>,
)

@Serializable
data class DbSavePracticeAnswerParams(
    @SerialName("p_round_id") val roundId: String,
    @SerialName("p_position") val position: Int,
    @SerialName("p_answer") val answer: String,
    @SerialName("p_response_time_ms") val responseTimeMs: Int,
)

@Serializable
data class DbPracticeAnswerResult(
    val position: Int,
    @SerialName("answer_outcome") val answerOutcome: String? = null,
    @SerialName("is_correct") val isCorrect: Boolean? = null,
    @SerialName("correct_option_id") val correctOptionId: String? = null,
    @SerialName("already_saved") val alreadySaved: Boolean = false,
    val action: String = "completed",
    @SerialName("attempt_count") val attemptCount: Int = 0,
    @SerialName("letter_count") val letterCount: Int? = null,
    val feedback: String? = null,
    @SerialName("revealed_answer") val revealedAnswer: String? = null,
    @SerialName("correct_answer") val correctAnswer: String? = null,
    @SerialName("learning_state") val learningState: String? = null,
    @SerialName("review_stage") val reviewStage: Int? = null,
    @SerialName("next_due_at") val nextDueAt: String? = null,
)

@Serializable
data class DbCompletePracticeRoundParams(
    @SerialName("p_round_id") val roundId: String,
)

@Serializable
data class DbGetLevelWordStatusesParams(
    @SerialName("p_level_number") val levelNumber: Int,
)

@Serializable
data class DbLevelWordStatus(
    @SerialName("sense_id") val senseId: String,
    val word: String,
    @SerialName("definition_zh") val definitionZh: String,
    val status: String,
    @SerialName("wrong_count") val wrongCount: Int,
    @SerialName("is_due") val isDue: Boolean,
)

@Serializable
data class DbPracticeRoundResult(
    @SerialName("round_id") val roundId: String,
    @SerialName("full_correct_count") val fullCorrectCount: Int = 0,
    @SerialName("assisted_correct_count") val assistedCorrectCount: Int = 0,
    @SerialName("remediation_count") val remediationCount: Int = 0,
    @SerialName("wrong_count") val wrongCount: Int = 0,
    @SerialName("weighted_accuracy") val weightedAccuracy: Double = 0.0,
    @SerialName("star_rating") val starRating: Int,
    @SerialName("duck_power_earned") val duckPowerEarned: Int,
    @SerialName("already_completed") val alreadyCompleted: Boolean,
    @SerialName("level_completed") val levelCompleted: Boolean? = false,
    // Legacy fields kept for backward compat with old completed rounds.
    @SerialName("correct_count") val correctCount: Int = 0,
    @SerialName("question_count") val questionCount: Int = 0,
)

/**
 * Row shape for `public.questions` (docs/architecture/DATA_MODEL_AND_CAPACITY.md §4.6).
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
)

/**
 * Row shape for `public.question_options` (docs/architecture/DATA_MODEL_AND_CAPACITY.md §4.6).
 * Used to build the option list for MCQ questions (type_code = 2).
 */
@Serializable
data class DbQuestionOption(
    @SerialName("question_id") val questionId: String,
    @SerialName("option_text") val optionText: String,
    @SerialName("is_correct")  val isCorrect: Boolean,
    @SerialName("sort_order")  val sortOrder: Int,
)

// ---- Mistake words (mistake_senses + word_senses + user_sense_mastery) ---------

/**
 * Row from mistake_senses with nested word_senses→words join.
 * Select: "sense_id, wrong_count, first_wrong_at, last_wrong_at,
 *           word_senses(definition_zh, part_of_speech, words(headword))"
 */
@Serializable
data class DbMistakeSense(
    @SerialName("sense_id")       val senseId: String,
    @SerialName("wrong_count")    val wrongCount: Int,
    @SerialName("first_wrong_at") val firstWrongAt: String,
    @SerialName("last_wrong_at")  val lastWrongAt: String,
    @SerialName("word_senses")    val sense: DbMistakeSenseDetail,
)

@Serializable
data class DbMistakeSenseDetail(
    @SerialName("definition_zh")  val definitionZh: String,
    @SerialName("part_of_speech") val partOfSpeech: String,
    val words: DbMistakeWord,
)

@Serializable
data class DbMistakeWord(
    val headword: String,
)

/** Row from user_sense_mastery — just the scheduling fields. */
@Serializable
data class DbSenseMastery(
    @SerialName("sense_id")    val senseId: String,
    @SerialName("review_stage") val reviewStage: Int = 0,
    @SerialName("next_due_at") val nextDueAt: String? = null,
)

/** Single level_number from user_level_progress (for highest-unlocked query). */
@Serializable
data class DbLevelNumber(
    @SerialName("level_number") val levelNumber: Int,
    val progress: Double = 0.0,
)
