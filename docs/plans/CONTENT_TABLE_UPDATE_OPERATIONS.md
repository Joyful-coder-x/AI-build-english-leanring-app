# Content Table Update Operations

This document defines how vocabulary and question-data changes must be stored
in Git so the `Deploy Supabase Database` GitHub Action can apply them safely.
It also defines when to use `update_table` and when the complete content package
must be reloaded with `load_table`.

## Deployment Source of Truth

The workflow reads the checked-in deployment package at:

`backend/content-pipeline/constructed_data/band_4_0_v1/supabase_import/`

The numbered CSV and SQL files in that directory are the only content files
read by the GitHub Action. A change made only in the Supabase dashboard, a local
database, or an uncommitted file will not be deployed.

The import files are generated artifacts, not the editorial source of truth.
Make content changes in the reviewed pipeline inputs or construction scripts,
regenerate the Band 4 package, validate it, review the generated diff, and then
commit both the source change and regenerated import files. Do not hand-edit an
exported CSV as the normal editing workflow because regeneration can overwrite
that edit.

For the current Band 4 package, regenerate and validate from the repository
root with:

```powershell
python backend/content-pipeline/scripts/10_build_band4_content.py
python backend/content-pipeline/scripts/11_validate_band4_content.py
```

## Required Change Workflow

For every content change:

1. Edit the reviewed source data or the generator that owns the value.
2. Regenerate the import package and run its validator.
3. Inspect the Git diff in every affected CSV or SQL file. Check identifiers,
   foreign keys, review flags, and unexpected bulk changes.
4. Commit the source changes and generated files together.
5. Push the commit to GitHub.
6. Open GitHub Actions, run `Deploy Supabase Database`, and choose the content
   action using the rules below.
7. Check the completed workflow and verify the affected rows in Supabase or the
   app. A pushed content-file change does not automatically run either manual
   content action.

## Choosing the Action

| Situation | Action | Reason |
|---|---|---|
| Correct text, translations, hints, metadata, review flags, audio paths, or ordering while preserving row keys | `update_table` | Existing rows are updated by their conflict key. |
| Add new words, senses, examples, questions, options, sources, or assignments with new stable IDs | `update_table` | New rows are inserted and existing rows are updated. |
| Change topic-cluster or level values without deleting their keys | `update_table` | Their SQL files already use upsert behavior. |
| Remove any row from the package | `load_table` | `update_table` does not delete database rows missing from a CSV. |
| Replace or regenerate UUIDs for existing logical rows | `load_table` | Upsert sees new UUIDs as new rows and leaves the old rows behind. |
| Move a level assignment by changing its composite key (`level_number`, `sense_id`, or `placement_type`) | `load_table` | The old assignment key would remain in the database. |
| Make a broad curriculum rebuild, generator change, or package replacement where many relationships change | `load_table` | A clean rebuild prevents stale related rows. |
| Change table columns, constraints, enums, indexes, functions, or RLS | Migration first; then choose `update_table` or `load_table` | Schema changes belong in a new migration, not only in CSV files. |
| First content deployment to an empty migrated database | `load_table` | Loads the complete validated package into a known clean state. |

When uncertain, compare old and new key columns. If a key disappeared or
changed, use `load_table`. If keys are preserved and rows are only added or
edited, use `update_table`.

## Stable Identifier Rules

`update_table` depends on stable keys. Preserve these keys when editing an
existing logical record:

| Import data | Conflict key |
|---|---|
| Sources, words, senses, forms, pronunciations, evidence, examples, collocations, questions, and options | `id` |
| Level/sense assignments | `level_number`, `sense_id`, `placement_type` |
| Topic clusters | `id` |
| Bands and levels | Their keys defined by the upsert SQL |

Do not create a new UUID merely because text changed. Keep the existing UUID so
foreign-key relationships and learner history still refer to the same logical
record. New logical rows need unique IDs, and every referenced parent row must
be present in the same package or already exist in the target database.

## What Each Action Does

### `update_table`

- Inserts rows whose conflict key does not exist.
- Updates all imported columns for rows whose conflict key already exists.
- Does not delete rows that were removed from the package.
- Does not reset learner practice, progress, or assessment data.
- Is the normal choice for small additions and corrections.

### `load_table`

- Clears vocabulary, curriculum, question, practice, progress, and assessment
  tables that depend on the content package.
- Reloads the complete Band 4 package in dependency order.
- Keeps authentication accounts, profiles, settings, consents, and onboarding
  profiles.
- Removes learner progress and practice history tied to the old content, so it
  must be treated as a destructive production operation.

Before using `load_table` against a database with real learner activity, take a
database backup and explicitly accept that the dependent learning history will
be cleared. Do not use it for a simple spelling or translation correction.

## Example Decisions

- Fix `definition_zh` for one existing sense: preserve its UUID, regenerate,
  commit, and run `update_table`.
- Add one question and four options: assign stable new UUIDs, preserve the
  existing sense UUID, regenerate, commit, and run `update_table`.
- Delete a bad question: remove it from its reviewed source, regenerate,
  commit, back up the target, and run `load_table`.
- Change only a question UUID while keeping the same question: avoid the UUID
  change. If it cannot be avoided, run `load_table` so the old question is not
  left behind.

## Failure Rule

If a content action fails, do not repeatedly run `load_table`. Read the first
failing workflow step, correct the source/package or database configuration,
and rerun the appropriate action. A partially failed `update_table` may have
already committed earlier table imports because the current importer processes
tables separately; its upserts are designed to be safe to rerun after the
underlying error is fixed.
