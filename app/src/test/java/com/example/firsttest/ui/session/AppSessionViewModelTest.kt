package com.example.firsttest.ui.session

import com.example.firsttest.data.model.AbilityRadar
import com.example.firsttest.data.model.StreakInfo
import com.example.firsttest.data.model.User
import com.example.firsttest.data.model.UserLevel
import com.example.firsttest.data.repository.AuthRepository
import com.example.firsttest.data.repository.AuthState
import com.example.firsttest.data.repository.OnboardingFlowState
import com.example.firsttest.data.repository.OnboardingRepository
import com.example.firsttest.data.repository.SessionUserRepository
import com.example.firsttest.data.repository.UserBootstrapState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AppSessionViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun signedOutSessionShowsLoginState() = runTest(dispatcher) {
        val auth = SessionAuthRepository(AuthState.SignedOut)
        val viewModel = AppSessionViewModel(
            auth,
            SessionUserRepositoryFake(),
            BootstrapRepositoryFake(OnboardingFlowState.HOME_READY),
        )

        advanceUntilIdle()

        assertTrue(viewModel.uiState.value is AppSessionState.SignedOut)
    }

    @Test
    fun signedInUserResumesQuestionnaireFromBootstrap() = runTest(dispatcher) {
        val auth = SessionAuthRepository(AuthState.SignedIn("user-1", "u@example.com"))
        val viewModel = AppSessionViewModel(
            auth,
            SessionUserRepositoryFake(),
            BootstrapRepositoryFake(OnboardingFlowState.QUESTIONNAIRE_PENDING, index = 3),
        )

        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(state is AppSessionState.QuestionnairePending)
        assertTrue((state as AppSessionState.QuestionnairePending).bootstrap.currentQuestionIndex == 3)
    }

    @Test
    fun migratedCompletedUserOpensHome() = runTest(dispatcher) {
        val auth = SessionAuthRepository(AuthState.SignedIn("user-1", "u@example.com"))
        val viewModel = AppSessionViewModel(
            auth,
            SessionUserRepositoryFake(),
            BootstrapRepositoryFake(OnboardingFlowState.HOME_READY),
        )

        advanceUntilIdle()

        assertTrue(viewModel.uiState.value is AppSessionState.Authenticated)
    }

    @Test
    fun retiredAssessmentStateShowsMigrationError() = runTest(dispatcher) {
        val auth = SessionAuthRepository(AuthState.SignedIn("user-1", "u@example.com"))
        val viewModel = AppSessionViewModel(
            auth,
            SessionUserRepositoryFake(),
            BootstrapRepositoryFake(OnboardingFlowState.ASSESSMENT_PENDING, index = 5),
        )

        advanceUntilIdle()

        val state = viewModel.uiState.value as AppSessionState.Error
        assertTrue(state.message.contains("retired assessment flow"))
    }

    @Test
    fun missingBootstrapFunctionFallsBackToAuthenticatedAccount() = runTest(dispatcher) {
        val auth = SessionAuthRepository(AuthState.SignedIn("user-1", "u@example.com"))
        val viewModel = AppSessionViewModel(
            auth,
            SessionUserRepositoryFake(),
            FailingBootstrapRepository(
                "Could not find public.get_user_bootstrap_state in the schema cache. " +
                    "Code: PGRST202 URL: https://example.supabase.co/rest/v1/rpc"
            ),
        )

        advanceUntilIdle()

        assertTrue(viewModel.uiState.value is AppSessionState.Authenticated)
    }
}

private class SessionAuthRepository(initial: AuthState) : AuthRepository {
    private val state = MutableStateFlow(initial)
    override fun authState(): Flow<AuthState> = state
    override suspend fun register(username: String, password: String) = Unit
    override suspend fun signIn(username: String, password: String) = Unit
    override suspend fun changePassword(currentPassword: String, newPassword: String) = Unit
    override suspend fun signOut() {
        state.value = AuthState.SignedOut
    }
}

private class BootstrapRepositoryFake(
    private val flowState: OnboardingFlowState,
    private val index: Int = 0,
) : OnboardingRepository {
    override suspend fun getBootstrapState() = UserBootstrapState(
        flowState = flowState,
        currentQuestionIndex = index,
        onboardingAnswers = emptyMap(),
        placementStatus = "pending",
        currentLevel = if (flowState == OnboardingFlowState.HOME_READY) 1 else null,
        highestUnlockedLevel = if (flowState == OnboardingFlowState.HOME_READY) 1 else null,
    )

    override suspend fun saveAnswer(
        questionnaireVersion: String,
        answerKey: String,
        answerValue: String,
        expectedQuestionIndex: Int,
    ) = error("Not used")

    override suspend fun finalizePlacement(
        ieltsBand: Float,
        skip: Boolean,
    ) = error("Not used")
}

private class FailingBootstrapRepository(
    private val errorMessage: String,
) : OnboardingRepository {
    override suspend fun getBootstrapState(): UserBootstrapState =
        error(errorMessage)

    override suspend fun saveAnswer(
        questionnaireVersion: String,
        answerKey: String,
        answerValue: String,
        expectedQuestionIndex: Int,
    ): UserBootstrapState = error("Not used")

    override suspend fun finalizePlacement(
        ieltsBand: Float,
        skip: Boolean,
    ): UserBootstrapState = error("Not used")
}

private class SessionUserRepositoryFake : SessionUserRepository {
    override suspend fun refreshCurrentUser() = Unit
    override suspend fun clear() = Unit
    override suspend fun getCurrentUser() = User(
        id = "KQ1000000001",
        nickname = "Tester",
        avatarUrl = null,
        phone = null,
        duckPower = 0,
        userLevel = UserLevel(1, 4.0, "Level 1", 0f),
        abilityRadar = AbilityRadar(
            ieltsScore = 0.0,
            vocabulary = AbilityRadar.Axis(0f, 0f),
            listening = AbilityRadar.Axis(0f, 0f),
            speaking = AbilityRadar.Axis(0f, 0f),
            reading = AbilityRadar.Axis(0f, 0f),
            writing = AbilityRadar.Axis(0f, 0f),
        ),
        streak = StreakInfo(0, 1),
        props = emptyList(),
    )
}
