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

Implementation-specific plans and follow-up work live in `plans/`. These documents describe intended or historical work; migrations and application code remain the source of truth for implemented behavior.

- `plans/BAND_UPGRADE_EXAM_PLAN.md` — approved replacement for initial
  placement assessment: always-open 40-question difficulty upgrade exams.
- `plans/LEVEL_AND_SPACED_REVIEW_FINAL_DESIGN.md` — controlling specification
  for configurable level composition, fixed 20-question rounds, spaced review,
  level completion, long-term mastery, and mistake-notebook ownership.

## Current status

- Band 4 Levels 1–54 are implemented as an engineering-test package.
- Server-created practice rounds, spaced review, rewards, streaks, conditional
  hints, Level word status, and repeat rounds are implemented.
- Hosted Supabase should be verified through migration 014.
- Band 4.5 upgrade exam and Band 4.5 content remain unfinished.

## Product prototype

`product-prototype-v1/feature-specifications/` contains the original feature documents. `product-prototype-v1/wireframes/` contains the corresponding screen and flow images.
