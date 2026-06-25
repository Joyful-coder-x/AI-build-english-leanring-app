package com.example.firsttest.data.repository

import com.example.firsttest.data.model.Level
import com.example.firsttest.data.model.LevelPracticeAnswerResult
import com.example.firsttest.data.model.LevelPracticeQuestion
import com.example.firsttest.data.model.LevelPracticeRound
import com.example.firsttest.data.model.LevelWordStatus
import com.example.firsttest.data.model.MeaningChoiceOption
import com.example.firsttest.data.model.MeaningChoiceQuestion
import com.example.firsttest.data.model.PracticeAnswerResult
import com.example.firsttest.data.model.PracticeRound
import com.example.firsttest.data.model.PracticeRoundResult

/**
 * In-memory [VocabRepository] for offline dev and unit tests.
 * Mirrors the real repo's contract: Level 1 unlocked, 2-5 locked,
 * and [getMeaningChoiceQuestionsForLevel] works for any level number.
 */
class FakeVocabRepository : VocabRepository {

    private var activeRound: PracticeRound? = null
    private var correctCount = 0

    override suspend fun startPracticeRound(levelNumber: Int): PracticeRound =
        activeRound ?: PracticeRound(
            roundId = "fake-round-$levelNumber",
            levelNumber = levelNumber,
            questions = getMeaningChoiceQuestionsForLevel(levelNumber, 3)
                .mapIndexed { index, question ->
                    question.copy(position = index + 1)
                },
        ).also {
            activeRound = it
            correctCount = 0
        }

    override suspend fun savePracticeAnswer(
        roundId: String,
        position: Int,
        answer: String,
        responseTimeMs: Int,
    ): PracticeAnswerResult {
        val question = requireNotNull(activeRound)
            .questions.first { it.position == position }
        val isCorrect = answer == question.correctOptionId
        if (isCorrect) correctCount++
        return PracticeAnswerResult(
            isCorrect = isCorrect,
            correctOptionId = question.correctOptionId,
            answerOutcome = if (isCorrect) "full_correct" else "wrong",
        )
    }

    override suspend fun completePracticeRound(roundId: String): PracticeRoundResult {
        val round = requireNotNull(activeRound)
        val result = PracticeRoundResult(
            correctCount = correctCount,
            questionCount = round.questions.size,
            starRating = com.example.firsttest.ui.practice.calcStars(
                correctCount,
                round.questions.size,
            ),
            duckPowerEarned = correctCount,
            levelCompleted = false,
        )
        activeRound = null
        return result
    }

    override suspend fun getLevelWordStatuses(levelNumber: Int): List<LevelWordStatus> =
        getMeaningChoiceQuestionsForLevel(levelNumber, 3).mapIndexed { index, question ->
            LevelWordStatus(
                senseId = question.senseId,
                word = question.wordText,
                definitionZh = question.definitionZh,
                status = if (index == 0) "复习中" else "未学习",
                wrongCount = 0,
                isDue = false,
            )
        }

    override suspend fun saveMeaningChoiceAnswer(
        levelNumber: Int, senseId: String, selectedSenseId: String,
        isCorrect: Boolean, responseTimeMs: Int,
    ) { /* no-op */ }

    override suspend fun completeMeaningChoiceSession(
        levelNumber: Int, correctCount: Int, totalCount: Int,
        starRating: Int, duckPowerEarned: Int,
    ) { /* no-op */ }

    override suspend fun getLevels(numbers: List<Int>): List<Level> =
        numbers.sorted().map { n ->
            Level(
                number = n,
                title = "Level $n",
                bandScore = bandScoreForLevel(n),
                isUnlocked = n == 1,
            )
        }

