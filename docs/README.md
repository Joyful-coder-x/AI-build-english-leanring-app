# Documentation Index

See `docs/CODEBASE_INDEX.md` for the complete file map, architecture rules, legacy boundaries, and coding conventions — the single must-read file for anyone starting work on this project.

## Architecture

- `architecture/APP_ARCHITECTURE.md` — Android architecture and delivery phases.
- `architecture/DATA_MODEL_AND_CAPACITY.md` — database model, expected volume, and data ownership.
- `architecture/CONTENT_DATA_SOURCE_POLICY.md` — approved sources, licensing, and attribution requirements.

## Content

- `content/CONTENT_CONSTRUCTION_BRIEF.md` — schema and requirements for constructing learning content.
- `content/WORD_RESEARCH_AND_REVIEW_GUIDE.md` — research and human-review workflow.
- `../backend/content-pipeline/constructed_data/band_4_0_v1/supabase_import/README.md`
  — complete Levels 1–54 Band 4.0 engineering import and load order.

## Plans

Implementation-specific plans and follow-up work live in `plans/`. Each active
plan owns a distinct area; migrations and application code remain the source of
truth for implemented behavior.

- `plans/README.md` — ownership map for the active planning docs.
- `plans/ACCOUNT_AND_USER_DATA_PLAN.md` — account/authentication flow, private
  user data tables, RLS, onboarding persistence, and Android session wiring.
- `plans/BAND_UPGRADE_EXAM_PLAN.md` — approved replacement for initial
  placement assessment: always-open 40-question difficulty upgrade exams.
- `plans/LEVEL_AND_SPACED_REVIEW_FINAL_DESIGN.md` — controlling specification
  for configurable level composition, fixed 20-question rounds, spaced review,
  level completion, long-term mastery, and mistake-notebook ownership.
- `plans/ENGINEERING_QUALITY_FOLLOW_UP.md` — cross-cutting engineering-quality
  and testing follow-up.

## Current status

- Band 4 Levels 1–54 are implemented as an engineering-test package.
- Server-created practice rounds, spaced review, rewards, streaks, conditional
  hints, Level word status, and repeat rounds are implemented.
- Hosted Supabase should be verified through migration 014.
- Band 4 -> 4.5 upgrade exam backend core and Android UI/repository/ViewModel
  wiring have been added; target Supabase SQL verification is still required.
- Band 4.5 content remains unfinished beyond the target unlock level metadata.

## Product prototype

`product-prototype-v1/feature-specifications/` contains the original feature documents. `product-prototype-v1/wireframes/` contains the corresponding screen and flow images.
