package com.example.firsttest.data.repository

import com.example.firsttest.data.model.Level
import com.example.firsttest.data.model.LevelPracticeAnswerResult
import com.example.firsttest.data.model.LevelPracticeRound
import com.example.firsttest.data.model.LevelWordStatus
import com.example.firsttest.data.model.MeaningChoiceQuestion
import com.example.firsttest.data.model.PracticeAnswerResult
import com.example.firsttest.data.model.PracticeRound
import com.example.firsttest.data.model.PracticeRoundResult
import java.time.LocalDate

/**
 * Vocabulary content repository: levels and dynamically-built practice questions.
 *
 * [getMeaningChoiceQuestionsForLevel] is the generic entry point — any level
 * can call it to produce a fresh set of Meaning Choice questions. The caller
 * supplies the level number; the implementation picks target senses and safe
 * distractors from that same level pool.
 */
interface VocabRepository {
    suspend fun getLevels(numbers: List<Int>): List<Level>
    suspend fun startPracticeRound(levelNumber: Int): PracticeRound
    suspend fun savePracticeAnswer(
        roundId: String,
        position: Int,
        answer: String,
        responseTimeMs: Int,
    ): PracticeAnswerResult
    suspend fun completePracticeRound(roundId: String): PracticeRoundResult
    suspend fun getLevelWordStatuses(levelNumber: Int): List<LevelWordStatus>

    /** Unified level practice: server-created round supporting option + cloze questions. */
    suspend fun startLevelPracticeRound(levelNumber: Int): LevelPracticeRound
    suspend fun saveLevelPracticeAnswer(
        roundId: String,
        position: Int,
        answer: String,
        responseTimeMs: Int,
    ): LevelPracticeAnswerResult

    /** Legacy client-built flow retained temporarily for compatibility tests. */
    suspend fun getMeaningChoiceQuestionsForLevel(levelNumber: Int, limit: Int = 10): List<MeaningChoiceQuestion>

    /**
     * Persists one answer to Supabase. Lazily creates today's practice session
     * for [levelNumber] if none exists. Also upserts [user_sense_mastery] and,
     * on a wrong answer, inserts into [mistake_senses].
     *
     * Designed to be called fire-and-forget — errors should not interrupt the UI flow.
     */
    suspend fun saveMeaningChoiceAnswer(
        levelNumber: Int,
        senseId: String,
        selectedSenseId: String,
        isCorrect: Boolean,
        responseTimeMs: Int,
    )

    /**
     * Marks today's practice session as completed and upserts [user_level_progress].
     * Called once at the end of every session regardless of whether individual
     * [saveMeaningChoiceAnswer] calls succeeded.
     */
    suspend fun completeMeaningChoiceSession(
        levelNumber: Int,
        correctCount: Int,
        totalCount: Int,
        starRating: Int,
        duckPowerEarned: Int,
    )

    /** Returns dates of completed practice sessions within the last [recentDays] days. */
    suspend fun getPracticeSessionDates(recentDays: Int): List<LocalDate>
}
