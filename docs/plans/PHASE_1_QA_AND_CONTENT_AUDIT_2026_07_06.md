# Phase 1 QA And Content Audit - 2026-07-06

Scope: user-flow spot check plus Band 4 CSV audit for the Phase 1 prototype:
deep Levels 1-5, compact lightweight Levels 6-33, Band 4 -> 4.5 upgrade exam, logging,
level-up, unlock logic, and learner-facing IELTS readiness.

## User-Flow Findings

| Area | Finding | Fix applied |
|---|---|---|
| Main navigation | Profile could still open the legacy assessment overlay, which can call `finalize_placement` and conflict with the approved Level 1 start / upgrade-exam model. | `MainScreen.kt` no longer imports or routes to `AssessmentScreen`; `ProfileScreen.kt` no longer exposes a reassessment callback/button. |
| Profile UI | Profile had visible mojibake labels and icons, making the app look broken during demo. | Rebuilt `ProfileScreen.kt` with clean Phase 1 English labels, IELTS readiness text, streak, heatmap, items, account security, and sign-out. |
| Band upgrade exam | The real screen and ViewModel were already wired from the previous pass. | Reverified with Android unit tests and debug build. |
| Heavy review debt | When a learner had more than 20 due reviews, the round picker could still introduce up to 7 new words before reviews. | Added `202607060028_due_review_new_word_gate.sql`; due review counts over one full round set the new-word quota to zero. |
| Legacy assessment code | `ui/assessment` still exists as legacy/unpurpose code. | Left in repo but unreachable from the active shell. |

## Content Audit Method

- Data specialist sample: deterministic random 100 words from
  `backend/content-pipeline/constructed_data/band_4_0_v1/supabase_import`.
- English teacher sample: deterministic random 200 words from the same package,
  reviewing definition, Chinese definition, examples, forms, pronunciation,
  static questions, options, and level assignment.
- Full-package checks were also run for row counts, target-span presence,
  option correctness, per-level question counts, examples, forms, and
  pronunciation coverage.

## Data Findings

Before repair, the biggest issue was not row integrity; it was learner quality:

| Pattern | Count before | Why it matters | Fix applied |
|---|---:|---|---|
| Generic examples like `Today, learners reviewed market.` | 1,234 examples | Poor as an English-teacher sample; it teaches almost no usage for IELTS or college survival. | Updated `scripts/10_build_band4_content.py` fallback examples to POS-aware campus/daily-life sentences and regenerated Band 4 CSVs. |
| Static validator expected 3 questions for Level 1-5 | 225 Level 1-5 senses affected | Stale validator contradicted the deep Level 1-5 design, where reviewed content has 12 questions per sense. | Updated `scripts/11_validate_band4_content.py` to expect 12 questions for Levels 1-5 and 3 for compact Levels 6-33. |
| Option validator treated blank `target_sense_id` as invalid | 1,800 speaking/self-check options affected | The schema allows nullable `target_sense_id`; these options are not vocabulary distractors. | Validator now only requires a target sense when the field is populated. |
| Option validator assumed only `type_code=2` uses options | Level 1-5 speaking/self-check option questions affected | Eight-type Level 1-5 content uses option answers for several type codes. | Validator now keys off `answer_form == "option"`. |

After repair:

- `generic_review_examples`: 0
- Band 4 package validation: passed
- Words/senses: 1,465
- Examples: 2,930
- Questions: 6,420
- Options: 16,220
- Forms: 1,759
- Level 6-33 target range: 44-45 new senses per level

## Remaining Editorial Risks

These are not blockers for the Phase 1 engineering prototype, but they are real
content-quality TODOs before a public learner release.

| Issue | Full-package count after repair | Sample impact |
|---|---:|---|
| Translation-like English definitions, e.g. `the English expression meaning ...` | 115 | 7/100 data sample; 17/200 teacher sample |
| Very thin definitions | 98 | 5/100 data sample; 10/200 teacher sample |
| Missing noun/verb core forms | 87 | 4/100 data sample; 11/200 teacher sample |
| Missing pronunciation rows | 12 | 0 in the 100/200 samples from this run |
| One quote-fragment definition | 1 | 1/200 teacher sample |

Decision: keep these as P1/P2 editorial cleanup. They do not prevent the app
from demonstrating Levels 1-5, generated Level 6-33 practice, logging, unlocks,
or the Band 4 -> 4.5 exam.

## Verification Run

- `python backend/content-pipeline/scripts/10_build_band4_content.py`: passed
- `python backend/content-pipeline/scripts/11_validate_band4_content.py`: passed
- `.\gradlew.bat test`: passed
- `.\gradlew.bat assembleDebug`: passed
- Local disposable Postgres with Band 4 import:
  - `backend/supabase/manual/run_phase1_local_docker_verification.ps1`: passed
  - `verify_project_installation.sql`: READY, 137 passed, 0 warnings, 0 failures
  - `202607060025_combo_scope_practice_type_selection_test.sql`: passed
  - `202607060026_band_upgrade_exam_core_test.sql`: passed
  - `202607060027_band4_unlock_chain_test.sql`: passed
  - `202606240010_band4_content_runtime_test.sql`: passed
  - `202606250016_sentence_cloze_level_rounds_test.sql`: passed
  - `202606240009_spaced_review_practice_rounds_test.sql`: passed
  - `202607060029_phase1_practice_logging_evidence_test.sql`: passed
