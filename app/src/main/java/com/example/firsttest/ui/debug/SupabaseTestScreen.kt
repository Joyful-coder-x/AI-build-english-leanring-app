package com.example.firsttest.ui.debug

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.firsttest.data.remote.RemoteWord
import com.example.firsttest.data.repository.SupabaseWordRepository
import com.example.firsttest.data.repository.WordRepository
import kotlinx.coroutines.CancellationException

/** UI state for the throwaway Supabase connectivity test. */
private sealed interface WordsTestState {
    data object Loading : WordsTestState
    data class Error(val message: String) : WordsTestState
    data class Success(val words: List<RemoteWord>) : WordsTestState
}

/**
 * TEMPORARY end-to-end test screen. Proves the app can read `public.words` from
 * Supabase through [Supabase.client]. Delete this screen (and the data/remote
 * RemoteWord + WordRepository helpers) once connectivity is confirmed.
 *
 * NOTE: this performs a real network call — it only works on a device/emulator,
 * not in a @Preview.
 */
@Composable
fun SupabaseTestScreen(
    repository: WordRepository = SupabaseWordRepository(),
    modifier: Modifier = Modifier,
) {
    var state by remember { mutableStateOf<WordsTestState>(WordsTestState.Loading) }

    LaunchedEffect(Unit) {
        state = try {
            WordsTestState.Success(repository.getWords())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            WordsTestState.Error(e.message ?: e.toString())
        }
    }

    Scaffold(modifier = modifier) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Supabase E2E 测试 · public.words",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )

            when (val s = state) {
                is WordsTestState.Loading ->
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }

                is WordsTestState.Error ->
                    Text(
                        "❌ 读取失败:\n${s.message}",
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium,
                    )

                is WordsTestState.Success -> {
                    Text(
                        "✅ 连接成功 — 读到 ${s.words.size} 行",
                        color = MaterialTheme.colorScheme.primary,
                        style = MaterialTheme.typography.titleMedium,
                    )
                    if (s.words.isEmpty()) {
                        Text(
                            "返回 0 行。表为空,或 RLS 策略未允许 anon 角色 SELECT。",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(s.words) { word -> WordRow(word) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WordRow(word: RemoteWord) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                "${word.headword}  ·  Lv${word.levelNumber}",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "音标 phonetic: ${word.phonetic ?: "—"}",
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                "助记 mnemonic: ${word.mnemonic ?: "—"}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
