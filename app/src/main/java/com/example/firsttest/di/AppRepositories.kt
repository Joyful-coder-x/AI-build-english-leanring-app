package com.example.firsttest.di

import com.example.firsttest.data.remote.Supabase
import com.example.firsttest.data.repository.SupabaseMistakeRepository
import com.example.firsttest.data.repository.FakePracticeRepository
import com.example.firsttest.data.repository.FakeUserRepository
import com.example.firsttest.data.repository.FakeVocabRepository
import com.example.firsttest.data.repository.MistakeRepository
import com.example.firsttest.data.repository.PracticeRepository
import com.example.firsttest.data.repository.SupabaseAuthRepository
import com.example.firsttest.data.repository.SupabaseOnboardingRepository
import com.example.firsttest.data.repository.SupabasePracticeRepository
import com.example.firsttest.data.repository.SupabaseUserRepository
import com.example.firsttest.data.repository.SupabaseVocabRepository
import com.example.firsttest.data.repository.UserRepository
import com.example.firsttest.data.repository.VocabRepository

/**
 * Manual dependency injection — one shared instance of each repository.
 *
 * All ViewModels obtain repositories here so that state is consistent across
 * the app: e.g. duck power earned in [PracticeViewModel] immediately updates
 * [ProfileViewModel] and [HomeViewModel] via the shared [UserRepository.userFlow].
 *
 * Replace individual entries as each phase is completed:
 *
 * TODO PHASE 4: swap [user] for SupabaseUserRepository(Supabase.client) once the
 *   `profiles` table exists in Supabase (docs/architecture/DATA_MODEL_AND_CAPACITY.md §5).
 *
 * TODO PHASE 3: [practice].getDailyPractice() currently delegates to the fake
 *   card layout. Wire it to real level_progress + practice_sessions queries.
 */
object AppRepositories {

    // Set to false to use FakePracticeRepository (avoids Supabase calls in local dev).
    private const val USE_REAL_QUESTIONS = true

    /**
     * Shared user repository. Using a single instance means duck power updates
     * from [com.example.firsttest.ui.practice.PracticeViewModel] propagate to
     * Profile and Home screens within the same session.
     */
    val auth = SupabaseAuthRepository(Supabase.client)

    val user = SupabaseUserRepository(Supabase.client)

    val onboarding = SupabaseOnboardingRepository(Supabase.client)

    /**
     * Practice repository. Questions come from Supabase when [USE_REAL_QUESTIONS] is true;
     * card layout is always fake until Phase 3.
     */
    val practice: PracticeRepository =
        if (USE_REAL_QUESTIONS) SupabasePracticeRepository() else FakePracticeRepository()

    /** Mistake-word repository. Reads live from mistake_senses + user_sense_mastery. */
    val mistakes: MistakeRepository = SupabaseMistakeRepository()

    /**
     * Vocabulary content repository: levels and Meaning Choice questions.
     * Set USE_REAL_VOCAB = false to use FakeVocabRepository for offline dev.
     */
    private const val USE_REAL_VOCAB = true

    val vocab: VocabRepository =
        if (USE_REAL_VOCAB) SupabaseVocabRepository() else FakeVocabRepository()
}
