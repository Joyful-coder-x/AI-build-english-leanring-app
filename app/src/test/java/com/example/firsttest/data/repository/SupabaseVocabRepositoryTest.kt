package com.example.firsttest.data.repository

import org.junit.Assert.assertEquals
import org.junit.Test

class SupabaseVocabRepositoryTest {

    @Test
    fun meaningChoiceUsesChineseDefinitionWhenAvailable() {
        assertEquals(
            "成年男子",
            meaningChoiceOptionText(
                definitionZh = "成年男子",
                definitionEn = "an adult male human",
            ),
        )
    }

    @Test
    fun meaningChoiceFallsBackToEnglishWhenChineseIsMissing() {
        assertEquals(
            "an adult male human",
            meaningChoiceOptionText(
                definitionZh = " ",
                definitionEn = "an adult male human",
            ),
        )
    }

    @Test
    fun databaseBandIdsMapToCurriculumScores() {
        assertEquals(4.0, bandScoreForId(1), 0.0)
        assertEquals(4.5, bandScoreForId(2), 0.0)
        assertEquals(8.0, bandScoreForId(9), 0.0)
    }

    @Test
    fun legacyNullSnapshotMetadataIsDerivedFromTypeCode() {
        assertEquals("keyboard", resolvedPracticeAnswerForm(null, 3))
        assertEquals(
            "sentence_cloze_typing",
            resolvedPracticeQuestionTypeKey(null, null, 3),
        )
    }

    @Test
    fun legacyNullOptionMetadataUsesRecognitionDefaults() {
        assertEquals("option", resolvedPracticeAnswerForm(null, 2))
        assertEquals(
            "option_recognition",
            resolvedPracticeQuestionTypeKey(null, null, 2),
        )
    }
}
