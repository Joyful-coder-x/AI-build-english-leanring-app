package com.example.firsttest.data.repository

import com.example.firsttest.data.model.User

enum class OnboardingFlowState {
    QUESTIONNAIRE_PENDING,
    ASSESSMENT_PENDING,
    PLACEMENT_FINALIZED,
    HOME_READY,
}

data class UserBootstrapState(
    val flowState: OnboardingFlowState,
    val currentQuestionIndex: Int,
    val onboardingAnswers: Map<String, String>,
    val placementStatus: String,
    val currentLevel: Int?,
    val highestUnlockedLevel: Int?,
)

interface OnboardingRepository {
    suspend fun getBootstrapState(): UserBootstrapState

    suspend fun saveAnswer(
        questionnaireVersion: String,
        answerKey: String,
        answerValue: String,
        expectedQuestionIndex: Int,
    ): UserBootstrapState

    /** Finalises placement after the assessment (or skip) and returns the updated bootstrap state. */
    suspend fun finalizePlacement(ieltsBand: Float, skip: Boolean = false): UserBootstrapState
}

interface SessionUserRepository {
    suspend fun refreshCurrentUser()
    suspend fun clear()
    suspend fun getCurrentUser(): User
}
