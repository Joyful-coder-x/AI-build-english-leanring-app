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
import com.example.firsttest.ui.home.HomeNav
import com.example.firsttest.ui.home.HomeScreen
import com.example.firsttest.ui.mistakes.MistakesScreen
import com.example.firsttest.ui.practice.PracticeQuestionScreen
import com.example.firsttest.ui.practice.PracticeResultScreen
import com.example.firsttest.ui.profile.ProfileScreen
import com.example.firsttest.ui.streak.StreakScreen

enum class TopLevelDestination(val label: String, val icon: String) {
    Home("首页", "🏠"),
    Streak("连胜", "🔥"),
    Mistakes("错词本", "📕"),
    Profile("我的", "🦆"),
}

/**
 * App shell: a 4-tab [NavigationBar] with Home-tab sub-navigation for the
 * practice answering flow (Home → PracticeQuestion → PracticeResult).
 *
 * Tab selection uses [rememberSaveable] (survives rotation).
 * Home sub-nav uses plain [remember] — config changes reset to LearningPath,
 * which is acceptable in Phase 2. navigation-compose replaces this in Phase 3+.
 */
@Composable
fun MainScreen(modifier: Modifier = Modifier) {
    var selected by rememberSaveable { mutableStateOf(TopLevelDestination.Home) }
    var homeNav by remember { mutableStateOf<HomeNav>(HomeNav.LearningPath) }

    // System back button pops the Home sub-stack back to the learning path.
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
                            onDrillClick = { cardId ->
                                homeNav = HomeNav.PracticeQuestion(cardId)
                            },
                        )

                    is HomeNav.PracticeQuestion ->
                        PracticeQuestionScreen(
                            cardId = nav.cardId,
                            onBack = { homeNav = HomeNav.LearningPath },
                            onSessionComplete = { correct, total, stars, power ->
                                homeNav = HomeNav.PracticeResult(correct, total, stars, power)
                            },
                        )

                    is HomeNav.PracticeResult ->
                        PracticeResultScreen(
                            correctCount = nav.correctCount,
                            totalCount = nav.totalCount,
                            starRating = nav.starRating,
                            duckPowerEarned = nav.duckPowerEarned,
                            onReturnHome = { homeNav = HomeNav.LearningPath },
                        )
                }

                TopLevelDestination.Streak -> StreakScreen()
                TopLevelDestination.Mistakes -> MistakesScreen()
                TopLevelDestination.Profile -> ProfileScreen()
            }
        }
    }
}
