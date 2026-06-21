# Pilot Word Bank Pipeline

This pipeline converts reviewed word-package data into Supabase-ready CSV, SQL, and TTS manifest files.

It does not scrape Oxford, Cambridge, or OALD. Production inputs must come from approved/licensed source files and must keep source/audit metadata in the package file or a separate production log.

## Directory Layout

```text
content_pipeline/
  config/pipeline_config.json
  input/level_001_seed.csv
  packages/level_001_packages.json
  scripts/
  tests/
  output/     # generated, gitignored
  audio/      # generated MP3 staging, gitignored
```

## Operator Workflow

Run from the repo root:

```powershell
python content_pipeline/scripts/validate_packages.py
python content_pipeline/scripts/export_csv.py
python content_pipeline/scripts/generate_questions.py
python content_pipeline/scripts/generate_tts_manifest.py
python content_pipeline/scripts/generate_sql.py
```

Generated files land in `content_pipeline/output/`.

## Supabase Load Order

1. Run `content_pipeline/output/schema_reference.sql` in Supabase SQL Editor.
2. Import `output/words.csv`.
3. Import `output/word_meanings.csv`.
4. Import `output/word_forms.csv`.
5. Import `output/examples.csv`.
6. Import `output/questions.csv`.
7. Import `output/question_options.csv`.
8. Generate Google TTS audio from `pronunciation_tts_manifest.jsonl`.
9. Upload MP3 files to Supabase Storage bucket `pronunciations`.
10. Validate the Android app with `USE_REAL_QUESTIONS = true`.

## Production Rules

- Oxford 3000/5000 is the word-list seed only.
- Cambridge Dictionary is primary for `definition_en`, `phonetic`, and `pos_primary`; OALD is backup.
- English example sentences must come from approved dictionaries/corpora, not AI.
- `translation_zh` and `mnemonic` may be AI-drafted, but must be reviewable.
- `mnemonic` is required before load.
- `questions.explanation` stays empty/null. Claude generates it live in the app.
- Active pilot question types are 1 and 2 only.

The included `packages/level_001_packages.json` is a tiny runnable fixture, not the final 80-word production package.
