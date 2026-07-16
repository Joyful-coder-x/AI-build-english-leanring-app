package com.example.firsttest.data.repository

import com.example.firsttest.data.model.Level
import com.example.firsttest.data.model.BandUpgradeAnswerResult
import com.example.firsttest.data.model.BandUpgradeExam
import com.example.firsttest.data.model.BandUpgradeQuestion
import com.example.firsttest.data.model.LevelPracticeAnswerResult
import com.example.firsttest.data.model.LevelPracticeQuestion
import com.example.firsttest.data.model.LevelPracticeRound
import com.example.firsttest.data.model.LevelWordStatus
import com.example.firsttest.data.model.MeaningChoiceOption
import com.example.firsttest.data.model.MeaningChoiceQuestion
import com.example.firsttest.data.model.OverallAssessment
import com.example.firsttest.data.model.OverallAssessmentAnswerResult
import com.example.firsttest.data.model.OverallAssessmentQuestion
import com.example.firsttest.data.model.PracticeAnswerResult
import com.example.firsttest.data.model.PracticeRound
import com.example.firsttest.data.model.PracticeRoundResult
import com.example.firsttest.data.remote.DbCompletePracticeRoundParams
import com.example.firsttest.data.remote.DbBandUpgradeExam
import com.example.firsttest.data.remote.DbCompleteBandUpgradeExamParams
import com.example.firsttest.data.remote.DbCompleteMeaningChoiceSessionParams
import com.example.firsttest.data.remote.DbLevel
import com.example.firsttest.data.remote.DbLevelProgress
import com.example.firsttest.data.remote.DbGetLevelWordStatusesParams
import com.example.firsttest.data.remote.DbExampleHintRow
import com.example.firsttest.data.remote.DbLevelWordStatus
import com.example.firsttest.data.remote.DbLevelSenseRow
import com.example.firsttest.data.remote.DbPracticeAnswerResult
import com.example.firsttest.data.remote.DbPracticeRound
import com.example.firsttest.data.remote.DbPracticeRoundResult
import com.example.firsttest.data.remote.DbBandUpgradeAnswerResult
import com.example.firsttest.data.remote.DbCompleteOverallAssessmentParams
import com.example.firsttest.data.remote.DbOverallAssessmentAttempt
import com.example.firsttest.data.remote.DbSaveBandUpgradeAnswerParams
import com.example.firsttest.data.remote.DbSaveOverallAssessmentAnswerParams
import com.example.firsttest.data.remote.DbSavePracticeAnswerParams
import com.example.firsttest.data.remote.DbSaveMeaningChoiceAnswerParams
import com.example.firsttest.data.remote.DbSenseHintRow
import com.example.firsttest.data.remote.DbSessionStartedAt
import com.example.firsttest.data.remote.DbStartPracticeRoundParams
import com.example.firsttest.data.remote.DbStartBandUpgradeExamParams
import com.example.firsttest.data.remote.Supabase
import com.example.firsttest.data.model.SenseHint
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.rpc
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

internal fun resolvedPracticeAnswerForm(answerForm: String?, typeCode: Int): String =
    answerForm?.takeIf { it.isNotBlank() }
        ?: if (typeCode == 3) "keyboard" else "option"

internal fun resolvedPracticeQuestionTypeKey(
    questionTypeKey: String?,
    answerForm: String?,
    typeCode: Int,
): String = questionTypeKey?.takeIf { it.isNotBlank() }
    ?: when (typeCode) {
        101  -> "meaning_choice"
        102  -> "sentence_cloze_typing"
        103  -> "listening_choice"
        104  -> "listening_fill"
        105  -> "speaking_repeat"
        106  -> "open_speaking"
        107  -> "word_form"
        108  -> "reading_comprehension"
        3    -> "sentence_cloze_typing"   // legacy type_code before migration 019
        else -> if (answerForm == "keyboard") "keyboard_recall" else "option_recognition"
    }

