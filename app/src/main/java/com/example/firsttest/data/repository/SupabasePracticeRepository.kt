package com.example.firsttest.data.repository

import com.example.firsttest.data.model.PracticeCard
import com.example.firsttest.data.model.Question
import com.example.firsttest.data.remote.DbQuestion
import com.example.firsttest.data.remote.DbQuestionOption
import com.example.firsttest.data.remote.Supabase
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns

/**
 * Real [PracticeRepository] that reads questions from Supabase.
 *
 * Supported type codes:
 *   1 — keyboard fill-in
 *   2 — MCQ 4-option (options fetched from question_options)
 *   3 — sentence cloze typing (near-meaning answers fetched from question_options
 *       where is_correct = false)
 *
 * [getDailyPractice] still returns a fake card layout — see class-level TODO.
 * TODO PHASE 3: replace [getDailyPractice] with real user-progress query.
 *
 * cardId scoping: the questions table has no per-card column yet, so [cardId]
 * is not used for DB filtering. Phase 3 will add a level_number column.
 */
class SupabasePracticeRepository : PracticeRepository {

    override suspend fun getDailyPractice(): List<PracticeCard> =
        FakePracticeRepository().getDailyPractice()

    override suspend fun getQuestionsForCard(cardId: String): List<Question> {
        // ---- 1. Fetch active questions of all supported types ----------------
        val dbQuestions = Supabase.client
            .from("questions")
            .select(
                Columns.list(
                    "id, type_code, prompt_hint, stem, correct_answer, " +
                    "translation_zh, expected_time_ms"
                )
            ) {
                filter {
                    eq("is_active", true)
                    isIn("type_code", listOf(1, 2, 3))
                }
                limit(20)
            }
            .decodeList<DbQuestion>()

        // ---- 2. Fetch options for MCQ (type 2) and near-meaning for cloze (type 3) --
        val needsOptions = dbQuestions.filter { it.typeCode == 2 || it.typeCode == 3 }.map { it.id }
        val options: List<DbQuestionOption> = if (needsOptions.isEmpty()) {
            emptyList()
        } else {
            Supabase.client
                .from("question_options")
                .select(Columns.list("question_id, option_text, is_correct, sort_order")) {
                    filter {
                        isIn("question_id", needsOptions)
                    }
                }
                .decodeList<DbQuestionOption>()
        }

        val optionsByQuestion = options.groupBy { it.questionId }

        // ---- 3. Map to domain model -----------------------------------------
        return dbQuestions.map { q ->
            val qOptions = optionsByQuestion[q.id]?.sortedBy { it.sortOrder } ?: emptyList()
            when (q.typeCode) {
                2 -> Question(
                    id             = q.id,
                    typeCode       = q.typeCode,
                    promptHint     = q.promptHint,
                    stem           = q.stem,
                    correctAnswer  = q.correctAnswer,
                    translationZh  = q.translationZh,
                    expectedTimeMs = q.expectedTimeMs,
                    options        = qOptions.map { it.optionText },
                )
                3 -> Question(
                    id                  = q.id,
                    typeCode            = q.typeCode,
                    promptHint          = q.promptHint,
                    stem                = q.stem,
                    correctAnswer       = q.correctAnswer,
                    translationZh       = q.translationZh,
                    expectedTimeMs      = q.expectedTimeMs,
                    // For type 3, question_options rows with is_correct=false are near-meaning answers
                    nearMeaningAnswers  = qOptions.filter { !it.isCorrect }.map { it.optionText },
                )
                else -> Question(
                    id             = q.id,
                    typeCode       = q.typeCode,
                    promptHint     = q.promptHint,
                    stem           = q.stem,
                    correctAnswer  = q.correctAnswer,
                    translationZh  = q.translationZh,
                    expectedTimeMs = q.expectedTimeMs,
                )
            }
        }
    }
}
