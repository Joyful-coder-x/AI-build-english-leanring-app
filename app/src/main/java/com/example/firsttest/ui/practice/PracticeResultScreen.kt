package com.example.firsttest.ui.practice

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Session summary shown after all questions are answered. Displays accuracy,
 * star rating, and duck power earned. [onReturnHome] navigates back to the
 * learning path.
 */
@Composable
fun PracticeResultScreen(
    correctCount: Int,
    totalCount: Int,
    starRating: Int,
    duckPowerEarned: Int,
    onReturnHome: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Spacer(Modifier.height(16.dp))

        Text(
            "练习完成！",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
        )

        // Stars
        Text(
            starsString(starRating),
            fontSize = 48.sp,
            textAlign = TextAlign.Center,
        )

        // Score card
        Card(Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                StatLine("✅  答对题数", "$correctCount / $totalCount")
                StatLine(
                    "📊  正确率",
                    if (totalCount > 0) "${(correctCount * 100 / totalCount)}%" else "—",
                )
                StatLine("⚡  获得鸭力值", "+$duckPowerEarned")
            }
        }

        // Encouragement text tied to star rating
        Text(
            encouragement(starRating),
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(Modifier.weight(1f))

        Button(onClick = onReturnHome, modifier = Modifier.fillMaxWidth()) {
            Text("返回首页")
        }
    }
}

@Composable
private fun StatLine(label: String, value: String) {
    androidx.compose.foundation.layout.Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge)
        Text(value, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Bold)
    }
}

private fun starsString(rating: Int): String {
    val r = rating.coerceIn(0, 3)
    return "★".repeat(r) + "☆".repeat(3 - r)
}

private fun encouragement(stars: Int): String = when (stars) {
    3 -> "太棒了！满分完成，鸭力值暴涨！🎉"
    2 -> "做得不错！继续练习，马上就能三星！💪"
    1 -> "继续加油！多练几遍，你一定可以的！🦆"
    else -> "没关系，每一次练习都是进步！重新来过！"
}
