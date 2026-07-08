package com.example.firsttest.data.repository

import com.example.firsttest.data.remote.DbUserBootstrapState
import com.example.firsttest.data.remote.FinalizePlacementParams
import com.example.firsttest.data.remote.SaveOnboardingAnswerParams
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.result.PostgrestResult
import io.github.jan.supabase.postgrest.rpc
import kotlinx.serialization.json.jsonPrimitive

class SupabaseOnboardingRepository(
    private val client: SupabaseClient,
) : OnboardingRepository {
    override suspend fun getBootstrapState(): UserBootstrapState =
        client.postgrest.rpc("get_user_bootstrap_state").decodeBootstrap()

    override suspend fun saveAnswer(
        questionnaireVersion: String,
        answerKey: String,
        answerValue: String,
        expectedQuestionIndex: Int,
    ): UserBootstrapState =
        client.postgrest.rpc(
            "save_onboarding_answer",
            SaveOnboardingAnswerParams(
                questionnaireVersion = questionnaireVersion,
                answerKey = answerKey,
                answerValue = answerValue,
                expectedQuestionIndex = expectedQuestionIndex,
            ),
        ).decodeBootstrap()

    override suspend fun finalizePlacement(ieltsBand: Float, skip: Boolean): UserBootstrapState =
        client.postgrest.rpc(
            "finalize_placement",
            FinalizePlacementParams(ieltsBand = ieltsBand, skip = skip),
        ).decodeBootstrap()

    private fun PostgrestResult.decodeBootstrap(): UserBootstrapState {
        val row = decodeAs<DbUserBootstrapState>()
        return UserBootstrapState(
            flowState = when (row.flowState) {
                "questionnaire_pending" -> OnboardingFlowState.QUESTIONNAIRE_PENDING
                "assessment_pending" -> OnboardingFlowState.ASSESSMENT_PENDING
                "placement_finalized" -> OnboardingFlowState.PLACEMENT_FINALIZED
                "home_ready" -> OnboardingFlowState.HOME_READY
                else -> error("Unknown onboarding flow state: ${row.flowState}")
            },
            currentQuestionIndex = row.currentQuestionIndex,
            onboardingAnswers = row.onboardingAnswers.mapValues { it.value.jsonPrimitive.content },
            placementStatus = row.placementStatus,
            currentLevel = row.currentLevel,
            highestUnlockedLevel = row.highestUnlockedLevel,
        )
    }
}
