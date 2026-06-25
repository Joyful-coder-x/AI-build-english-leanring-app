package com.example.firsttest.ui.home

/**
 * Home-tab sub-navigation state. MainScreen holds this and passes callbacks
 * into each screen.
 */
sealed interface HomeNav {
    data object LearningPath : HomeNav
    data class PracticeQuestion(val cardId: String) : HomeNav
    data class PracticeResult(
        val levelNumber: Int?,
        val correctCount: Int,
        val totalCount: Int,
        val starRating: Int,
        val duckPowerEarned: Int,
    ) : HomeNav
    data class ScratchCard(val cardId: String) : HomeNav
    /**
     * [attemptId] makes each Start/Review click a distinct navigation entry.
     * Without it, Compose reuses the old level ViewModel (for example
     * `mc_level_1`) and a completed level immediately reopens its old result.
     */
    data class MeaningChoice(
        val levelNumber: Int,
        val attemptId: Long,
    ) : HomeNav
    data class BandExam(val targetBand: Double) : HomeNav
    data class LevelPractice(
        val levelNumber: Int,
        val attemptId: Long,
    ) : HomeNav
}