/**
 * Real [VocabRepository] backed by Supabase.
 *
 * [getMeaningChoiceQuestionsForLevel] is generic: pass any level number and it
 * fetches a pool of senses assigned to that level, shuffles them, picks up to
 * [limit] targets, and pairs each with 3 distractor senses from the same pool.
 * Distractors prefer a different word (headword) than the target to avoid
 * confusing the learner.
 *
 * Requires authenticated Supabase session (RLS: `for select to authenticated`
 * on words, word_senses, level_sense_assignments, levels).
 *
 */
class SupabaseVocabRepository : VocabRepository {

    override suspend fun startPracticeRound(levelNumber: Int): PracticeRound {
        val row = Supabase.client.postgrest.rpc(
            "start_practice_round",
            DbStartPracticeRoundParams(levelNumber),
        ).decodeAs<DbPracticeRound>()

        return PracticeRound(
            roundId = row.roundId,
            levelNumber = row.levelNumber,
            questions = row.questions.map { question ->
                MeaningChoiceQuestion(
                    questionId = question.questionId,
                    levelNumber = row.levelNumber,
                    senseId = question.senseId,
                    position = question.position,
                    promptHint = question.promptHint,
                    stem = question.stem,
                    wordText = question.stem,
                    partOfSpeech = "",
                    definitionZh = question.translationZh,
                    typeCode = question.typeCode,
                    questionTypeKey = resolvedPracticeQuestionTypeKey(
                        question.questionTypeKey,
                        question.answerForm,
                        question.typeCode,
                    ),
                    answerForm = resolvedPracticeAnswerForm(
                        question.answerForm,
                        question.typeCode,
                    ),
                    expectedTimeMs = question.expectedTimeMs,
                    attemptCount = question.attemptCount,
                    hintUsed = question.hintUsed,
                    revealedAnswer = question.revealedAnswer,
                    options = question.options.map { option ->
                        MeaningChoiceOption(
                            optionId = option.optionId,
                            senseId = "",
                            text = option.optionText,
                            isCorrect = false,
                        )
                    },
                )
            },
        )
    }

    override suspend fun savePracticeAnswer(
        roundId: String,
        position: Int,
        answer: String,
        responseTimeMs: Int,
    ): PracticeAnswerResult {
        val row = Supabase.client.postgrest.rpc(
            "save_practice_answer",
            DbSavePracticeAnswerParams(
                roundId = roundId,
                position = position,
                answer = answer,
                responseTimeMs = responseTimeMs,
            ),
        ).decodeAs<DbPracticeAnswerResult>()
        val answerOutcome = row.answerOutcome
            ?: if (row.isCorrect == true) "full_correct" else "wrong"
        return PracticeAnswerResult(
            isCorrect = row.isCorrect,
            correctOptionId = row.correctOptionId.orEmpty(),
            answerOutcome = answerOutcome,
            action = row.action,
            attemptCount = row.attemptCount,
            letterCount = row.letterCount,
            feedback = row.feedback.orEmpty(),
            revealedAnswer = row.revealedAnswer,
        )
    }

    override suspend fun completePracticeRound(roundId: String): PracticeRoundResult {
        val row = Supabase.client.postgrest.rpc(
            "complete_practice_round",
            DbCompletePracticeRoundParams(roundId),
        ).decodeAs<DbPracticeRoundResult>()
        val effectiveCorrect = if (row.fullCorrectCount > 0) row.fullCorrectCount else row.correctCount
        val effectiveTotal   = if (row.questionCount > 0) row.questionCount
                               else (row.fullCorrectCount + row.assistedCorrectCount + row.remediationCount + row.wrongCount)
        return PracticeRoundResult(
            correctCount          = effectiveCorrect,
            questionCount         = effectiveTotal,
            starRating            = row.starRating,
            duckPowerEarned       = row.duckPowerEarned,
            levelCompleted        = row.levelCompleted ?: false,
            fullCorrectCount      = effectiveCorrect,
            assistedCorrectCount  = row.assistedCorrectCount,
            weightedAccuracy      = row.weightedAccuracy,
        )
    }

