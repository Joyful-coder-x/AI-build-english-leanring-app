# Claude Code — Project Rules for KuaKua Duck

> Full file index, legacy boundaries, architecture rules, and coding conventions: `docs/CODEBASE_INDEX.md`

## IDE & tooling

- **Android Studio only.** Do not suggest VS Code extensions, VS Code launch configs, or any non-Android-Studio tooling for the Android project.
- The content pipeline scripts run in a terminal (PowerShell or Bash), not inside any IDE.
- Gradle JDK is pinned to `D:\Coding\Android\jbr` (Android Studio's bundled JBR 21) via `gradle.properties`. Do not change this path.

## Android app rules

- Language: Kotlin. UI: Jetpack Compose. Architecture: MVVM + Repository.
- All data access goes through Repository interfaces (`UserRepository`, `SupabasePracticeRepository`, etc.). ViewModels never call Supabase directly.
- Fake repositories (`Fake*Repository`) stay in the codebase for offline dev/testing. Do not delete them.
- Do not add features, abstractions, or error handling beyond what the current phase requires.
- Do not write comments that explain *what* code does — only write a comment when the *why* is non-obvious.

## Content pipeline rules

- The active pipeline lives in `backend/content-pipeline/`. Run numbered scripts from the project root with `python backend/content-pipeline/scripts/<script>.py`.
- Reviewed intermediate files and Supabase imports live under `backend/content-pipeline/constructed_data/`.
- The first 20-word generator is archived under `backend/content-pipeline/legacy-pilot/`; do not use it for production imports.
- Pipeline output is **AI-draft**. Human QA is required before marking status `production`.

## Supabase deployment workflow

- The intended deployment path is: local edit -> local verification -> commit -> push to GitHub `master` -> GitHub Actions runs `supabase db push`.
- GitHub Actions workflow: `.github/workflows/supabase-db.yml`; it uses repository secrets `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, `SUPABASE_PROJECT_ID`, and `SUPABASE_DATABASE_URL`.
- SQL schema/RPC/RLS changes must be added as forward-only files in `backend/supabase/migrations/`; do not edit migrations that may already have been applied to hosted Supabase.
- Normal pushes deploy migrations only. The `Import Band 4 content` job is intentionally skipped unless the workflow is manually run with `import_band4=true`.
- Do not run the Band 4 CSV import automatically or casually. It is content-changing and should happen only after a database backup and explicit operator intent.
- The 2026-07-08 Actions success did not deploy migrations because the workflow used the wrong CLI workdir and scanned an empty nested migrations directory. The workflow must use `--workdir backend`; hosted migration history must be baselined before automatic pushes are treated as operational.

### Curriculum terminology

- Use **word**, not "unit", in curriculum plans and user-facing descriptions.
- A word means `lemma + part of speech + selected definition`. The same spelling with a different definition counts as a different word, including when taught in another level.
- Curriculum hierarchy: several words make up a level, and several levels make up an IELTS band.
- A level has approximately 80 total word placements: 45-55 new words, with the remainder made up of forms, collocations, and reviewed/context words.

## Project status (as of 2026-07-01)

### Approved progression change (2026-06-24)

- The initial placement assessment is legacy behavior and must be removed.
- New users start at Level 1 after onboarding.
- Internal `band` values are displayed to learners as `雅思 # 分难度`.
- Every difficulty transition uses an always-open 40-question upgrade exam.
- Passing requires at least 37/40; attempts are unlimited.
- Canonical rules: `docs/plans/BAND_UPGRADE_EXAM_PLAN.md`.

### Done
- [x] Phase 1: Home screen, DuckTitle, navigation skeleton (fake data)
- [x] Phase 2: Practice flow — PracticeQuestionScreen (Type 1 keyboard + Type 2 MCQ), combo bonus, 连胜 streak, 错词本 MistakesScreen
- [x] Supabase connected: questions + question_options read live from DB
- [x] Content pipeline: 20-word pilot batch (A1 People/Home/Food/Time/Actions) fully generated, validated, and imported into Supabase
- [x] File organisation: backend systems grouped together, documentation indexed by purpose, and source-reference PDFs stored with the content pipeline.
- [x] **LevelPractice round system** — migrations 015 + 016 (weighted scoring, cloze support); `LevelPracticeViewModel` + `LevelPracticeScreen` in `ui/level/`; all level taps route here; `answer_outcome_enum`, spaced-review mastery writes, duck power formula all wired.
- [x] **Codebase index** — `docs/CODEBASE_INDEX.md`: complete file map with active/legacy categorization, architecture rules, coding conventions, scope boundaries.
- [x] **All 8 question types** — `LevelPracticeScreen` renders type-specific UI for all types: meaning_choice (MCQ), sentence_cloze_typing (keyboard), listening_choice/listening_fill (audio panel), speaking_repeat/open_speaking (self-assess), word_form (keyboard), reading_comprehension (passage card). `FakeVocabRepository` generates all 8 types for offline dev.
- [x] **Profile heatmap** — GitHub-style 12-week × 7-day contribution grid on Profile screen; `VocabRepository.getPracticeSessionDates()` reads live data from `practice_sessions` in both `SupabaseVocabRepository` and `FakeVocabRepository`.
- [x] **Android TTS for listening types** — device TTS (`TextToSpeech`, `Locale.US`) reads the target word aloud on question load; replay button shown; `listening_fill` shows Chinese definition as context instead (word not in stem by RPC design).
- [x] **Auth + onboarding flow wired** — `AppSessionViewModel` drives app routing: `LoginScreen` (signed out), `OnboardingScreen` (questionnaire pending), `MainScreen` (authenticated), error state with retry. Deep link scheme `kuakuaduck://auth` registered in AndroidManifest for Supabase magic links.
- [x] **LevelProgressScreen** — intermediate screen between Home and `LevelPracticeScreen`; level tap goes here first (shows level info / word count), then routes to practice.
- [x] **SpellingCorrection UX** — `ShowingClozeAnswer` + `ClozeMemoryRetype` merged into single `SpellingCorrection` state; shows letter-by-letter diff of wrong vs. correct answer; retry stays client-side until perfect (no backend hit); Chinese hint toggle in Answering state.
- [x] **SupabaseMistakeRepository live** — wired in `AppRepositories`; reads from `mistake_senses` + `user_sense_mastery`.
- [x] **Migration 016 additions** — staged type-3 cloze dispatcher (`save_practice_answer` wraps `finalize_practice_answer`); `near_meaning_count` + `duck_points` columns on `practice_round_questions`; keyboard trigger fix.

### Still needed
- [ ] Apply migrations 015 + 016 to hosted Supabase; verify they run cleanly.
- [ ] **RLS policies** — verify Supabase Row Level Security allows anonymous reads on words/questions tables.
- [ ] **Profile screen** — heatmap reads live session data; duck power, radar, and streak stats still need backend queries in `SupabaseUserRepository`.
- [ ] **StreakScreen** — UI exists; needs live Supabase data (streak counters via `refresh_user_profile` RPC).
- [ ] **word_forms table** — verify current Supabase migration schema and import compatibility before next production load.
- [ ] **TTS audio pipeline** — `pronunciation_tts_manifest.jsonl` exists but `synthesize_audio.py` not yet built; no pre-generated audio files (listening questions currently use Android device TTS as a placeholder).
- [ ] **Content: remaining curriculum** — continue with the reviewed numbered workflow documented in `backend/content-pipeline/README.md`.
- [ ] **levels table** — needs data rows before `LevelProgressScreen` can show real level info.
- [ ] **AssessmentIntroScreen + MeaningChoiceScreen** — deleted as legacy; `AssessmentScreen` is retained for reassessment flow from Profile.