    override suspend fun getMeaningChoiceQuestionsForLevel(
        levelNumber: Int,
        limit: Int,
    ): List<MeaningChoiceQuestion> = listOf(
        buildQuestion(
            qId = "mc_${levelNumber}_1", levelNumber = levelNumber,
            senseId = "s1", word = "achieve", pos = "verb",
            correctText = "实现；达到（目标或结果）",
            correctId = "o1", defZh = "实现；达到（目标或结果）",
            distractors = listOf(
                Triple("o2", "s2", "快速地从一个地方移动到另一个地方"),
                Triple("o3", "s3", "为某事提供资金支持"),
                Triple("o4", "s4", "向一群人正式讲话"),
            ),
        ),
        buildQuestion(
            qId = "mc_${levelNumber}_2", levelNumber = levelNumber,
            senseId = "s5", word = "evidence", pos = "noun",
            correctText = "证据；证明",
            correctId = "o5", defZh = "证据；证明",
            distractors = listOf(
                Triple("o6", "s6", "对刺激产生的突然强烈反应"),
                Triple("o7", "s7", "发现或学习新事物的过程"),
                Triple("o8", "s8", "双方之间的正式书面协议"),
            ),
        ),
        buildQuestion(
            qId = "mc_${levelNumber}_3", levelNumber = levelNumber,
            senseId = "s9", word = "significant", pos = "adjective",
            correctText = "重要的；显著的",
            correctId = "o9", defZh = "重要的；显著的",
            distractors = listOf(
                Triple("o10", "s10", "与自然力量和现象的研究有关的"),
                Triple("o11", "s11", "与另一件事同时发生或存在的"),
                Triple("o12", "s12", "频繁变化且难以预测的"),
            ),
        ),
    ).take(limit)

    private fun buildQuestion(
        qId: String,
        levelNumber: Int,
        senseId: String,
        word: String,
        pos: String,
        correctText: String,
        correctId: String,
        defZh: String,
        distractors: List<Triple<String, String, String>>,
    ): MeaningChoiceQuestion {
        val correct = MeaningChoiceOption(correctId, senseId, correctText, true)
        val others = distractors.map { (id, sid, text) ->
            MeaningChoiceOption(id, sid, text, false)
        }
        return MeaningChoiceQuestion(
            questionId = qId,
            levelNumber = levelNumber,
            senseId = senseId,
            promptHint = "选择正确的中文释义",
            stem = word,
            wordText = word,
            partOfSpeech = pos,
            definitionZh = defZh,
            options = (listOf(correct) + others).shuffled(),
            correctOptionId = correctId,
        )
    }

    // ---- Level Practice (unified round supporting option + cloze) ----------

    private var activeLevelRound: LevelPracticeRound? = null
    // Maps position → correct option id (option questions only)
    private val levelRoundCorrectIds = mutableMapOf<Int, String>()

    override suspend fun startLevelPracticeRound(levelNumber: Int): LevelPracticeRound {
        val questions = getMeaningChoiceQuestionsForLevel(levelNumber, 3)
            .mapIndexed { index, q ->
                LevelPracticeQuestion(
                    questionId      = q.questionId,
                    senseId         = q.senseId,
                    position        = index + 1,
                    promptHint      = q.promptHint,
                    stem            = q.stem,
                    answerForm      = "option",
                    questionTypeKey = "option_recognition",
                    translationZh   = q.definitionZh,
                    options         = q.options,
                )
            }
        levelRoundCorrectIds.clear()
        questions.forEach { q ->
            q.options.firstOrNull { it.isCorrect }?.let { levelRoundCorrectIds[q.position] = it.optionId }
        }
        return LevelPracticeRound(
            roundId     = "fake-lp-$levelNumber",
            levelNumber = levelNumber,
            questions   = questions,
        ).also { activeLevelRound = it }
    }

    override suspend fun saveLevelPracticeAnswer(
        roundId: String,
        position: Int,
        answer: String,
        responseTimeMs: Int,
    ): LevelPracticeAnswerResult {
        val correctId = levelRoundCorrectIds[position] ?: ""
        val isCorrect = answer == correctId
        return LevelPracticeAnswerResult(
            isCorrect       = isCorrect,
            answerOutcome   = if (isCorrect) "full_correct" else "wrong",
            correctOptionId = correctId.ifBlank { null },
            correctAnswer   = null,
            learningState   = null,
            reviewStage     = null,
        )
    }

    private fun bandScoreForLevel(levelNumber: Int): Double = when {
        levelNumber <= 54 -> 4.0
        levelNumber <= 81 -> 4.5
        levelNumber <= 99 -> 5.0
        levelNumber <= 126 -> 5.5
        levelNumber <= 144 -> 6.0
        levelNumber <= 162 -> 6.5
        levelNumber <= 180 -> 7.0
        levelNumber <= 210 -> 7.5
        else -> 8.0
    }
}
