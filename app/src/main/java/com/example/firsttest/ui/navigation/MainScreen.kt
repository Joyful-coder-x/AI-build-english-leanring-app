package com.example.firsttest.ui.navigation

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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.example.firsttest.ui.home.HomeScreen
import com.example.firsttest.ui.mistakes.MistakesScreen
import com.example.firsttest.ui.profile.ProfileScreen
import com.example.firsttest.ui.streak.StreakScreen

/**
 * The 4 bottom-nav destinations, in display order, matching the product
 * framework (v1.0 产品框架): 首页 · 连胜 · 错词本 · 我的.
 */
enum class TopLevelDestination(val label: String, val icon: String) {
    Home("首页", "🏠"),
    Streak("连胜", "🔥"),
    Mistakes("错词本", "📕"),
    Profile("我的", "🦆"),
}

/**
 * App shell: a [Scaffold] with a 4-tab [NavigationBar]. Selection is held in
 * local saveable state (no nav-graph dependency yet); deeper in-tab navigation
 * can be layered on per phase. Each tab renders its feature screen, fed the
 * scaffold's content padding so it sits above the bottom bar.
 */
@Composable
fun MainScreen(modifier: Modifier = Modifier) {
    var selected by rememberSaveable { mutableStateOf(TopLevelDestination.Home) }

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
                TopLevelDestination.Home -> HomeScreen()
                TopLevelDestination.Streak -> StreakScreen()
                TopLevelDestination.Mistakes -> MistakesScreen()
                TopLevelDestination.Profile -> ProfileScreen()
            }
        }
    }
}
