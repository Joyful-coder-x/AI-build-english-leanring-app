package com.example.firsttest.data.repository

import com.example.firsttest.data.model.MistakeWord

/**
 * Source of the user's mistake-word list (错词本, spec 2.3).
 *
 * Phase 2 uses [FakeMistakeRepository].
 * TODO PHASE 3: implement SupabaseMistakeRepository that reads/writes the
 *   `mistake_words` table in Supabase (DATA_DESIGN.md §5).
 *   Words are added automatically by PracticeViewModel on a wrong answer,
 *   and removed after the user passes reviewStage 5.
 */
interface MistakeRepository {
    suspend fun getMistakeWords(): List<MistakeWord>
}
