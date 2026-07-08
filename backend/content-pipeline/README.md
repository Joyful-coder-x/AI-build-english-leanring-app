# Vocabulary Content Pipeline

This pipeline constructs reviewed IELTS vocabulary curriculum data and exports
Supabase-ready files. It combines approved local source datasets, explicit
quality gates, human review, and deterministic export logic.

The original 20-word prototype generator is preserved in `legacy-pilot/` for
audit purposes. It is not the active production workflow.

## Directory Layout

```text
backend/content-pipeline/
  constructed_data/   # reviewed intermediate data and import packages
  input/              # manually maintained pipeline inputs
  reference/          # research material and feasibility samples
  scripts/            # active numbered pipeline stages
  sources/            # downloaded source repositories; gitignored
  legacy-pilot/       # archived first-generation generator
```

## Active Workflow

Run from the repo root:

```powershell
python backend/content-pipeline/scripts/00_filter_sources.py
python backend/content-pipeline/scripts/01_select_candidates.py
python backend/content-pipeline/scripts/02_enrich_candidates.py
python backend/content-pipeline/scripts/03_validate_constructed_data.py
python backend/content-pipeline/scripts/04_fill_source_gaps.py
python backend/content-pipeline/scripts/06_build_approved_level_content.py
python backend/content-pipeline/scripts/07_validate_approved_content.py
python backend/content-pipeline/scripts/05_export_supabase_imports.py
```

Run stage 04 only when the review queue requires online gap filling. Do not
export a batch unless stages 03 and 07 pass.

## Full Band 4.0 Engineering Package

Generate and validate the complete first difficulty band with:

```powershell
python backend/content-pipeline/scripts/10_build_band4_content.py
python backend/content-pipeline/scripts/11_validate_band4_content.py
```

Output:

`constructed_data/band_4_0_v1/supabase_import/`

The package preserves reviewed Levels 1-5 and constructs source-backed,
deterministic prototype content for Levels 6-54. It is intended for complete
engineering/product testing. Public release still requires a separate human
editorial pass.

## Supabase Load Order

1. Apply migrations from `../supabase/migrations/` in filename order.
2. Read `constructed_data/band_4_0_v1/supabase_import/README.md`.
3. Import the validated files in the documented order.
4. Run `../supabase/manual/run_phase1_local_docker_verification.ps1` for local
   proof, or `../supabase/manual/run_phase1_target_verification.ps1` against a
   hosted target before using the data in the Android app.

## Production Rules

- Follow `../../docs/architecture/CONTENT_DATA_SOURCE_POLICY.md`.
- Preserve source and review metadata for every imported content row.
- Treat generated content as draft until the validation and human-review gates pass.
- Do not edit exported CSV rows directly; update the reviewed source data and regenerate them.
