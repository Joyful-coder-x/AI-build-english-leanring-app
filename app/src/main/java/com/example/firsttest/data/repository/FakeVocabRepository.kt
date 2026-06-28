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
import java.time.LocalDate

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

    // ---- Level Practice (unified round — all 8 question types) -------------

    private var activeLevelRound: LevelPracticeRound? = null
    // Maps position → correct answer (option id or typed word)
    private val levelRoundCorrectAnswers = mutableMapOf<Int, String>()

    override suspend fun startLevelPracticeRound(levelNumber: Int): LevelPracticeRound {
        val questions = buildList {
            add(LevelPracticeQuestion(
                questionId      = "lp_${levelNumber}_1", senseId = "s1", position = 1,
                promptHint      = "选择正确的中文释义", stem = "achieve",
                answerForm      = "option", questionTypeKey = "meaning_choice",
                translationZh   = "实现；达到（目标或结果）",
                options         = listOf(
                    MeaningChoiceOption("o1a", "s1", "实现；达到（目标或结果）", true),
                    MeaningChoiceOption("o1b", "s2", "快速地移动到另一个地方", false),
                    MeaningChoiceOption("o1c", "s3", "为某事提供资金支持", false),
                    MeaningChoiceOption("o1d", "s4", "向一群人正式讲话", false),
                ).shuffled(),
            ))
            add(LevelPracticeQuestion(
                questionId      = "lp_${levelNumber}_2", senseId = "s2", position = 2,
                promptHint      = "填写空格中的目标词",
                stem            = "She worked hard to ___ her goals.",
                answerForm      = "keyboard", questionTypeKey = "sentence_cloze_typing",
                translationZh   = "实现；达到", options = emptyList(), letterCount = 7,
            ))
            add(LevelPracticeQuestion(
                questionId      = "lp_${levelNumber}_3", senseId = "s3", position = 3,
                promptHint      = "听完后选择你听到的单词", stem = "evidence",
                answerForm      = "option", questionTypeKey = "listening_choice",
                translationZh   = "证据；证明",
                options         = listOf(
                    MeaningChoiceOption("o3a", "s3", "evidence", true),
                    MeaningChoiceOption("o3b", "s5", "apparent", false),
                    MeaningChoiceOption("o3c", "s6", "essential", false),
                    MeaningChoiceOption("o3d", "s7", "efficient", false),
                ).shuffled(),
            ))
            add(LevelPracticeQuestion(
                questionId      = "lp_${levelNumber}_4", senseId = "s4", position = 4,
                promptHint      = "听完后拼写你听到的单词", stem = "significant",
                answerForm      = "keyboard", questionTypeKey = "listening_fill",
                translationZh   = "重要的；显著的", options = emptyList(), letterCount = 11,
            ))
            add(LevelPracticeQuestion(
                questionId      = "lp_${levelNumber}_5", senseId = "s1", position = 5,
                promptHint      = "朗读以下单词，然后选择自评结果", stem = "achieve",
                answerForm      = "option", questionTypeKey = "speaking_repeat",
                translationZh   = "实现；达到",
                options         = listOf(
                    MeaningChoiceOption("sp5a", "s1", "✅ 我清晰地说出来了", true),
                    MeaningChoiceOption("sp5b", "s1", "🤔 大概说对了", true),
                    MeaningChoiceOption("sp5c", "s1", "❌ 我没说出来", false),
                ),
            ))
            add(LevelPracticeQuestion(
                questionId      = "lp_${levelNumber}_6", senseId = "s3", position = 6,
                promptHint      = "用英语描述这个词的含义，然后自评",
                stem            = "证据；有助于证明某事为真的事实或信息",
                answerForm      = "option", questionTypeKey = "open_speaking",
                translationZh   = "evidence",
                options         = listOf(
                    MeaningChoiceOption("sp6a", "s3", "✅ 我说出了核心含义", true),
                    MeaningChoiceOption("sp6b", "s3", "🤔 我说了部分内容", true),
                    MeaningChoiceOption("sp6c", "s3", "❌ 我没有说出来", false),
                ),
            ))
            add(LevelPracticeQuestion(
                questionId      = "lp_${levelNumber}_7", senseId = "s1", position = 7,
                promptHint      = "写出 achieve 的名词形式",
                stem            = "His ___ in the exam was outstanding. (achieve → 名词)",
                answerForm      = "keyboard", questionTypeKey = "word_form",
                translationZh   = "实现；成就 (achievement)", options = emptyList(), letterCount = 11,
            ))
            add(LevelPracticeQuestion(
                questionId      = "lp_${levelNumber}_8", senseId = "s3", position = 8,
                promptHint      = "阅读短文，回答问题",
                stem            = "Scientists have found new evidence that climate change is accelerating faster than expected. " +
                    "The data, collected over 20 years, provides significant proof of rising global temperatures.\n\n" +
                    "问题：文中 "evidence" 的中文含义最接近？",
                answerForm      = "option", questionTypeKey = "reading_comprehension",
                translationZh   = "证据；证明",
                options         = listOf(
                    MeaningChoiceOption("rc8a", "s3", "证据；证明", true),
                    MeaningChoiceOption("rc8b", "s5", "论点；争议", false),
                    MeaningChoiceOption("rc8c", "s6", "假设；猜测", false),
                    MeaningChoiceOption("rc8d", "s7", "实验；测试", false),
                ).shuffled(),
            ))
        }

        levelRoundCorrectAnswers.clear()
        questions.forEach { q ->
            when {
                q.answerForm == "keyboard" -> levelRoundCorrectAnswers[q.position] = when (q.questionTypeKey) {
                    "sentence_cloze_typing" -> "achieve"
                    "listening_fill"        -> "significant"
                    "word_form"             -> "achievement"
                    else                    -> ""
                }
                else -> q.options.firstOrNull { it.isCorrect }
                    ?.let { levelRoundCorrectAnswers[q.position] = it.optionId }
            }
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
        val correct = levelRoundCorrectAnswers[position] ?: ""
        val isCorrect = answer.trim().lowercase() == correct.trim().lowercase()
        return LevelPracticeAnswerResult(
            isCorrect       = isCorrect,
            answerOutcome   = if (isCorrect) "full_correct" else "wrong",
            correctOptionId = correct.ifBlank { null },
            correctAnswer   = correct.ifBlank { null },
            learningState   = null,
            reviewStage     = null,
        )
    }

    override suspend fun getPracticeSessionDates(recentDays: Int): List<LocalDate> {
        val today = LocalDate.now()
        return listOf(0, 1, 2, 4, 5, 7, 8, 9, 12, 14, 15, 19, 21, 28, 35, 42, 50, 60, 70, 80)
            .map { daysAgo -> today.minusDays(daysAgo.toLong()) }
            .filter { !it.isBefore(today.minusDays(recentDays.toLong())) }
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
