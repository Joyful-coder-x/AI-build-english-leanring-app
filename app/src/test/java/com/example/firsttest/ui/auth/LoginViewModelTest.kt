package com.example.firsttest.ui.auth

import com.example.firsttest.data.repository.AuthRepository
import com.example.firsttest.data.repository.AuthState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class LoginViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun registrationAcceptsSixCharacterPasswordWithoutComplexityRules() = runTest(dispatcher) {
        val repository = RecordingAuthRepository()
        val viewModel = LoginViewModel(repository)
        viewModel.setMode(AuthMode.REGISTER)
        viewModel.setUsername("person_1")
        viewModel.setPassword("xxxxxx")
        viewModel.setConfirmPassword("xxxxxx")
        viewModel.setAcceptedTerms(true)

        viewModel.submit()
        advanceUntilIdle()

        assertEquals("xxxxxx", repository.registeredPassword)
        assertFalse(viewModel.uiState.value.isLoading)
        assertEquals("Account created. Please sign in.", viewModel.uiState.value.message)
    }

    @Test
    fun registrationRejectsPasswordShorterThanSixCharacters() = runTest(dispatcher) {
        val repository = RecordingAuthRepository()
        val viewModel = LoginViewModel(repository)
        viewModel.setMode(AuthMode.REGISTER)
        viewModel.setUsername("person_1")
        viewModel.setPassword("short")
        viewModel.setConfirmPassword("short")
        viewModel.setAcceptedTerms(true)

        viewModel.submit()
        advanceUntilIdle()

        assertEquals(null, repository.registeredPassword)
        assertEquals(
            "Password must be at least 6 characters.",
            viewModel.uiState.value.message,
        )
    }

    @Test
    fun authErrorsNeverExposeRequestDetails() {
        val error = IllegalStateException(
            "weak_password URL: https://example.supabase.co/auth/v1/signup Headers: apikey=secret"
        )

        assertEquals(
            "Password must be at least 6 characters.",
            LoginViewModel.authMessage(error),
        )
    }

    @Test
    fun unknownAuthErrorsUseGenericMessage() {
        val error = IllegalStateException(
            "URL: https://example.supabase.co/auth/v1/signup Headers: apikey=secret"
        )

        assertEquals(
            "Authentication failed. Try again.",
            LoginViewModel.authMessage(error),
        )
    }

    @Test
    fun loginUsesUsernameAndPassword() = runTest(dispatcher) {
        val repository = RecordingAuthRepository()
        val viewModel = LoginViewModel(repository)
        viewModel.setUsername("person_1")
        viewModel.setPassword("xxxxxx")

        viewModel.submit()
        advanceUntilIdle()

        assertEquals("person_1", repository.signedInUsername)
    }

    @Test
    fun registrationRequiresMatchingPasswords() = runTest(dispatcher) {
        val repository = RecordingAuthRepository()
        val viewModel = LoginViewModel(repository)
        viewModel.setMode(AuthMode.REGISTER)
        viewModel.setUsername("person_1")
        viewModel.setPassword("first1")
        viewModel.setConfirmPassword("second2")
        viewModel.setAcceptedTerms(true)

        viewModel.submit()
        advanceUntilIdle()

        assertEquals(null, repository.registeredPassword)
        assertEquals("Passwords do not match.", viewModel.uiState.value.message)
    }

    @Test
    fun registrationRequiresTermsConsent() = runTest(dispatcher) {
        val repository = RecordingAuthRepository()
        val viewModel = LoginViewModel(repository)
        viewModel.setMode(AuthMode.REGISTER)
        viewModel.setUsername("person_1")
        viewModel.setPassword("xxxxxx")
        viewModel.setConfirmPassword("xxxxxx")

        viewModel.submit()
        advanceUntilIdle()

        assertEquals(null, repository.registeredPassword)
        assertEquals("Accept the terms and privacy policy.", viewModel.uiState.value.message)
    }
}

private class RecordingAuthRepository(
    private val signInError: Throwable? = null,
) : AuthRepository {
    var registeredPassword: String? = null
    var signedInUsername: String? = null

    override fun authState(): Flow<AuthState> = flowOf(AuthState.SignedOut)

    override suspend fun register(username: String, password: String) {
        registeredPassword = password
    }

    override suspend fun signIn(username: String, password: String) {
        signInError?.let { throw it }
        signedInUsername = username
    }
    override suspend fun changePassword(currentPassword: String, newPassword: String) = Unit
    override suspend fun signOut() = Unit
}
