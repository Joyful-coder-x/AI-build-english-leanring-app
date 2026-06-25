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
import com.example.firsttest.ui.assessment.AssessmentScreen
import com.example.firsttest.ui.home.HomeNav
import com.example.firsttest.ui.home.HomeScreen
import com.example.firsttest.ui.home.BandExamPlaceholderScreen
import com.example.firsttest.ui.level.LevelPracticeScreen
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
 * App shell: a 4-tab [NavigationBar] with Home-tab sub-navigation for the
 * practice answering flow and scratch card.
 *
 * [showReassessment] overlays [AssessmentScreen] in re-assessment mode, which
 * is triggered from ProfileScreen's "重新评测" / "评测报告" buttons.
 */
@Composable
fun MainScreen(
    modifier: Modifier = Modifier,
    onSignOut: () -> Unit = {},
) {
    var selected by rememberSaveable { mutableStateOf(TopLevelDestination.Home) }
    var homeNav by remember { mutableStateOf<HomeNav>(HomeNav.LearningPath) }
    var showReassessment by rememberSaveable { mutableStateOf(false) }

    // Reassessment overlay — covers the entire shell.
    if (showReassessment) {
        BackHandler { showReassessment = false }
        AssessmentScreen(
            isNewUser = false,
            onComplete = { showReassessment = false },
            modifier = modifier,
        )
        return
    }

    // System back pops Home sub-nav back to the learning path.
    BackHandler(enabled = homeNav !is HomeNav.LearningPath) {
        homeNav = HomeNav.LearningPath
    }

    Scaffold(
        modifier = modifier,
        bottomBar = {
            NavigationBar {
                TopLevelDestination.entries.forEach { destination ->
                    NavigationBarItem(
                        selected = selected == destination,
                        onClick = { selected = destination },
                        icon = { Text(destination.icon) },
                        label = { Text(destination.label) },
                    )
                }
            }
        },
    ) { innerPadding ->
        Box(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
            when (selected) {
                TopLevelDestination.Home -> when (val nav = homeNav) {
                    is HomeNav.LearningPath ->
                        HomeScreen(
                            onLevelClick = { levelNumber ->
                                homeNav = HomeNav.LevelPractice(
                                    levelNumber = levelNumber,
                                    attemptId = System.nanoTime(),
                                )
                            },
                            onBandTestClick = { targetBand ->
                                homeNav = HomeNav.BandExam(targetBand)
                            },
                        )

                    is HomeNav.LevelPractice ->
                        LevelPracticeScreen(
                            levelNumber = nav.levelNumber,
                            attemptId = nav.attemptId,
                            onBack = { homeNav = HomeNav.LearningPath },
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

                    is HomeNav.PracticeQuestion ->
                        PracticeQuestionScreen(
                            cardId = nav.cardId,
                            onBack = { homeNav = HomeNav.LearningPath },
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

                    is HomeNav.PracticeResult ->
                        PracticeResultScreen(
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
                            onReturnHome = { homeNav = HomeNav.LearningPath },
                        )

                    is HomeNav.ScratchCard ->
                        ScratchCardScreen(
                            cardId = nav.cardId,
                            onComplete = { homeNav = HomeNav.LearningPath },
                        )

                    is HomeNav.BandExam ->
                        BandExamPlaceholderScreen(
                            targetBand = nav.targetBand,
                            onBack = { homeNav = HomeNav.LearningPath },
                        )
                }

                TopLevelDestination.Streak -> StreakScreen()
                TopLevelDestination.Mistakes -> MistakesScreen()
                TopLevelDestination.Profile -> ProfileScreen(
                    onReassessClick = { showReassessment = true },
                    onSignOut = onSignOut,
                )
            }
        }
    }
}
