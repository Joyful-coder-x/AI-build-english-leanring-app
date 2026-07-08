package com.example.firsttest.ui.practice

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.firsttest.data.model.LevelWordStatus
import com.example.firsttest.data.repository.VocabRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface LevelWordListState {
    data object Idle : LevelWordListState
    data object Loading : LevelWordListState
    data class Ready(val words: List<LevelWordStatus>) : LevelWordListState
    data class Error(val message: String) : LevelWordListState
}

class PracticeResultViewModel(
    private val repository: VocabRepository,
) : ViewModel() {
    private val mutableWordList =
        MutableStateFlow<LevelWordListState>(LevelWordListState.Idle)
    val wordList: StateFlow<LevelWordListState> = mutableWordList.asStateFlow()

    fun loadLevelWords(levelNumber: Int) {
        if (mutableWordList.value is LevelWordListState.Ready ||
            mutableWordList.value is LevelWordListState.Loading
        ) return

        mutableWordList.value = LevelWordListState.Loading
        viewModelScope.launch {
            try {
                mutableWordList.value = LevelWordListState.Ready(
                    repository.getLevelWordStatuses(levelNumber)
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                mutableWordList.value = LevelWordListState.Error(
                    error.message ?: "Failed to load level words."
                )
            }
        }
    }

    companion object {
        val Factory: ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T =
                    PracticeResultViewModel(AppRepositories.vocab) as T
            }
    }
}
