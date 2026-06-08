package com.example.firsttest.ui.mistakes

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.MistakeWord
import com.example.firsttest.data.repository.MistakeRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface MistakesUiState {
    data object Loading : MistakesUiState
    data object Empty : MistakesUiState        // no mistakes yet (spec: show empty state)
    data class Success(val words: List<MistakeWord>) : MistakesUiState
}

/**
 * Drives the 错词本 screen (spec 2.3).
 *
 * Words enter the list when the user answers incorrectly during practice and
 * are removed once they pass reviewStage 5 (Ebbinghaus full cycle).
 *
 * TODO PHASE 3: read/write from Supabase `mistake_words` table.
 *   Words should be added in PracticeViewModel.onSubmit() when !isCorrect.
 * TODO PHASE 3: "开始复习" tap should navigate into a targeted practice session
 *   filtered to the due mistake words (sorted by reviewStage ascending).
 */
class MistakesViewModel(
    private val repository: MistakeRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<MistakesUiState>(MistakesUiState.Loading)
    val uiState: StateFlow<MistakesUiState> = _uiState.asStateFlow()

    init { load() }

    private fun load() {
        viewModelScope.launch {
            val words = repository.getMistakeWords()
            _uiState.value = if (words.isEmpty()) MistakesUiState.Empty
                             else MistakesUiState.Success(words)
        }
    }

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer { MistakesViewModel(AppRepositories.mistakes) }
        }
    }
}
