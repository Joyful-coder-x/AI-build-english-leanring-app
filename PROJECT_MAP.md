# Project Map — KuaKua Duck 夸夸鸭AI

Three categories. Every file in this project belongs to exactly one.

---

## ENVIRONMENT (`_env/`)

Build infrastructure. **Must stay at project root** — Android/Gradle requires it.
See `_env/ENVIRONMENT_INDEX.md` for the full list.

Quick list: `gradlew`, `gradlew.bat`, `gradle/`, `gradle.properties`,
`settings.gradle.kts`, `build.gradle.kts`, `local.properties`, `.git/`, `.gitignore`,
`.idea/`, `.gradle/`, `CLAUDE.md`, `.claude/`, `.agents/`, `.github/`

---

## TEMP (`_temp/`)

Deleted 2026-07-07. Everything this held was superseded/reference-only per this
map's own classification (old architecture/database docs, superseded plan
drafts, the old pipeline chain, one-time SQL scripts, the legacy 40Q
assessment, the old band-exam placeholder). `backend/content-pipeline/legacy-pilot/`
was moved back to its canonical path (CLAUDE.md requires it to stay archived
there) before the rest of `_temp/` was removed. Nothing else was recovered —
if you need any of that content again, pull it from git history before this
commit.

### Android files still IN source tree but needing work (not moved — build would break)

These are in their normal Android package locations but are incomplete or use fake data.
They are "temp" in intent — do not treat them as done.

| File | Status | What it needs |
|---|---|---|
| `ui/mistakes/MistakesScreen.kt` | Needs real backend | Wire to SupabaseMistakeRepository |
| `ui/mistakes/MistakesViewModel.kt` | Uses FakeMistakeRepository | Replace with real repository |
| `ui/scratch/ScratchCardScreen.kt` | Partially implemented | Full persistence + eligibility logic |
| `ui/scratch/ScratchCardViewModel.kt` | Partial | Full persistence |
| `data/repository/FakeMistakeRepository.kt` | Dev/test only | Used by tests; do not delete |
| `data/repository/FakePracticeRepository.kt` | Dev toggle | Used by AppRepositories toggle |
| `data/repository/FakeUserRepository.kt` | Dev/test only | Used by tests |
| `data/repository/FakeVocabRepository.kt` | Dev toggle | Used by AppRepositories toggle |
| `ui/practice/PracticeQuestionScreen.kt` | Only meaning_choice rendered | Add 7 more question type panels |

---

## CURRENT (project root, `app/`, `backend/`, `docs/`, `support/`)

Everything below is 100% working or is the active controlling document.
Do not add files here unless they pass their acceptance criteria.

### Android source — `app/src/main/java/.../`

```
MainActivity.kt                        ← active shell, session routing
di/AppRepositories.kt                  ← dependency injection

data/model/                            ← all domain models (current)
data/remote/DbModels.kt                ← Supabase DTO models
data/remote/Supabase.kt                ← Supabase client init
data/repository/
  AuthRepository.kt                    ← interface
  UserRepository.kt                    ← interface
  OnboardingRepository.kt              ← interface
  VocabRepository.kt                   ← interface
  PracticeRepository.kt                ← interface
  MistakeRepository.kt                 ← interface
  SupabaseAuthRepository.kt            ← WORKING
  SupabaseUserRepository.kt            ← WORKING
  SupabaseOnboardingRepository.kt      ← WORKING
  SupabaseVocabRepository.kt           ← WORKING
  SupabasePracticeRepository.kt        ← WORKING (meaning_choice path)
  SupabaseMistakeRepository.kt         ← exists, needs verification

ui/auth/LoginScreen.kt                 ← WORKING
ui/auth/LoginViewModel.kt              ← WORKING
ui/session/AppSessionViewModel.kt      ← WORKING
ui/onboarding/OnboardingScreen.kt      ← WORKING
ui/onboarding/OnboardingViewModel.kt   ← WORKING
ui/navigation/MainScreen.kt            ← WORKING
ui/home/HomeScreen.kt                  ← WORKING
ui/home/HomeViewModel.kt               ← WORKING
ui/home/HomeNav.kt                     ← WORKING
ui/home/BandUpgradeExamScreen.kt       ← WORKING (backend RPCs exist)
ui/home/BandUpgradeExamViewModel.kt    ← WORKING
ui/home/OverallAssessmentScreen.kt     ← WORKING (added 2026-07-07, backend RPCs exist)
ui/home/OverallAssessmentViewModel.kt  ← WORKING (added 2026-07-07)
ui/level/LevelProgressScreen.kt        ← WORKING
ui/level/LevelProgressViewModel.kt     ← WORKING
ui/level/LevelPracticeScreen.kt        ← WORKING (all 8 question types render since 2026-07-07)
ui/level/LevelPracticeViewModel.kt     ← WORKING
ui/practice/PracticeQuestionScreen.kt  ← PARTIAL (only meaning_choice rendered)
ui/practice/PracticeResultScreen.kt    ← WORKING
ui/practice/PracticeResultViewModel.kt ← WORKING
ui/practice/PracticeViewModel.kt       ← WORKING
ui/streak/StreakScreen.kt              ← WORKING
ui/streak/StreakViewModel.kt            ← WORKING
ui/profile/ProfileScreen.kt            ← WORKING (rebuilt 2026-07-06)
ui/profile/ProfileViewModel.kt         ← WORKING
ui/profile/AccountViewModel.kt         ← WORKING
ui/common/PlaceholderScreen.kt         ← utility (keep)
ui/theme/                              ← Material3 theme (keep)
```

