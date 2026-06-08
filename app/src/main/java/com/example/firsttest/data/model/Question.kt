package com.example.firsttest.data.model

/**
 * One practice question. Source: spec 2.2.3 (14 question types).
 *
 * Phase 2 renders typeCode 1 (keyboard fill-in) and typeCode 2 (MCQ 4-option).
 * All other type codes are fetched from Supabase but skipped by the UI until
 * their screens are built.
 *
 * [expectedTimeMs] is stored for every question so the speed bonus rule
 * (spec 2.2.3: 3★ within expected time → +5 鸭力值) can be enforced once a
 * per-question timer is added to PracticeQuestionScreen.
 * TODO PHASE 2: add a visible countdown timer and apply the +5 speed bonus.
 */
data class Question(
    val id: String,
    val typeCode: Int,             // 1 = keyboard fill-in, 2 = MCQ 4-option
    val promptHint: String,        // shown above the stem, e.g. "请选择正确答案"
    val stem: String,              // the sentence / question shown to the user
    val correctAnswer: String,     // type 1: full word; type 2: matching option text
    val translationZh: String,     // shown in the result panel after submission
    val options: List<String> = emptyList(),    // type 2 only; includes correctAnswer
    val expectedTimeMs: Int = 15_000,           // target solve time (spec 2.2.3 speed bonus)
)
