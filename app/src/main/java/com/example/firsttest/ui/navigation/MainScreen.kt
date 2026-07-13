package com.example.firsttest.ui.navigation

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.sp
import com.example.firsttest.ui.home.BandUpgradeExamScreen
import com.example.firsttest.ui.home.HomeNav
import com.example.firsttest.ui.home.HomeScreen
import com.example.firsttest.ui.home.OverallAssessmentScreen
import com.example.firsttest.ui.level.LevelPracticeScreen
import com.example.firsttest.ui.level.LevelProgressScreen
import com.example.firsttest.ui.mistakes.MistakesScreen
import com.example.firsttest.ui.practice.PracticeQuestionScreen
import com.example.firsttest.ui.practice.PracticeResultScreen
import com.example.firsttest.ui.profile.ProfileScreen
import com.example.firsttest.ui.scratch.ScratchCardScreen
import com.example.firsttest.ui.streak.StreakScreen

enum class TopLevelDestination(val label: String, val icon: String) {
    Home("首页", "🏠"),
    Streak("连胜", "🔥"),
    Mistakes("错词本", "📕"),
    Profile("我的", "🦆"),
}

/**
 * App shell with Home-tab sub-navigation for the active Phase 1 learning path.
 * Legacy placement/reassessment is intentionally not reachable from the shell.
 */
@Composable
fun MainScreen(
    modifier: Modifier = Modifier,
    onSignOut: () -> Unit = {},
) {
    var selected by rememberSaveable { mutableStateOf(TopLevelDestination.Home) }
    var homeNav by remember { mutableStateOf<HomeNav>(HomeNav.LearningPath) }
    var homeRefreshToken by rememberSaveable { mutableStateOf(0) }

    fun returnToLearningPath(refresh: Boolean = false) {
        if (refresh) homeRefreshToken += 1
        homeNav = HomeNav.LearningPath
    }

    BackHandler(enabled = homeNav !is HomeNav.LearningPath) {
        returnToLearningPath(refresh = true)
    }

    Scaffold(
        modifier = modifier,
        bottomBar = {
            NavigationBar {
                TopLevelDestination.entries.forEach { destination ->
                    NavigationBarItem(
                        selected = selected == destination,
                        onClick = { selected = destination },
                        icon = { Text(destination.icon, fontSize = 22.sp) },
                        label = { Text(destination.label) },
                    )
                }
            }
        },
    ) { innerPadding ->
        Box(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
            when (selected) {
                TopLevelDestination.Home -> when (val nav = homeNav) {
                    is HomeNav.LearningPath -> HomeScreen(
                        refreshToken = homeRefreshToken,
                        onLevelClick = { levelNumber ->
                            homeNav = HomeNav.LevelProgress(levelNumber)
                        },
                        onBandTestClick = { targetBand ->
                            homeNav = HomeNav.BandExam(targetBand)
                        },
                        onOverallAssessmentClick = {
                            homeNav = HomeNav.OverallAssessment
                        },
                        onScratchCardClick = { cardId ->
                            homeNav = HomeNav.ScratchCard(cardId)
                        },
                    )

                    is HomeNav.LevelProgress -> LevelProgressScreen(
                        levelNumber = nav.levelNumber,
                        onBack = { returnToLearningPath(refresh = true) },
                        onStartPractice = { levelNumber ->
                            homeNav = HomeNav.LevelPractice(
                                levelNumber = levelNumber,
                                attemptId = System.nanoTime(),
                            )
                        },
                    )

                    is HomeNav.LevelPractice -> LevelPracticeScreen(
                        levelNumber = nav.levelNumber,
                        attemptId = nav.attemptId,
                        onBack = { returnToLearningPath(refresh = true) },
                        onSessionComplete = { correct, total, stars, power ->
                            homeNav = HomeNav.PracticeResult(
                                nav.levelNumber,
                                correct,
                                total,
                                stars,
                                power,
                            )
                        },
                    )

                    is HomeNav.MeaningChoice -> homeNav = HomeNav.LearningPath

                    is HomeNav.PracticeQuestion -> PracticeQuestionScreen(
                        cardId = nav.cardId,
                        onBack = { returnToLearningPath(refresh = true) },
                        onSessionComplete = { correct, total, stars, power -> 
                            homeNav = HomeNav.PracticeResult(
                                null,
                                correct,
                                total,
                                stars,
                                power,
                            )
                        },
                    )

                    is HomeNav.PracticeResult -> PracticeResultScreen(
                        levelNumber = nav.levelNumber,
                        correctCount = nav.correctCount,
                        totalCount = nav.totalCount,
                        starRating = nav.starRating,
                        duckPowerEarned = nav.duckPowerEarned,
                        onRepeat = nav.levelNumber?.let { levelNumber ->
                            {
                                homeNav = HomeNav.LevelPractice(
                                    levelNumber = levelNumber,
                                    attemptId = System.nanoTime(),
                                )
                            }
                        },
                        onReturnHome = { returnToLearningPath(refresh = true) },
                    )

                    is HomeNav.ScratchCard -> ScratchCardScreen(
                        cardId = nav.cardId,
                        onComplete = { returnToLearningPath(refresh = true) },
                    )

                    is HomeNav.BandExam -> BandUpgradeExamScreen(
                        targetBand = nav.targetBand,
                        onBack = { returnToLearningPath(refresh = true) },
                    )

                    is HomeNav.OverallAssessment -> OverallAssessmentScreen(
                        onBack = { returnToLearningPath(refresh = true) },
                    )
                }

                TopLevelDestination.Streak -> StreakScreen()
                TopLevelDestination.Mistakes -> MistakesScreen()
                TopLevelDestination.Profile -> ProfileScreen(onSignOut = onSignOut)
            }
        }
    }
}
