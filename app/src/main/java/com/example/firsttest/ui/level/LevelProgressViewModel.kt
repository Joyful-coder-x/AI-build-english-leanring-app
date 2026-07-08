package com.example.firsttest.ui.level

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.LevelWordStatus
import com.example.firsttest.data.repository.VocabRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface LevelProgressUiState {
    data object Loading : LevelProgressUiState
    data class Success(
        val levelNumber: Int,
        val isUnlocked: Boolean,
        val words: List<LevelWordStatus>,
    ) : LevelProgressUiState {
        val masteredCount: Int get() = words.count { it.isMasteredStatus() }
        val startedCount: Int get() = words.count { it.isStartedStatus() }
    }
    data class Error(val message: String) : LevelProgressUiState
}

class LevelProgressViewModel(
    val levelNumber: Int,
    private val vocabRepository: VocabRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<LevelProgressUiState>(LevelProgressUiState.Loading)
    val uiState: StateFlow<LevelProgressUiState> = _uiState.asStateFlow()

    init { load() }

    fun retry() { load() }

    private fun load() {
        _uiState.value = LevelProgressUiState.Loading
        viewModelScope.launch {
            try {
                val level = vocabRepository.getLevels(listOf(levelNumber)).firstOrNull()
                val isUnlocked = level?.isUnlocked == true
                val statuses = if (isUnlocked) {
                    vocabRepository.getLevelWordStatuses(levelNumber)
                } else {
                    emptyList()
                }
                _uiState.value = LevelProgressUiState.Success(levelNumber, isUnlocked, statuses)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = LevelProgressUiState.Error(
                    e.message ?: "Failed to load level progress.",
                )
            }
        }
    }

    companion object {
        fun factory(levelNumber: Int) = viewModelFactory {
            initializer {
                LevelProgressViewModel(
                    levelNumber = levelNumber,
                    vocabRepository = AppRepositories.vocab,
                )
            }
        }
    }
}

internal fun LevelWordStatus.isMasteredStatus(): Boolean =
    status == "\u5df2\u638c\u63e1" || status.equals("mastered", ignoreCase = true)

internal fun LevelWordStatus.isReviewingStatus(): Boolean =
    status == "\u590d\u4e60\u4e2d" || status.equals("reviewing", ignoreCase = true)

internal fun LevelWordStatus.isStartedStatus(): Boolean =
    status != "\u672a\u5b66\u4e60" && !status.equals("not_started", ignoreCase = true)
