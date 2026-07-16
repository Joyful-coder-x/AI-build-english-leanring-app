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
    val containerColor = when {
        isReviewingCorrect        -> MaterialTheme.colorScheme.primaryContainer
        isSubmittedPositiveSelfCheck -> Color(0xFFE3F5E8)
        isReviewingWrongSelection -> MaterialTheme.colorScheme.errorContainer
        isSelected                -> MaterialTheme.colorScheme.secondaryContainer
        else                      -> MaterialTheme.colorScheme.surface
    }
    val contentColor = if (isSubmittedPositiveSelfCheck) {
        Color(0xFF1B5E20)
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
