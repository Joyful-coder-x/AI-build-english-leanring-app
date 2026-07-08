package com.example.firsttest.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.Award
import com.example.firsttest.data.model.User
import com.example.firsttest.data.repository.UserRepository
import com.example.firsttest.data.repository.VocabRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.LocalDate

sealed interface ProfileUiState {
    data object Loading : ProfileUiState
    data class Success(
        val user: User,
        val sessionDates: List<LocalDate> = emptyList(),
        val awards: List<Award> = emptyList(),
    ) : ProfileUiState
}

/**
 * Holds the Profile screen state.
 *
 * Collects [UserRepository.userFlow] reactively, and loads practice session
 * dates once on init for the contribution heatmap.
 */
class ProfileViewModel(
    userRepository: UserRepository,
    private val vocabRepository: VocabRepository,
) : ViewModel() {

    private val _sessionDates = MutableStateFlow<List<LocalDate>>(emptyList())
    private val _awards = MutableStateFlow<List<Award>>(emptyList())

    val uiState: StateFlow<ProfileUiState> = combine(
        userRepository.userFlow(),
        _sessionDates,
        _awards,
    ) { user, dates, awards ->
        ProfileUiState.Success(user, dates, awards)
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.Eagerly,
        initialValue = ProfileUiState.Loading,
    )

    init {
        viewModelScope.launch {
            _sessionDates.value = runCatching {
                vocabRepository.getPracticeSessionDates(recentDays = 84)
            }.getOrDefault(emptyList())
        }
        viewModelScope.launch {
            _awards.value = runCatching { userRepository.getAwards() }.getOrDefault(emptyList())
        }
    }

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer { ProfileViewModel(AppRepositories.user, AppRepositories.vocab) }
        }
    }
}
