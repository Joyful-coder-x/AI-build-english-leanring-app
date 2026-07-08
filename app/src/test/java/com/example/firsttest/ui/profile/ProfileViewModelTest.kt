package com.example.firsttest.ui.profile

import com.example.firsttest.data.model.DuckTitle
import com.example.firsttest.data.repository.FakeUserRepository
import com.example.firsttest.data.repository.FakeVocabRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ProfileViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun startsInLoadingState() {
        // stateIn(Eagerly) hasn't had a chance to emit yet (dispatcher not advanced).
        val vm = ProfileViewModel(FakeUserRepository(), FakeVocabRepository())
        assertEquals(ProfileUiState.Loading, vm.uiState.value)
    }

    @Test
    fun emitsSuccessWithFakeUser() = runTest(dispatcher) {
        val vm = ProfileViewModel(FakeUserRepository(), FakeVocabRepository())
        advanceUntilIdle()
        val state = vm.uiState.value
        assertTrue("expected Success but was $state", state is ProfileUiState.Success)
        state as ProfileUiState.Success
        assertEquals("leoninebess", state.user.nickname)
        assertEquals(450, state.user.duckPower)
        assertEquals(5, state.user.streak.currentDays)
        // DuckTitle is derived from duckPower (450 → 初学鸭, threshold 0–499).
        assertEquals(DuckTitle.BEGINNER, state.user.duckTitle)
    }

    @Test
    fun duckPowerUpdateReflectsOnFlow() = runTest(dispatcher) {
        val repo = FakeUserRepository()
        val vm = ProfileViewModel(repo, FakeVocabRepository())
        advanceUntilIdle()

        repo.addDuckPower(100)
        advanceUntilIdle()

        val state = vm.uiState.value as ProfileUiState.Success
        assertEquals(550, state.user.duckPower)
    }
}