### Unit tests — `app/src/test/java/.../`

All test files in `ui/` (except `ui/assessment/` which moved to `_temp`) are current.

### Backend Supabase — `backend/supabase/`

```
migrations/                            ← ALL migrations are current (001–026, 028–035)
                                         Apply in filename order. Never rename.
                                         029 fixes review-before-new-sense round
                                         assembly priority (2026-07-07 audit).
                                         030 login tracking, 031 awards, 032 skill_category,
                                         033 coming_soon flag, 034 skill scoring fn,
                                         035 overall assessment (034 before 035: dependency).
                                         None of 029-035 applied to hosted Supabase yet —
                                         only verified via local Docker harness.
tests/                                 ← ALL test SQL files are current
manual/
  run_phase1_local_docker_verification.ps1   ← use for local Docker testing
  run_phase1_target_verification.ps1         ← use for hosted Supabase testing
```

### Backend Content Pipeline — `backend/content-pipeline/`

```
scripts/
  10_build_band4_content.py            ← ACTIVE: regenerates Band 4 CSVs
  11_validate_band4_content.py         ← ACTIVE: validates Band 4 CSVs
constructed_data/
  band_4_0_v1/supabase_import/         ← ACTIVE: import package for Phase 1
  levels_001_005/                      ← referenced by scripts 10 and 11 (keep)
input/ielts_topic_map.csv              ← referenced by script 10 (keep)
DATA_CONSTRUCTION_SPEC.md              ← active spec
README.md
legacy-pilot/                          ← archived per CLAUDE.md; do not use for production imports
```

### Docs — `docs/`

```
MASTER_PROJECT_HANDOFF_PLAN.md        ← engineering baseline doc (2026-06-24)
PHASE_1_CONSTRUCTION_MASTERPLAN.md    ← PRIMARY PLAN (2026-07-07) ← START HERE
README.md

content/
  CONTENT_CONSTRUCTION_BRIEF.md       ← content pipeline guide
  WORD_RESEARCH_AND_REVIEW_GUIDE.md   ← editorial review workflow

plans/
  BAND_UPGRADE_EXAM_PLAN.md           ← controlling Band exam spec
  LEVEL_1_5_FINAL_PROTOTYPE_GOAL.md   ← Level 1-5 done criteria
  LEVEL_AND_SPACED_REVIEW_FINAL_DESIGN.md  ← spaced review rules (approved)
  PHASE_1_COMBO_CONTENT_AND_BAND_EXAM_PLAN.md  ← Phase 1 scope
  PHASE_1_MANUAL_DEMO_SCRIPT.md       ← manual QA script
  PHASE_1_QA_AND_CONTENT_AUDIT_2026_07_06.md  ← latest audit
  PHASE_1_TARGET_EVIDENCE_TEMPLATE.md ← evidence checklist template
  TODO_AND_LEGACY_INVENTORY.md        ← open items
  README.md
```

### Support — `support/`

```
Scoring System Design for IELTS-Style Bands.pdf       ← REQUIRED for Feature I
Evidence-Based Vocabulary Mastery and Review Scheduling System.pdf  ← reference
Recommended Scoring Plan for KuaKua Duck Levels.pdf   ← reference
```

---

## What to build next

Follow `docs/PHASE_1_CONSTRUCTION_MASTERPLAN.md` Section 16 (Implementation Sequence), starting at Step 1 (backend stabilization).
