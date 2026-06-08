package com.example.firsttest.data.repository

import com.example.firsttest.data.model.PracticeCard
import com.example.firsttest.data.model.Question

/**
 * Source of the home learning-path cards and the questions inside each card.
 *
 * Phase 1-2 uses [FakePracticeRepository]. A real implementation will fetch
 * the AI-generated daily cycle and question bank. See ARCHITECTURE.md.
 */
interface PracticeRepository {
    suspend fun getDailyPractice(): List<PracticeCard>
    suspend fun getQuestionsForCard(cardId: String): List<Question>
}