    override suspend fun getLevelWordStatuses(levelNumber: Int): List<LevelWordStatus> =
        Supabase.client.postgrest.rpc(
            "get_level_word_statuses",
            DbGetLevelWordStatusesParams(levelNumber),
        ).decodeAs<List<DbLevelWordStatus>>().map { row ->
            LevelWordStatus(
                senseId = row.senseId,
                word = row.word,
                definitionZh = row.definitionZh,
                status = row.status,
                wrongCount = row.wrongCount,
                isDue = row.isDue,
            )
        }

    override suspend fun startBandUpgradeExam(targetBand: Double): BandUpgradeExam {
        val row = Supabase.client.postgrest.rpc(
            "start_band_upgrade_exam",
            DbStartBandUpgradeExamParams(targetBand),
        ).decodeAs<DbBandUpgradeExam>()
        return row.toBandUpgradeExam()
    }

    override suspend fun saveBandUpgradeAnswer(
        attemptId: String,
        position: Int,
        answer: String,
        responseTimeMs: Int,
    ): BandUpgradeAnswerResult {
        val row = Supabase.client.postgrest.rpc(
            "save_band_upgrade_answer",
            DbSaveBandUpgradeAnswerParams(
                attemptId = attemptId,
                position = position,
                answer = answer,
                responseTimeMs = responseTimeMs,
            ),
        ).decodeAs<DbBandUpgradeAnswerResult>()
        return BandUpgradeAnswerResult(
            alreadySaved = row.alreadySaved,
            position = row.position,
            isCorrect = row.isCorrect,
        )
    }

    override suspend fun completeBandUpgradeExam(attemptId: String): BandUpgradeExam {
        val row = Supabase.client.postgrest.rpc(
            "complete_band_upgrade_exam",
            DbCompleteBandUpgradeExamParams(attemptId),
        ).decodeAs<DbBandUpgradeExam>()
        return row.toBandUpgradeExam()
    }

    override suspend fun startOverallAssessment(): OverallAssessment {
        val row = Supabase.client.postgrest.rpc("start_overall_assessment")
            .decodeAs<DbOverallAssessmentAttempt>()
        return row.toOverallAssessment()
    }

    override suspend fun saveOverallAssessmentAnswer(
        attemptId: String,
        position: Int,
        answer: String,
        responseTimeMs: Int,
    ): OverallAssessmentAnswerResult {
        val row = Supabase.client.postgrest.rpc(
            "save_overall_assessment_answer",
            DbSaveOverallAssessmentAnswerParams(
                attemptId = attemptId,
                position = position,
                answer = answer,
                responseTimeMs = responseTimeMs,
            ),
        ).decodeAs<com.example.firsttest.data.remote.DbOverallAssessmentAnswerResult>()
        return OverallAssessmentAnswerResult(
            alreadySaved = row.alreadySaved,
            position = row.position,
            isCorrect = row.isCorrect,
        )
    }

    override suspend fun completeOverallAssessment(attemptId: String): OverallAssessment {
        val row = Supabase.client.postgrest.rpc(
            "complete_overall_assessment",
            DbCompleteOverallAssessmentParams(attemptId),
        ).decodeAs<DbOverallAssessmentAttempt>()
        return row.toOverallAssessment()
    }

    override suspend fun saveMeaningChoiceAnswer(
        levelNumber: Int,
        senseId: String,
        selectedSenseId: String,
        isCorrect: Boolean,
        responseTimeMs: Int,
    ) {
        Supabase.client.postgrest.rpc(
            "save_meaning_choice_answer",
            DbSaveMeaningChoiceAnswerParams(
                levelNumber     = levelNumber,
                senseId         = senseId,
                selectedSenseId = selectedSenseId,
                isCorrect       = isCorrect,
                responseTimeMs  = responseTimeMs,
            ),
        )
    }

