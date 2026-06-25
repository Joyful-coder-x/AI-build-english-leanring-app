package com.example.firsttest.data.repository

import com.example.firsttest.data.model.MistakeWord
import com.example.firsttest.data.remote.DbMistakeSense
import com.example.firsttest.data.remote.DbSenseMastery
import com.example.firsttest.data.remote.Supabase
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Reads active mistake words from `mistake_senses` joined with vocabulary tables. */
class SupabaseMistakeRepository : MistakeRepository {

    override suspend fun getMistakeWords(): List<MistakeWord> {
        val rows = Supabase.client
            .from("mistake_senses")
            .select(
                Columns.raw(
                    "sense_id, wrong_count, first_wrong_at, last_wrong_at, " +
                    "word_senses(definition_zh, part_of_speech, words(headword))"
                )
            ) {
                filter { eq("is_active", true) }
                order("last_wrong_at", Order.DESCENDING)
            }
            .decodeList<DbMistakeSense>()

        if (rows.isEmpty()) return emptyList()

        val masteries = Supabase.client
            .from("user_sense_mastery")
            .select(Columns.raw("sense_id, review_stage, next_due_at")) {
                filter { isIn("sense_id", rows.map { it.senseId }) }
            }
            .decodeList<DbSenseMastery>()
            .associateBy { it.senseId }

        return rows.map { row ->
            val mastery = masteries[row.senseId]
            MistakeWord(
                wordId         = row.senseId,
                headword       = row.sense.words.headword,
                phonetic       = "",   // TODO: add phonetic column to words table
                definitionZh   = row.sense.definitionZh,
                addedAt        = row.firstWrongAt.take(10),
                reviewStage    = mastery?.reviewStage ?: 0,
                nextReviewLabel = formatNextDue(mastery?.nextDueAt),
            )
        }
    }

    private fun formatNextDue(nextDueAt: String?): String {
        if (nextDueAt == null) return "今天复习"
        return try {
            val due  = Instant.parse(nextDueAt).atZone(ZoneId.systemDefault()).toLocalDate()
            val today = LocalDate.now(ZoneId.systemDefault())
            when (val days = ChronoUnit.DAYS.between(today, due)) {
                in Long.MIN_VALUE..0L -> "今天复习"
                1L -> "明天复习"
                else -> "${days}天后复习"
            }
        } catch (_: Exception) {
            "今天复习"
        }
    }
}
