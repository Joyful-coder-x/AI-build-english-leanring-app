package com.example.firsttest.data.model

/**
 * A word in the user's 错词本 (mistake notebook).
 *
 * Words are added automatically when the user answers incorrectly during
 * practice (spec 2.3.1). They follow an Ebbinghaus spaced-repetition schedule
 * until the user passes the review — at which point they are removed.
 *
 * Review stages and intervals (spec 2.3 艾宾浩斯记忆曲线):
 *   0 = just added → review today
 *   1 = reviewed once → review after 1 day
 *   2 = reviewed twice → review after 3 days
 *   3 = reviewed 3× → review after 7 days
 *   4 = reviewed 4× → review after 15 days
 *   5 = reviewed 5× → review after 30 days → pass, remove from list
 *
 * TODO PHASE 3: persist to / read from Supabase `mistake_words` table
 *   (docs/architecture/DATA_MODEL_AND_CAPACITY.md §5). [reviewStage] drives AI-pushed review questions.
 */
data class MistakeWord(
    val wordId: String,
    val headword: String,
    val phonetic: String,
    val definitionZh: String,
    val addedAt: String,           // display string, e.g. "2026-06-05"
    val reviewStage: Int,          // 0..5
    val nextReviewLabel: String,   // "今天复习" / "明天复习" / "X天后复习"
)
