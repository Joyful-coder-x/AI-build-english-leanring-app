package com.example.firsttest.ui.scratch

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.firsttest.data.model.PropType
import com.example.firsttest.data.repository.UserRepository
import com.example.firsttest.di.AppRepositories
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.random.Random

enum class ScratchRewardType { DUCK_POWER, STREAK_PROTECTION, CHALLENGE_KEY }

data class ScratchReward(
    val type: ScratchRewardType,
    val amount: Int,
    val icon: String,
    val title: String,
    val subtitle: String,
)

sealed interface ScratchCardUiState {
    data object Unscratched : ScratchCardUiState
    data class Revealed(val reward: ScratchReward) : ScratchCardUiState
    data object Collected : ScratchCardUiState
}

class ScratchCardViewModel(
    private val userRepository: UserRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<ScratchCardUiState>(ScratchCardUiState.Unscratched)
    val uiState: StateFlow<ScratchCardUiState> = _uiState.asStateFlow()

    fun onScratch() {
        if (_uiState.value !is ScratchCardUiState.Unscratched) return
        _uiState.value = ScratchCardUiState.Revealed(randomReward())
    }

    fun onCollect() {
        val s = _uiState.value as? ScratchCardUiState.Revealed ?: return
        viewModelScope.launch {
            when (s.reward.type) {
                ScratchRewardType.DUCK_POWER ->
                    userRepository.addDuckPower(s.reward.amount)
                ScratchRewardType.STREAK_PROTECTION ->
                    userRepository.addProp(PropType.STREAK_PROTECTION, 1)
                ScratchRewardType.CHALLENGE_KEY ->
                    userRepository.addProp(PropType.CHALLENGE_KEY, 1)
            }
            _uiState.value = ScratchCardUiState.Collected
        }
    }

    companion object {
        val Factory = viewModelFactory {
            initializer { ScratchCardViewModel(AppRepositories.user) }
        }

        // Probabilities: 40% duck+20, 30% duck+10, 20% streak protection, 10% challenge key
        private fun randomReward(): ScratchReward = when (Random.nextInt(10)) {
            in 0..3 -> ScratchReward(ScratchRewardType.DUCK_POWER, 20, "⚡", "鸭力值 +20", "继续保持，你最棒！")
            in 4..6 -> ScratchReward(ScratchRewardType.DUCK_POWER, 10, "⚡", "鸭力值 +10", "每天进步一点点！")
            in 7..8 -> ScratchReward(ScratchRewardType.STREAK_PROTECTION, 1, "🛡️", "连胜保护 ×1", "你的连胜有保障了！")
            else    -> ScratchReward(ScratchRewardType.CHALLENGE_KEY, 1, "🔑", "挑战赛钥匙 ×1", "解锁挑战赛，超越自己！")
        }
    }
}
