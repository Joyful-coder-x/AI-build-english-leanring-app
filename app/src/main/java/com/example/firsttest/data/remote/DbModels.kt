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
    @SerialName("is_coming_soon") val isComingSoon: Boolean = false,
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
    @SerialName("question_type_key") val questionTypeKey: String? = null,
    @SerialName("answer_form") val answerForm: String? = null,
    @SerialName("expected_time_ms") val expectedTimeMs: Int = 12_000,
    @SerialName("attempt_count") val attemptCount: Int = 0,
    @SerialName("hint_used") val hintUsed: Boolean = false,
    @SerialName("letter_count") val letterCount: Int? = null,
    @SerialName("revealed_answer") val revealedAnswer: String? = null,
    @SerialName("audio_text") val audioText: String? = null,
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
data class DbSenseHintRow(
    @SerialName("definition_zh") val definitionZh: String,
)

@Serializable
data class DbExampleHintRow(
    @SerialName("sentence_en") val sentenceEn: String,
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

@Serializable
data class DbStartBandUpgradeExamParams(
    @SerialName("p_target_band") val targetBand: Double,
)

@Serializable
data class DbSaveBandUpgradeAnswerParams(
    @SerialName("p_attempt_id") val attemptId: String,
    @SerialName("p_position") val position: Int,
    @SerialName("p_answer") val answer: String,
    @SerialName("p_response_time_ms") val responseTimeMs: Int,
)

@Serializable
data class DbCompleteBandUpgradeExamParams(
    @SerialName("p_attempt_id") val attemptId: String,
)

@Serializable
data class DbBandUpgradeOption(
    val id: String,
    val text: String,
    @SerialName("sort_order") val sortOrder: Int = 0,
)

@Serializable
data class DbBandUpgradeQuestion(
    val position: Int,
    @SerialName("question_id") val questionId: String,
    @SerialName("question_type_key") val questionTypeKey: String,
    val category: String,
    @SerialName("answer_form") val answerForm: String,
    val stem: String? = null,
    @SerialName("prompt_hint") val promptHint: String? = null,
    @SerialName("translation_zh") val translationZh: String? = null,
    val headword: String? = null,
    val options: List<DbBandUpgradeOption> = emptyList(),
    val answered: Boolean = false,
    @SerialName("is_correct") val isCorrect: Boolean? = null,
)

@Serializable
data class DbBandUpgradeExam(
    @SerialName("attempt_id") val attemptId: String,
    @SerialName("source_band") val sourceBand: Double,
    @SerialName("target_band") val targetBand: Double,
    val status: String,
    @SerialName("question_count") val questionCount: Int,
    @SerialName("correct_count") val correctCount: Int? = null,
    val accuracy: Double? = null,
    val passed: Boolean? = null,
    @SerialName("category_counts") val categoryCounts: Map<String, Int> = emptyMap(),
    val questions: List<DbBandUpgradeQuestion> = emptyList(),
)

@Serializable
data class DbBandUpgradeAnswerResult(
    @SerialName("already_saved") val alreadySaved: Boolean = false,
    val position: Int,
    @SerialName("is_correct") val isCorrect: Boolean? = null,
)

@Serializable
data class DbSaveOverallAssessmentAnswerParams(
    @SerialName("p_attempt_id") val attemptId: String,
    @SerialName("p_position") val position: Int,
    @SerialName("p_answer") val answer: String,
    @SerialName("p_response_time_ms") val responseTimeMs: Int,
)

@Serializable
data class DbCompleteOverallAssessmentParams(
    @SerialName("p_attempt_id") val attemptId: String,
)

@Serializable
data class DbOverallAssessmentOption(
    val id: String,
    val text: String,
    @SerialName("sort_order") val sortOrder: Int = 0,
)

@Serializable
data class DbOverallAssessmentQuestion(
    val position: Int,
    @SerialName("question_id") val questionId: String,
    @SerialName("question_type_key") val questionTypeKey: String,
    @SerialName("skill_category") val skillCategory: String,
    @SerialName("answer_form") val answerForm: String,
    val stem: String? = null,
    @SerialName("prompt_hint") val promptHint: String? = null,
    @SerialName("translation_zh") val translationZh: String? = null,
    val headword: String? = null,
    val options: List<DbOverallAssessmentOption> = emptyList(),
    val answered: Boolean = false,
    @SerialName("is_correct") val isCorrect: Boolean? = null,
)

@Serializable
data class DbOverallAssessmentAttempt(
    @SerialName("attempt_id") val attemptId: String,
    val status: String,
    @SerialName("question_count") val questionCount: Int,
    @SerialName("correct_count") val correctCount: Int? = null,
    @SerialName("listening_correct") val listeningCorrect: Int? = null,
    @SerialName("listening_total") val listeningTotal: Int? = null,
    @SerialName("reading_correct") val readingCorrect: Int? = null,
    @SerialName("reading_total") val readingTotal: Int? = null,
    @SerialName("speaking_correct") val speakingCorrect: Int? = null,
    @SerialName("speaking_total") val speakingTotal: Int? = null,
    @SerialName("spelling_correct") val spellingCorrect: Int? = null,
    @SerialName("spelling_total") val spellingTotal: Int? = null,
    @SerialName("listening_band") val listeningBand: Double? = null,
    @SerialName("reading_band") val readingBand: Double? = null,
    @SerialName("speaking_band") val speakingBand: Double? = null,
    @SerialName("spelling_band") val spellingBand: Double? = null,
    @SerialName("overall_band") val overallBand: Double? = null,
    val questions: List<DbOverallAssessmentQuestion> = emptyList(),
)

@Serializable
data class DbOverallAssessmentAnswerResult(
    @SerialName("already_saved") val alreadySaved: Boolean = false,
    val position: Int,
    @SerialName("is_correct") val isCorrect: Boolean? = null,
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

@Serializable
data class DbPronunciationRow(
    @SerialName("sense_id") val senseId: String? = null,
    @SerialName("word_id") val wordId: String? = null,
    @SerialName("ipa_us") val ipaUs: String,
)

/** Single level_number from user_level_progress (for highest-unlocked query). */
@Serializable
data class DbLevelNumber(
    @SerialName("level_number") val levelNumber: Int,
    val progress: Double = 0.0,
)

/** One row from practice_sessions — just the timestamp, for the profile heatmap. */
@Serializable
data class DbSessionStartedAt(
    @SerialName("started_at") val startedAt: String,
)

/** One row from user_props — a stack of a single 道具 type. */
@Serializable
data class DbUserProp(
    @SerialName("prop_type") val propType: String,
    val count: Int,
)

@Serializable
data class DbGrantPropParams(
    @SerialName("p_prop_type") val propType: String,
    @SerialName("p_count") val count: Int,
)

@Serializable
data class DbGrantPropResult(
    @SerialName("prop_type") val propType: String,
    val count: Int,
)

@Serializable
data class DbCheckAwardsParams(
    @SerialName("p_user_id") val userId: String,
)

@Serializable
data class DbNewAward(
    @SerialName("new_award_id") val awardId: String,
    @SerialName("new_award_name") val awardName: String,
)

@Serializable
data class DbUserAward(
    @SerialName("award_id") val awardId: String,
    @SerialName("awarded_at") val awardedAt: String,
    @SerialName("award_definitions") val definition: DbAwardDefinition? = null,
)

@Serializable
data class DbAwardDefinition(
    val id: String,
    @SerialName("name_zh") val nameZh: String,
    @SerialName("description_zh") val descriptionZh: String? = null,
)
