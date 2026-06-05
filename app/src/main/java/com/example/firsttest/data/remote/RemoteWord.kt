package com.example.firsttest.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * A row read from `public.words` in Supabase — only the columns this E2E test
 * displays. Extra columns in the table are ignored (the Supabase client's JSON
 * decoder ignores unknown keys), so this does not need to mirror the full table.
 *
 * snake_case DB columns are mapped to Kotlin names via [SerialName].
 */
@Serializable
data class RemoteWord(
    val headword: String,
    val phonetic: String? = null,
    val mnemonic: String? = null,
    @SerialName("level_number") val levelNumber: Int,
)
