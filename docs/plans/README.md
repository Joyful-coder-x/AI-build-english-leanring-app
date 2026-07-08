# Planning Docs

This folder contains active implementation plans only. Each plan has a distinct
owner area so work does not split across overlapping documents.

| Plan | Owns | Does not own |
|---|---|---|
| `ACCOUNT_AND_USER_DATA_PLAN.md` | Auth, account state, profile/private user tables, RLS, onboarding persistence, Android session wiring | Spaced review, practice-round selection, upgrade-exam rules |
| `LEVEL_AND_SPACED_REVIEW_FINAL_DESIGN.md` | Level completion, sense mastery, spaced review, fixed practice rounds, mistake-notebook ownership | Auth/session flow, upgrade-exam pass/unlock rules |
| `BAND_UPGRADE_EXAM_PLAN.md` | Always-open 40-question upgrade exams, pass rule, exam snapshots, difficulty unlock transaction | Daily level practice and account bootstrap |
| `ENGINEERING_QUALITY_FOLLOW_UP.md` | Cross-cutting quality, testing, DI/navigation boundaries, source hygiene | Product-specific data models or user flows |
| `DATABASE_TABLE_CLEANUP_AND_QUESTION_DATA_MAP.md` | Current table organization, cleanup candidates, and where 8-type question data belongs | Product behavior rules or Android UI design |
| `TODO_AND_LEGACY_INVENTORY.md` | Living inventory of real TODOs vs. intentionally-deferred/legacy code (`Fake*Repository`, retired screens, stale phase comments) | Design rationale for *why* a feature should exist — see the owning plan for that |
| `PHASE_1_PM_OPTIONS_AND_DECISIONS.md` | Product-management options, pros/cons, and selected Phase 1 prototype direction | Low-level engineering task tracking or SQL/API implementation details |
| `PHASE_1_COMBO_CONTENT_AND_BAND_EXAM_PLAN.md` | Active combo scope: Band 4 package as demo data source, deep Levels 1-5, compact lightweight Levels 6-33, and Band 4 -> 4.5 upgrade exam | Older Level 1-5-only scope when it conflicts with the combo goal |
| `PHASE_1_QA_AND_CONTENT_AUDIT_2026_07_06.md` | Current user-flow and Band 4 data audit findings, fixes applied, and remaining editorial risks | Product scope decisions or target-DB deployment steps |
| `PHASE_1_MANUAL_DEMO_SCRIPT.md` | Repeatable manual demo script and operator evidence checklist for the full Phase 1 path | Implementation design or backlog ownership |
| `PHASE_1_TARGET_EVIDENCE_TEMPLATE.md` | Fill-in proof template for hosted Supabase verification, Android build/install evidence, fresh-user manual flow, and known demo limitations | Product scope decisions or implementation design |

Checkpoint plan:

- `LEVEL_1_5_FINAL_PROTOTYPE_GOAL.md`: near-term final prototype checkpoint
  for proving Levels 1-5 end to end with real practice, logging, level-up, and
  unlock persistence. It does not own the full two-band proof of concept, Band
  4.5 content, or public launch readiness.
- `LEVEL_1_5_IMPLEMENTATION_CHECKLIST.md`: marked worklist from the current
  repository scan showing what is already present, what needs verification,
  and what still must be built to satisfy the Level 1-5 checkpoint.
- `PHASE_1_COMBO_CONTENT_AND_BAND_EXAM_PLAN.md`: current Phase 1 expansion
  plan for using the complete Band 4 package while preserving the deeper
  Level 1-5 learning experience and adding the Band 4 upgrade exam.

Removed plans:

- `AUTHENTICATION_AND_USER_DATA_IMPLEMENTATION_PLAN.md` and
  `USER_DATA_SCHEMA_PLAN.md` were merged into `ACCOUNT_AND_USER_DATA_PLAN.md`.
- `MEANING_CHOICE_ANSWER_PERSISTENCE_PLAN.md` was deleted because it described
  a superseded client-supplied-correctness design. Practice persistence is now
  owned by `LEVEL_AND_SPACED_REVIEW_FINAL_DESIGN.md`.
