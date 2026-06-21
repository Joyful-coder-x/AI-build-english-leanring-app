# Claude Code — Project Rules for KuaKua Duck

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

- Pipeline lives in `content_pipeline/`. Scripts run from the project root: `python content_pipeline/scripts/<script>.py`
- Output folders: `output/oxford_source/` (Oxford word lists), `output/level_001/` (all level 1 files + Supabase CSVs), `output/level_001/tts/` (TTS manifest), `output/reference/` (schema SQL etc.)
- `packages/level_001_packages.json` is the master content file. Always run `validate_packages.py` after editing it.
- UUID namespace in `config/pipeline_config.json` must never change — all UUIDs are deterministic from it.
- Pipeline output is **AI-draft**. Human QA is required before marking status `production`.

## Project status (as of 2026-06-15)

### Done
- [x] Phase 1: Home screen, DuckTitle, navigation skeleton (fake data)
- [x] Phase 2: Practice flow — PracticeQuestionScreen (Type 1 keyboard + Type 2 MCQ), combo bonus, 连胜 streak, 错词本 MistakesScreen
- [x] Supabase connected: questions + question_options read live from DB
- [x] Content pipeline: 20-word pilot batch (A1 People/Home/Food/Time/Actions) fully generated, validated, and imported into Supabase
- [x] File organisation: output/ subfolders, docs/ for planning MDs, PDFs to content_pipeline/reference/

### Still needed
- [ ] **Assessment / onboarding screen** (`ui/assessment/` exists but not wired) — determines starting level for new users
- [ ] **Onboarding flow** (`ui/onboarding/` exists but not wired)
- [ ] **Profile screen** — currently placeholder; needs real user stats from Supabase
- [ ] **SupabaseMistakeRepository** — mistake_words table in Supabase; currently only stored locally/fake
- [ ] **word_forms table** — created manually this session; not yet in the schema SQL; needs adding to `output/reference/schema_reference.sql`
- [ ] **TTS audio** — `pronunciation_tts_manifest.jsonl` exists but `synthesize_audio.py` not yet built; no audio files yet
- [ ] **Content: remaining ~2860 words** — pipeline ready; need to run batches of 20–50 words following `content_pipeline/PIPELINE_GUIDE.md`
- [ ] **RLS policies** — verify Supabase Row Level Security allows anonymous reads on words/questions tables
- [ ] **levels table** — needs data (level metadata rows) before level-select screen can work