    override suspend fun completeMeaningChoiceSession(
        levelNumber: Int,
        correctCount: Int,
        totalCount: Int,
        starRating: Int,
        duckPowerEarned: Int,
    ) {
        Supabase.client.postgrest.rpc(
            "complete_meaning_choice_session",
            DbCompleteMeaningChoiceSessionParams(
                levelNumber     = levelNumber,
                correctCount    = correctCount,
                totalCount      = totalCount,
                starRating      = starRating,
                duckPowerEarned = duckPowerEarned,
            ),
        )
    }

    override suspend fun getLevels(numbers: List<Int>): List<Level> {
        val requestedNumbers = numbers.toSet()
        val rows = Supabase.client
            .from("levels")
            .select(Columns.list("level_number, band_id, title, is_coming_soon"))
            .decodeList<DbLevel>()

        val progressMap = Supabase.client
            .from("user_level_progress")
            .select(
                Columns.list(
                    "level_number, is_unlocked, is_completed, progress, " +
                        "best_star_rating, completed_session_count"
                )
            )
            .decodeList<DbLevelProgress>()
            .associateBy { it.levelNumber }

        return rows
            .asSequence()
            .filter { it.levelNumber in requestedNumbers }
            .sortedBy { it.levelNumber }
            .map { row ->
            val progress = progressMap[row.levelNumber]
            Level(
                number = row.levelNumber,
                title = row.title,
                bandScore = bandScoreForId(row.bandId),
                isUnlocked = progress?.isUnlocked ?: (row.levelNumber == 1),
                isCompleted = progress?.isCompleted ?: false,
                completionRate = progress?.progress?.toFloat() ?: 0f,
                bestStarRating = progress?.bestStarRating ?: 0,
                completedSessionCount = progress?.completedSessionCount ?: 0,
                isComingSoon = row.isComingSoon,
            )
        }.toList()
    }

    override suspend fun getMeaningChoiceQuestionsForLevel(
        levelNumber: Int,
        limit: Int,
    ): List<MeaningChoiceQuestion> {
        // Fetch a larger pool so we have distractors after picking targets.
        val poolSize = (limit * 5).coerceAtLeast(30)

        val rows = Supabase.client
            .from("level_sense_assignments")
            .select(
                Columns.list(
                    "sense_id, level_number, " +
                    "word_senses(id, part_of_speech, definition_en, definition_zh, word_id, " +
                    "words(id, headword))"
                )
            ) {
                filter {
                    eq("level_number", levelNumber)
                    eq("placement_type", "new")
                }
                limit(poolSize.toLong())
            }
            .decodeList<DbLevelSenseRow>()

        if (rows.size < 4) return emptyList()

        val pool = rows.shuffled()
        val targets = pool.take(limit)

        return targets.mapNotNull { target ->
            val distractors = pool
                .filter { row ->
                    row.senseId != target.senseId &&
                    row.sense.wordId != target.sense.wordId &&
                    row.sense.definitionEn != target.sense.definitionEn
                }
                .take(3)

            if (distractors.size < 3) return@mapNotNull null

            val correctOption = MeaningChoiceOption(
                optionId  = "opt_${target.senseId}",
                senseId   = target.senseId,
                text      = meaningChoiceOptionText(
                    definitionZh = target.sense.definitionZh,
                    definitionEn = target.sense.definitionEn,
                ),
                isCorrect = true,
            )
            val distractorOptions = distractors.map { d ->
                MeaningChoiceOption(
                    optionId  = "opt_${d.senseId}",
                    senseId   = d.senseId,
                    text      = meaningChoiceOptionText(
                        definitionZh = d.sense.definitionZh,
                        definitionEn = d.sense.definitionEn,
                    ),
                    isCorrect = false,
                )
            }

            MeaningChoiceQuestion(
                questionId     = UUID.randomUUID().toString(),
                levelNumber    = levelNumber,
                senseId        = target.senseId,
                promptHint     = "Choose the matching English word.",
                stem           = target.sense.words.headword,
                wordText       = target.sense.words.headword,
                partOfSpeech   = target.sense.partOfSpeech,
                definitionZh   = target.sense.definitionZh,
                options        = (listOf(correctOption) + distractorOptions).shuffled(),
                correctOptionId = correctOption.optionId,
            )
        }
    }

