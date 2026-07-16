package com.example.firsttest.data.repository

import com.example.firsttest.data.remote.DbBandUpgradeExam
import com.example.firsttest.data.remote.DbBandUpgradeOption
import com.example.firsttest.data.remote.DbBandUpgradeQuestion
import com.example.firsttest.data.remote.DbOverallAssessmentAttempt
import com.example.firsttest.data.remote.DbOverallAssessmentOption
import com.example.firsttest.data.remote.DbOverallAssessmentQuestion
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

    @Test
    fun openSpeakingMetadataIsDerivedFromTypeCode() {
        assertEquals(
            "open_speaking",
            resolvedPracticeQuestionTypeKey(null, null, 106),
        )
    }

    @Test
    fun bandUpgradeExamPreservesServerShuffledOptionOrder() {
        // sort_order is a static DB column that is always 1 for the correct
        // answer; the RPC's real randomized presentation order is the list
        // order itself. The mapper must not re-sort by sort_order, or the
        // correct answer always ends up first.
        val exam = DbBandUpgradeExam(
            attemptId = "attempt-1",
            sourceBand = 4.0,
            targetBand = 4.5,
            status = "in_progress",
            questionCount = 1,
            questions = listOf(
                DbBandUpgradeQuestion(
                    position = 1,
                    questionId = "q1",
                    questionTypeKey = "meaning_choice",
                    category = "new_word",
                    answerForm = "option",
                    options = listOf(
                        DbBandUpgradeOption(id = "1", text = "voice", sortOrder = 2),
                        DbBandUpgradeOption(id = "2", text = "body", sortOrder = 3),
                        DbBandUpgradeOption(id = "3", text = "ear", sortOrder = 1),
                        DbBandUpgradeOption(id = "4", text = "beard", sortOrder = 4),
                    ),
                ),
            ),
        )

        assertEquals(
            listOf("voice", "body", "ear", "beard"),
            exam.toBandUpgradeExam().questions.single().options.map { it.text },
        )
    }

    @Test
    fun overallAssessmentPreservesServerShuffledOptionOrder() {
        val attempt = DbOverallAssessmentAttempt(
            attemptId = "attempt-1",
            status = "in_progress",
            questionCount = 1,
            questions = listOf(
                DbOverallAssessmentQuestion(
                    position = 1,
                    questionId = "q1",
                    questionTypeKey = "meaning_choice",
                    skillCategory = "reading",
                    answerForm = "option",
                    options = listOf(
                        DbOverallAssessmentOption(id = "1", text = "voice", sortOrder = 2),
                        DbOverallAssessmentOption(id = "2", text = "body", sortOrder = 3),
                        DbOverallAssessmentOption(id = "3", text = "ear", sortOrder = 1),
                        DbOverallAssessmentOption(id = "4", text = "beard", sortOrder = 4),
                    ),
                ),
            ),
        )

        assertEquals(
            listOf("voice", "body", "ear", "beard"),
            attempt.toOverallAssessment().questions.single().options.map { it.text },
        )
    }
}
