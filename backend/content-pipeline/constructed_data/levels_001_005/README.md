# Levels 1-5 Constructed Data

This folder is generated from the source repositories under
`backend/content-pipeline/sources/`. Do not manually edit generated CSV rows; update the
pipeline scripts and regenerate them.

## Coverage

- Level 1: core family members and relationships
- Level 2: life stages, appearance, and personal description
- Level 3: relationships, behavior, and family life
- Level 4: rooms, furniture, and parts of a home
- Level 5: household objects, chores, and home routines

Each level contains 45 new sense-level learning units. Forms, collocations, and
review/context placements complete the planned 80-unit level experience.

## Run

From the repository root:

```powershell
python backend/content-pipeline/scripts/00_filter_sources.py
python backend/content-pipeline/scripts/01_select_candidates.py
python backend/content-pipeline/scripts/02_enrich_candidates.py
python backend/content-pipeline/scripts/03_validate_constructed_data.py
python backend/content-pipeline/scripts/06_build_approved_level_content.py
python backend/content-pipeline/scripts/07_validate_approved_content.py
python backend/content-pipeline/scripts/05_export_supabase_imports.py
```

## Files

- `00_source_registry.csv`: role, license, and review status for all six repos.
- `00_source_index.csv`: normalized ECDICT/Oxford/Webster source join.
- `01_candidates.csv`: ranked approved and reserve candidates.
- `02_word_senses.csv`: selected sense-level learning records.
- `02_word_forms.csv`: ECDICT inflections and lemma relationships.
- `02_level_assignments.csv`: 45 new units assigned to each level.
- `02_usage_evidence.csv`: source examples retained as private-study evidence.
- `02_collocations.csv`: candidate collocations extracted from source examples.
- `02_review_queue.csv`: records requiring content review.
- `02_level_summary.csv`: planned composition of each level.
- `03_content_todo.csv`: original practice-example authoring still required.
- `04_online_gap_fills.csv`: optional online comparison data for source gaps;
  never applied automatically.
- `06_approved_word_senses.csv`: corrected, approved sense records.
- `06_practice_examples.csv`: two original bilingual examples per sense.
- `06_questions.csv`: meaning choice, context choice, and spelling questions.
- `06_question_options.csv`: reviewed option sets for choice questions.
- `06_review_resolutions.csv`: audit trail for resolved review decisions.
- `supabase_import/`: normalized, dependency-ordered CSV files with stable UUIDs.

Every CSV includes `human_review` with `T` or `F`.

Vocabulary roles are `foundation`, `general_ielts`, and
`topic_recognition`. The first five levels are expected to contain foundation
and reusable general-IELTS senses; topic-recognition senses require explicit
Reading or Listening evidence.