    override suspend fun startLevelPracticeRound(levelNumber: Int): LevelPracticeRound {
        val row = Supabase.client.postgrest.rpc(
            "start_practice_round",
            DbStartPracticeRoundParams(levelNumber),
        ).decodeAs<DbPracticeRound>()
        return LevelPracticeRound(
            roundId = row.roundId,
            levelNumber = row.levelNumber,
            questions = row.questions.map { q ->
                LevelPracticeQuestion(
                    questionId     = q.questionId,
                    senseId        = q.senseId,
                    position       = q.position,
                    promptHint     = q.promptHint,
                    stem           = q.stem,
                    answerForm     = resolvedPracticeAnswerForm(q.answerForm, q.typeCode),
                    questionTypeKey = resolvedPracticeQuestionTypeKey(
                        q.questionTypeKey,
                        q.answerForm,
                        q.typeCode,
                    ),
                    typeCode       = q.typeCode,
                    expectedTimeMs = q.expectedTimeMs,
                    attemptCount   = q.attemptCount,
                    hintUsed       = q.hintUsed,
                    letterCount    = q.letterCount,
                    revealedAnswer = q.revealedAnswer,
                    audioText      = q.audioText,
                    translationZh  = q.translationZh,
                    isAnswered     = q.isAnswered,
                    options        = q.options.map { opt ->
                        MeaningChoiceOption(
                            optionId  = opt.optionId,
                            senseId   = "",
                            text      = opt.optionText,
                            isCorrect = false,
                        )
                    },
                )
            },
        )
    }

    override suspend fun saveLevelPracticeAnswer(
        roundId: String,
        position: Int,
        answer: String,
        responseTimeMs: Int,
    ): LevelPracticeAnswerResult {
        val row = Supabase.client.postgrest.rpc(
            "save_practice_answer",
            DbSavePracticeAnswerParams(
                roundId        = roundId,
                position       = position,
                answer         = answer,
                responseTimeMs = responseTimeMs,
            ),
        ).decodeAs<DbPracticeAnswerResult>()
        // Migration 015+ returns answer_outcome; older DB only returns is_correct.
        val answerOutcome = row.answerOutcome
            ?: if (row.isCorrect == true) "full_correct" else "wrong"
        return LevelPracticeAnswerResult(
            isCorrect       = row.isCorrect,
            answerOutcome   = answerOutcome,
            correctOptionId = row.correctOptionId,
            correctAnswer   = row.correctAnswer,
            learningState   = row.learningState,
            reviewStage     = row.reviewStage,
            action          = row.action,
            attemptCount    = row.attemptCount,
            letterCount     = row.letterCount,
            feedback        = row.feedback.orEmpty(),
            revealedAnswer  = row.revealedAnswer,
        )
    }

    override suspend fun getSenseHint(senseId: String): SenseHint {
        val sense = Supabase.client
            .from("word_senses")
            .select(Columns.list("definition_zh")) {
                filter { eq("id", senseId) }
                limit(1)
            }
            .decodeSingle<DbSenseHintRow>()

        val example = Supabase.client
            .from("examples")
            .select(Columns.list("sentence_en")) {
                filter { eq("sense_id", senseId) }
                limit(1)
            }
            .decodeSingleOrNull<DbExampleHintRow>()

        return SenseHint(
            definitionZh = sense.definitionZh,
            exampleSentence = example?.sentenceEn,
        )
    }

