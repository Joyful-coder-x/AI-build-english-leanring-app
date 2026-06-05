package com.example.firsttest.data.repository

import com.example.firsttest.data.remote.RemoteWord
import com.example.firsttest.data.remote.Supabase
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns

/**
 * Reads vocabulary words. For this E2E test the only implementation is
 * [SupabaseWordRepository], which talks to the real `public.words` table.
 */
interface WordRepository {
    suspend fun getWords(limit: Int = 50): List<RemoteWord>
}

/**
 * Fetches rows from `public.words` via the shared [Supabase.client]. Selects
 * only the columns the test displays; the rows are decoded into [RemoteWord].
 */
class SupabaseWordRepository : WordRepository {
    override suspend fun getWords(limit: Int): List<RemoteWord> =
        Supabase.client
            .from("words")
            .select(Columns.list("headword, phonetic, mnemonic, level_number")) {
                limit(limit.toLong())
            }
            .decodeList<RemoteWord>()
}
