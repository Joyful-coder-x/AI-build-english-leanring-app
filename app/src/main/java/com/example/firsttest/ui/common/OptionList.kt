package com.example.firsttest.ui.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.firsttest.data.model.MeaningChoiceOption

// A single "this is correct" color, used whether the option is objectively
// correct (meaning_choice, reading_comprehension, ...) or a self-assessed
// positive response (speaking/read-aloud self-check) -- both used to render
// with different colors (theme purple vs. hardcoded green), which read as
// inconsistent across question types.
private val CorrectAnswerContainerColor = Color(0xFFE3F5E8)
private val CorrectAnswerContentColor = Color(0xFF1B5E20)

@Composable
internal fun OptionList(
    options: List<MeaningChoiceOption>,
    selectedId: String?,
    reviewingCorrectId: String?,
    reviewingSelectedId: String?,
    onSelect: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { option ->
            OptionButton(
                option = option,
                isSelected = option.optionId == selectedId,
                isReviewingCorrect = option.optionId == reviewingCorrectId,
                isReviewingSelection = option.optionId == reviewingSelectedId,
                isReviewingWrongSelection = option.optionId == reviewingSelectedId &&
                        option.optionId != reviewingCorrectId,
                onClick = { onSelect(option.optionId) },
            )
        }
    }
}

@Composable
internal fun OptionButton(
    option: MeaningChoiceOption,
    isSelected: Boolean,
    isReviewingCorrect: Boolean,
    isReviewingSelection: Boolean,
    isReviewingWrongSelection: Boolean,
    onClick: () -> Unit,
) {
    val displayText = displayOptionText(option.text)
    val isPositiveSelfCheck = displayText in setOf(
        "I know it",
        "I know how to use",
        "I know how to read",
    )
    val isSubmittedPositiveSelfCheck = isPositiveSelfCheck &&
        (isReviewingSelection || isReviewingCorrect)
    val isCorrectHighlight = isReviewingCorrect || isSubmittedPositiveSelfCheck
    val containerColor = when {
        isCorrectHighlight        -> CorrectAnswerContainerColor
        isReviewingWrongSelection -> MaterialTheme.colorScheme.errorContainer
        isSelected                -> MaterialTheme.colorScheme.secondaryContainer
        else                      -> MaterialTheme.colorScheme.surface
    }
    val contentColor = if (isCorrectHighlight) {
        CorrectAnswerContentColor
    } else {
        MaterialTheme.colorScheme.onSurface
    }
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = containerColor,
            contentColor = contentColor,
        ),
    ) {
        Text(
            text = displayText,
            fontWeight = if (
                isSelected || isReviewingCorrect || isSubmittedPositiveSelfCheck
            ) FontWeight.SemiBold else FontWeight.Normal,
            fontSize = 14.sp,
        )
    }
}

internal fun displayOptionText(text: String): String = when (text) {
    "I need more practice." -> "I need hint"
    "I used it clearly." -> "I know how to use"
    else -> text
}
