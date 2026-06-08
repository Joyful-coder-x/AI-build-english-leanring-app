package com.example.firsttest.ui.home

/**
 * Home-tab sub-navigation state. MainScreen holds this and passes callbacks
 * into each screen. Using plain `remember` (not `rememberSaveable`) is
 * intentional — this is a Phase 2 prototype; navigation-compose replaces this
 * in Phase 3+ and config-change resets to LearningPath are acceptable.
 */
sealed interface HomeNav {
    data object LearningPath : HomeNav
    data class PracticeQuestion(val cardId: String) : HomeNav
    data class PracticeResult(
        val correctCount: Int,
        val totalCount: Int,
        val starRating: Int,
        val duckPowerEarned: Int,
    ) : HomeNav
}
