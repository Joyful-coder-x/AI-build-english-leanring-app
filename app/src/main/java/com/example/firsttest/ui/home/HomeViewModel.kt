package com.example.firsttest.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.Level
import com.example.firsttest.data.repository.UserRepository
import com.example.firsttest.data.repository.VocabRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed interface HomeUiState {
    data object Loading : HomeUiState
    data class Success(
        val duckPower: Int,
        val streakDays: Int,
        val streakGoal: Int,
        val bands: List<BandSection>,
    ) : HomeUiState
    data class Error(val message: String) : HomeUiState
}

data class BandSection(
    val score: Double,
    val label: String,
    val levels: List<Level>,
    val isUnlocked: Boolean,
    val isCurrent: Boolean,
) {
    val completedLevelCount: Int get() = levels.count { it.isCompleted }
    val unlockedLevelCount: Int get() = levels.count { it.isUnlocked }
}

/**
 * Drives the Home / 首页 level-select screen.
 *
 * Loads all 240 levels and groups them into learner-facing IELTS difficulty
 * sections. Level state comes from user_level_progress.
 *
 * The status row (duck power, streak) is reactive via [UserRepository.userFlow].
 */
class HomeViewModel(
    private val userRepository: UserRepository,
    private val vocabRepository: VocabRepository,
) : ViewModel() {

    private val _levels = MutableStateFlow<List<Level>?>(null)
    private val _loadError = MutableStateFlow<String?>(null)

    val uiState: StateFlow<HomeUiState> = combine(
        userRepository.userFlow(),
        _levels,
        _loadError,
    ) { user, levels, error ->
        when {
            error != null  -> HomeUiState.Error(error)
            levels == null -> HomeUiState.Loading
            else -> HomeUiState.Success(
                duckPower  = user.duckPower,
                streakDays = user.streak.currentDays,
                streakGoal = user.streak.goalDays,
                bands      = buildBandSections(levels),
            )
        }
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.Eagerly,
        initialValue = HomeUiState.Loading,
    )

    init { loadLevels() }

    fun retry() {
        _loadError.value = null
        _levels.value = null
        loadLevels()
    }

    /** Reload persisted level/session counters whenever Home becomes visible. */
    fun refreshWhenVisible() {
        if (_levels.value != null) loadLevels()
    }

    private fun loadLevels() {
        viewModelScope.launch {
            try {
                _levels.value = vocabRepository.getLevels((1..240).toList())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _loadError.value = e.message ?: "加载失败，请重试"
            }
        }
    }

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer { HomeViewModel(AppRepositories.user, AppRepositories.vocab) }
        }
    }
}

internal fun buildBandSections(levels: List<Level>): List<BandSection> {
    val currentBand = levels
        .filter { it.isUnlocked }
        .maxByOrNull { it.number }
        ?.bandScore
        ?: 4.0

    return levels
        .groupBy { it.bandScore }
        .toSortedMap()
        .map { (score, bandLevels) ->
            val sortedLevels = bandLevels.sortedBy { it.number }
            val sectionNames = sortedLevels
                .mapNotNull { levelSectionName(it.title) }
                .distinct()
            BandSection(
                score = score,
                label = buildString {
                    append("雅思")
                    append(formatBandScore(score))
                    append("分难度")
                    if (sectionNames.size == 1) {
                        append("：")
                        append(sectionNames.single())
                    }
                },
                levels = sortedLevels,
                isUnlocked = bandLevels.any { it.isUnlocked },
                isCurrent = score == currentBand,
            )
        }
}

internal fun formatBandScore(score: Double): String =
    if (score % 1.0 == 0.0) score.toInt().toString() else score.toString()

internal fun levelSectionName(title: String): String? =
    title.substringBefore(":", missingDelimiterValue = "")
        .trim()
        .takeIf { it.isNotEmpty() }

internal fun levelTopicDisplayName(levels: List<Level>, levelIndex: Int): String {
    val title = levels[levelIndex].title
    val topic = title.substringAfter(":", missingDelimiterValue = title).trim()
    val occurrence = levels
        .take(levelIndex + 1)
        .count { it.title.equals(title, ignoreCase = true) }
    return "${topic.replaceFirstChar { it.uppercase() }} ($occurrence)"
}
