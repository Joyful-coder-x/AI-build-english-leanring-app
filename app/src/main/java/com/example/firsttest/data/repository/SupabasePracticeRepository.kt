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
 * [getDailyPractice] still returns a fake card layout because the per-user
 * learning path (which cards are unlocked, practice history) requires the
 * `level_progress` and `practice_sessions` tables.
 * TODO PHASE 3: replace [getDailyPractice] with real user-progress query once
 *   those tables exist in Supabase.
 *
 * [getQuestionsForCard] fetches all active type-1 and type-2 questions from the
 * `questions` table (with options from `question_options`) and returns them in
 * display order. In Phase 3 this will be filtered by the card's level/word set.
 * TODO PHASE 3: filter questions by the card's level_number so each 鸭力训练
 *   shows words appropriate to the user's current level.
 */
class SupabasePracticeRepository : PracticeRepository {

    override suspend fun getDailyPractice(): List<PracticeCard> =
        // TODO PHASE 3: fetch from Supabase level_progress + practice_sessions.
        FakePracticeRepository().getDailyPractice()

    override suspend fun getQuestionsForCard(cardId: String): List<Question> {
        // ---- 1. Fetch all questions ----------------------------------------
        val allDbQuestions = Supabase.client
            .from("questions")
            .select(
                Columns.list(
                    "id, type_code, prompt_hint, stem, correct_answer, " +
                    "translation_zh, expected_time_ms, is_active"
                )
            )
            .decodeList<DbQuestion>()

        // Phase 2 only renders type 1 (keyboard) and type 2 (MCQ).
        // Type 14 (writing) and others exist in the DB but are skipped here.
        // TODO PHASE 2: add type 14 (translation fill-in) renderer.
        // TODO PHASE 3: add remaining 12 question types.
        val questions = allDbQuestions.filter { it.isActive && it.typeCode in setOf(1, 2) }

        // ---- 2. Fetch options for MCQ questions ----------------------------
        val mcqIds = questions.filter { it.typeCode == 2 }.map { it.id }.toSet()
        val allOptions: List<DbQuestionOption> = if (mcqIds.isEmpty()) {
            emptyList()
        } else {
            Supabase.client
                .from("question_options")
                .select(Columns.list("question_id, option_text, is_correct, sort_order"))
                .decodeList<DbQuestionOption>()
                .filter { it.questionId in mcqIds }
        }

        val optionsByQuestion: Map<String, List<DbQuestionOption>> =
            allOptions.groupBy { it.questionId }

        // ---- 3. Map to domain model ----------------------------------------
        return questions.map { q ->
            val opts = optionsByQuestion[q.id]
                ?.sortedBy { it.sortOrder }
                ?.map { it.optionText }
                ?: emptyList()
            Question(
                id             = q.id,
                typeCode       = q.typeCode,
                promptHint     = q.promptHint,
                stem           = q.stem,
                correctAnswer  = q.correctAnswer,
                translationZh  = q.translationZh,
                expectedTimeMs = q.expectedTimeMs,
                options        = opts,
            )
        }
    }
}
