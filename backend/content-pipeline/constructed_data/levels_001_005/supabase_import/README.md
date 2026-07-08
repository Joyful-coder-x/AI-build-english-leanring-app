# Supabase Import Order

Run migrations through `202606260020_generated_practice_round_logic.sql` first.

For Supabase SQL Editor, use the generated SQL upsert scripts instead of the
CSV importer. The all-in-one file may be too large for the SQL Editor, so run
these files in numeric order:

1. `99_upsert_current_levels_001_005_part_01.sql`
2. `99_upsert_current_levels_001_005_part_02.sql`
3. `99_upsert_current_levels_001_005_part_03.sql`
4. `99_upsert_current_levels_001_005_part_04.sql`
5. `99_upsert_current_levels_001_005_part_05.sql`
6. `99_upsert_current_levels_001_005_part_06.sql`

Then run `98_validate_current_levels_001_005.sql`.

`99_upsert_current_levels_001_005.sql` contains the same statements in one
transaction for direct database clients that can run larger SQL files.

If the old pilot vocabulary is still present, back up the database and then run
`backend/supabase/manual/reset_vocabulary_content_for_rebuild.sql`. Do not run that
script after real learner progress exists unless losing vocabulary-dependent
progress is intentional.

CSV fallback import order:

1. `01_content_sources.csv`
2. Run `03_curriculum_upsert.sql` in the SQL editor. This safely updates the
   240 level rows created by the migration.
3. `04_words.csv`
4. `05_word_senses.csv`
5. `06_word_forms.csv`
6. `07_pronunciations.csv`
7. `08_level_sense_assignments.csv`
8. `09_usage_evidence.csv`
9. `10_examples.csv`
10. `11_collocations.csv`
11. `12_questions.csv`
12. `13_question_options.csv`

`02_topic_clusters.csv` and `03_levels.csv` are audit/export copies. Do not use
a plain insert for `03_levels.csv`, because the migration already creates those
level keys.

The exporter uses UUID v5 identifiers, so the same source record receives the
same ID after regeneration. This slice includes two reviewed original examples
and three supported questions per sense. Lexical relations remain empty because
synonyms and antonyms are not forced without a reliable sense-level relation.

Regenerate these files with:

```powershell
python backend/content-pipeline/scripts/05_export_supabase_imports.py
```
