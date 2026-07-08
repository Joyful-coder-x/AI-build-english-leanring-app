package com.example.firsttest.data.repository

import com.example.firsttest.data.model.MistakeWord
import com.example.firsttest.data.remote.DbMistakeSense
import com.example.firsttest.data.remote.DbPronunciationRow
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

        val senseIds = rows.map { it.senseId }
        val masteries = Supabase.client
            .from("user_sense_mastery")
            .select(Columns.raw("sense_id, review_stage, next_due_at")) {
                filter { isIn("sense_id", senseIds) }
            }
            .decodeList<DbSenseMastery>()
            .associateBy { it.senseId }

        val ipaBySense = Supabase.client
            .from("pronunciations")
            .select(Columns.raw("sense_id, ipa_us")) {
                filter { isIn("sense_id", senseIds) }
            }
            .decodeList<DbPronunciationRow>()
            .mapNotNull { row -> row.senseId?.let { it to row.ipaUs } }
            .toMap()

        return rows.map { row ->
            val mastery = masteries[row.senseId]
            MistakeWord(
                wordId = row.senseId,
                headword = row.sense.words.headword,
                phonetic = ipaBySense[row.senseId].orEmpty(),
                definitionZh = row.sense.definitionZh,
                addedAt = row.firstWrongAt.take(10),
                reviewStage = mastery?.reviewStage ?: 0,
                nextReviewLabel = formatNextDue(mastery?.nextDueAt),
            )
        }
    }

    private fun formatNextDue(nextDueAt: String?): String {
        if (nextDueAt == null) return "Review today"
        return try {
            val due = Instant.parse(nextDueAt).atZone(ZoneId.systemDefault()).toLocalDate()
            val today = LocalDate.now(ZoneId.systemDefault())
            when (val days = ChronoUnit.DAYS.between(today, due)) {
                in Long.MIN_VALUE..0L -> "Review today"
                1L -> "Review tomorrow"
                else -> "Review in ${days} days"
            }
        } catch (_: Exception) {
            "Review today"
        }
    }
}