    override suspend fun getPracticeSessionDates(recentDays: Int): List<LocalDate> {
        val cutoff = LocalDate.now().minusDays(recentDays.toLong())
        val rows = Supabase.client
            .from("practice_sessions")
            .select(Columns.list("started_at")) {
                filter {
                    eq("status", "completed")
                    gte("started_at", cutoff.toString())
                }
                limit(500)
            }
            .decodeList<DbSessionStartedAt>()
        return rows.mapNotNull { row ->
            runCatching {
                Instant.parse(row.startedAt)
                    .atZone(ZoneId.systemDefault())
                    .toLocalDate()
            }.getOrNull()
        }.distinct()
    }
}

internal fun meaningChoiceOptionText(
    definitionZh: String,
    definitionEn: String,
): String = definitionZh.trim().ifBlank { definitionEn.trim() }

internal fun bandScoreForId(bandId: Int): Double = when (bandId) {
    1 -> 4.0
    2 -> 4.5
    3 -> 5.0
    4 -> 5.5
    5 -> 6.0
    6 -> 6.5
    7 -> 7.0
    8 -> 7.5
    9 -> 8.0
    else -> error("Unknown band id: $bandId")
}

internal fun DbBandUpgradeExam.toBandUpgradeExam(): BandUpgradeExam =
    BandUpgradeExam(
        attemptId = attemptId,
        sourceBand = sourceBand,
        targetBand = targetBand,
        status = status,
        questionCount = questionCount,
        correctCount = correctCount,
        accuracy = accuracy,
        passed = passed,
        categoryCounts = categoryCounts,
        questions = questions.map { question ->
            BandUpgradeQuestion(
                position = question.position,
                questionId = question.questionId,
                questionTypeKey = question.questionTypeKey,
                category = question.category,
                answerForm = question.answerForm,
                stem = question.stem.orEmpty(),
                promptHint     = "Choose the matching English word.",
                translationZh = question.translationZh.orEmpty(),
                headword = question.headword.orEmpty(),
                options = question.options
                    .map { option ->
                        MeaningChoiceOption(
                            optionId = option.id,
                            senseId = "",
                            text = option.text,
                            isCorrect = false,
                        )
                    },
                answered = question.answered,
                isCorrect = question.isCorrect,
            )
        },
    )

internal fun DbOverallAssessmentAttempt.toOverallAssessment(): OverallAssessment =
    OverallAssessment(
        attemptId = attemptId,
        status = status,
        questionCount = questionCount,
        correctCount = correctCount,
        listeningCorrect = listeningCorrect,
        listeningTotal = listeningTotal,
        readingCorrect = readingCorrect,
        readingTotal = readingTotal,
        speakingCorrect = speakingCorrect,
        speakingTotal = speakingTotal,
        spellingCorrect = spellingCorrect,
        spellingTotal = spellingTotal,
        listeningBand = listeningBand,
        readingBand = readingBand,
        speakingBand = speakingBand,
        spellingBand = spellingBand,
        overallBand = overallBand,
        questions = questions.map { question ->
            OverallAssessmentQuestion(
                position = question.position,
                questionId = question.questionId,
                questionTypeKey = question.questionTypeKey,
                skillCategory = question.skillCategory,
                answerForm = question.answerForm,
                stem = question.stem.orEmpty(),
                promptHint = question.promptHint.orEmpty(),
                translationZh = question.translationZh.orEmpty(),
                headword = question.headword.orEmpty(),
                options = question.options
                    .map { option ->
                        MeaningChoiceOption(
                            optionId = option.id,
                            senseId = "",
                            text = option.text,
                            isCorrect = false,
                        )
                    },
                answered = question.answered,
                isCorrect = question.isCorrect,
            )
        },
    )
