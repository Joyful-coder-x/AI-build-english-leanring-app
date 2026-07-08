package com.example.firsttest.ui.onboarding

import com.example.firsttest.data.repository.OnboardingFlowState
import com.example.firsttest.data.repository.OnboardingRepository
import com.example.firsttest.data.repository.UserBootstrapState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class OnboardingViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun answerAdvancesOnlyAfterServerResponse() = runTest(dispatcher) {
        val repository = RecordingOnboardingRepository(waitForRelease = true)
        val viewModel = OnboardingViewModel(repository, bootstrap(index = 0))

        viewModel.onAnswer(ONBOARDING_QUESTIONS[0].options.first())
        runCurrent()

        val saving = viewModel.uiState.value as OnboardingUiState.Question
        assertTrue(saving.isSaving)
        assertEquals(0, saving.currentIndex)

        repository.release()
        advanceUntilIdle()

        val advanced = viewModel.uiState.value as OnboardingUiState.Question
        assertEquals(1, advanced.currentIndex)
        assertFalse(advanced.isSaving)
        assertEquals("occupation", repository.lastKey)
    }

    @Test
    fun failedSaveKeepsQuestionAndCanRetry() = runTest(dispatcher) {
        val repository = RecordingOnboardingRepository(failNext = true)
        val viewModel = OnboardingViewModel(repository, bootstrap(index = 2))

        viewModel.onAnswer(ONBOARDING_QUESTIONS[2].options.first())
        advanceUntilIdle()

        val failed = viewModel.uiState.value as OnboardingUiState.Question
        assertEquals(2, failed.currentIndex)
        assertTrue(failed.errorMessage != null)

        viewModel.retry()
        advanceUntilIdle()

        val advanced = viewModel.uiState.value as OnboardingUiState.Question
        assertEquals(3, advanced.currentIndex)
        assertEquals(2, repository.lastExpectedIndex)
    }

    @Test
    fun fifthAnswerCompletesOnboardingToHomeReadyLevelOne() = runTest(dispatcher) {
        val repository = RecordingOnboardingRepository()
        val viewModel = OnboardingViewModel(repository, bootstrap(index = 4))

        viewModel.onAnswer(ONBOARDING_QUESTIONS[4].options.first())
        advanceUntilIdle()

        assertEquals(OnboardingUiState.Completed, viewModel.uiState.value)
        assertEquals(OnboardingFlowState.HOME_READY, repository.lastBootstrap?.flowState)
        assertEquals(1, repository.lastBootstrap?.currentLevel)
        assertEquals(1, repository.lastBootstrap?.highestUnlockedLevel)
        assertFalse(repository.finalizePlacementCalled)
    }

    private fun bootstrap(index: Int) = UserBootstrapState(
        flowState = OnboardingFlowState.QUESTIONNAIRE_PENDING,
        currentQuestionIndex = index,
        onboardingAnswers = emptyMap(),
        placementStatus = "pending",
        currentLevel = null,
        highestUnlockedLevel = null,
    )
}

private class RecordingOnboardingRepository(
    private var failNext: Boolean = false,
    waitForRelease: Boolean = false,
) : OnboardingRepository {
    private val releaseGate = CompletableDeferred<Unit>().apply {
        if (!waitForRelease) complete(Unit)
    }
    var lastKey: String? = null
    var lastExpectedIndex: Int? = null
    var lastBootstrap: UserBootstrapState? = null
        private set
    var finalizePlacementCalled: Boolean = false
        private set

    fun release() {
        releaseGate.complete(Unit)
    }

    override suspend fun getBootstrapState(): UserBootstrapState =
        error("Not used")

    override suspend fun saveAnswer(
        questionnaireVersion: String,
        answerKey: String,
        answerValue: String,
        expectedQuestionIndex: Int,
    ): UserBootstrapState {
        lastKey = answerKey
        lastExpectedIndex = expectedQuestionIndex
        releaseGate.await()
        if (failNext) {
            failNext = false
            error("Network unavailable")
        }
        val nextIndex = expectedQuestionIndex + 1
        return UserBootstrapState(
            flowState = if (nextIndex == 5) {
                OnboardingFlowState.HOME_READY
            } else {
                OnboardingFlowState.QUESTIONNAIRE_PENDING
            },
            currentQuestionIndex = nextIndex,
            onboardingAnswers = mapOf(answerKey to answerValue),
            placementStatus = if (nextIndex == 5) "level_1" else "pending",
            currentLevel = if (nextIndex == 5) 1 else null,
            highestUnlockedLevel = if (nextIndex == 5) 1 else null,
        ).also { lastBootstrap = it }
    }

    override suspend fun finalizePlacement(
        ieltsBand: Float,
        skip: Boolean,
    ): UserBootstrapState {
        finalizePlacementCalled = true
        error("Not used")
    }
}
