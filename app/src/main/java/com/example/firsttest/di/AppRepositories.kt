package com.example.firsttest.di

import com.example.firsttest.data.repository.FakeMistakeRepository
import com.example.firsttest.data.repository.FakeUserRepository
import com.example.firsttest.data.repository.MistakeRepository
import com.example.firsttest.data.repository.PracticeRepository
import com.example.firsttest.data.repository.SupabasePracticeRepository
import com.example.firsttest.data.repository.UserRepository

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
 *   `profiles` table exists in Supabase (DATA_DESIGN.md §5).
 *
 * TODO PHASE 3: [practice].getDailyPractice() currently delegates to the fake
 *   card layout. Wire it to real level_progress + practice_sessions queries.
 */
object AppRepositories {

    /**
     * Shared user repository. Using a single instance means duck power updates
     * from [com.example.firsttest.ui.practice.PracticeViewModel] propagate to
     * Profile and Home screens within the same session.
     */
    val user: UserRepository = FakeUserRepository()

    /**
     * Practice repository. Questions come from Supabase; card layout is still fake.
     */
    val practice: PracticeRepository = SupabasePracticeRepository()

    /**
     * Mistake-word repository.
     * TODO PHASE 3: replace with SupabaseMistakeRepository once words are added
     *   to `mistake_words` after wrong answers in PracticeViewModel.
     */
    val mistakes: MistakeRepository = FakeMistakeRepository()
}
