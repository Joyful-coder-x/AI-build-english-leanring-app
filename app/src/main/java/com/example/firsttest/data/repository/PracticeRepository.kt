package com.example.firsttest.data.repository

import com.example.firsttest.data.model.PracticeCard

/**
 * Source of the home learning-path cards (the AI-pushed daily practice).
 *
 * Phase 1 uses [FakePracticeRepository]. Later, a real implementation will
 * fetch the AI-generated daily cycle. See ARCHITECTURE.md.
 */
interface PracticeRepository {
    suspend fun getDailyPractice(): List<PracticeCard>
}
