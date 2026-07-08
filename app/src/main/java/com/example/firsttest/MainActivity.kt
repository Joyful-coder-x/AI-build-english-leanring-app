package com.example.firsttest

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.firsttest.data.remote.Supabase
import com.example.firsttest.ui.auth.LoginScreen
import com.example.firsttest.ui.navigation.MainScreen
import com.example.firsttest.ui.onboarding.OnboardingScreen
import com.example.firsttest.ui.session.AppSessionState
import com.example.firsttest.ui.session.AppSessionViewModel
import com.example.firsttest.ui.theme.KuaKuaTheme
import io.github.jan.supabase.auth.handleDeeplinks

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        Supabase.client.handleDeeplinks(intent)
        setContent {
            KuaKuaTheme {
                AppContent()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        Supabase.client.handleDeeplinks(intent)
    }
}

@Composable
private fun AppContent(
    viewModel: AppSessionViewModel = viewModel(factory = AppSessionViewModel.Factory),
) {
    val session by viewModel.uiState.collectAsState()
    when (val state = session) {
        AppSessionState.RestoringSession,
        AppSessionState.LoadingBootstrap -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
        AppSessionState.SignedOut -> LoginScreen()
        is AppSessionState.QuestionnairePending -> OnboardingScreen(
            bootstrap = state.bootstrap,
            onCompleted = viewModel::retry,
        )
        is AppSessionState.Authenticated -> MainScreen(onSignOut = viewModel::signOut)
        is AppSessionState.Error -> {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    text = "Unable to load account",
                    style = MaterialTheme.typography.headlineSmall,
                    textAlign = TextAlign.Center,
                )
                Text(
                    text = state.message,
                    modifier = Modifier.padding(top = 12.dp, bottom = 24.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                )
                Button(
                    onClick = viewModel::retry,
                    modifier = Modifier.fillMaxWidth().widthIn(max = 320.dp),
                ) {
                    Text("Retry")
                }
                Button(
                    onClick = viewModel::signOut,
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .fillMaxWidth()
                        .widthIn(max = 320.dp),
                ) {
                    Text("Sign out")
                }
            }
        }
    }
}
