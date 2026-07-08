package com.example.firsttest.data.remote

import com.example.firsttest.BuildConfig
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.storage.Storage

/**
 * Single app-wide Supabase client.
 *
 * URL + anon (publishable) key come from BuildConfig, which is populated from
 * local.properties (gitignored) — see app/build.gradle.kts. The anon key is
 * meant to ship in the client; access is governed server-side by RLS.
 *
 * Phase 4: the `Supabase*Repository` implementations of the existing repository
 * interfaces will use [client]. Until then the app keeps using the fake repos,
 * so adding this changes nothing at runtime.
 */
object Supabase {
    val client: SupabaseClient by lazy {
        createSupabaseClient(
            supabaseUrl = BuildConfig.SUPABASE_URL,
            supabaseKey = BuildConfig.SUPABASE_ANON_KEY,
        ) {
            install(Auth) {
                scheme = "kuakuaduck"
                host = "auth"
            }
            install(Postgrest)
            install(Storage)
        }
    }
}
