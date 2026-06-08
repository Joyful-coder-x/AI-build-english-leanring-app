package com.example.firsttest.data.repository

import com.example.firsttest.data.model.MistakeWord

/**
 * In-memory fake 错词本 data.
 *
 * Five words at different Ebbinghaus review stages so the screen renders all
 * badge states. Headwords match the Supabase fake words table (word_1…word_5).
 *
 * TODO PHASE 3: replace with SupabaseMistakeRepository.
 */
class FakeMistakeRepository : MistakeRepository {
    override suspend fun getMistakeWords(): List<MistakeWord> = listOf(
        MistakeWord(
            wordId = "w1",
            headword = "word_1",
            phonetic = "/phonetic_1/",
            definitionZh = "单词1的中文释义（名词）",
            addedAt = "2026-06-08",
            reviewStage = 0,
            nextReviewLabel = "今天复习",
        ),
        MistakeWord(
            wordId = "w2",
            headword = "word_2",
            phonetic = "/phonetic_2/",
            definitionZh = "单词2的中文释义（动词）",
            addedAt = "2026-06-07",
            reviewStage = 1,
            nextReviewLabel = "明天复习",
        ),
        MistakeWord(
            wordId = "w3",
            headword = "word_3",
            phonetic = "/phonetic_3/",
            definitionZh = "单词3的中文释义（形容词）",
            addedAt = "2026-06-05",
            reviewStage = 2,
            nextReviewLabel = "3天后复习",
        ),
        MistakeWord(
            wordId = "w4",
            headword = "word_4",
            phonetic = "/phonetic_4/",
            definitionZh = "单词4的中文释义（副词）",
            addedAt = "2026-06-01",
            reviewStage = 3,
            nextReviewLabel = "7天后复习",
        ),
        MistakeWord(
            wordId = "w5",
            headword = "word_5",
            phonetic = "/phonetic_5/",
            definitionZh = "单词5的中文释义（名词）",
            addedAt = "2026-05-24",
            reviewStage = 4,
            nextReviewLabel = "15天后复习",
        ),
    )
}
