# IELTS Vocabulary Database

## GitHub Actions deployment

This repo deploys schema changes with GitHub Actions from
`.github/workflows/supabase-db.yml`.

The workflow is:

```text
edit locally -> test locally -> commit -> push to GitHub master -> GitHub Actions runs supabase db push
```

Because the repository keeps Supabase files in `backend/supabase/`, the action
runs Supabase CLI commands with `--workdir backend`. The CLI resolves migrations
as `<workdir>/supabase/migrations`, so using `backend/supabase` as the workdir
would incorrectly scan an empty `backend/supabase/supabase/migrations` folder.
Do not move or duplicate the migrations folder just for CI.

Add these repository secrets in GitHub:

```text
SUPABASE_ACCESS_TOKEN
SUPABASE_DB_PASSWORD
SUPABASE_PROJECT_ID
SUPABASE_DATABASE_URL
```

`SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, and `SUPABASE_PROJECT_ID` are
used by `supabase link` and `supabase db push`. `SUPABASE_DATABASE_URL` is used
by the migration-history safety check and the manual Band 4 content job.

Automatic pushes to `master` deploy SQL migrations only. The Band 4 CSV package
is imported only through a manual **Run workflow** action with
`content_action=load_table` or `content_action=update_table`, because CSV changes
should happen only after a backup and operator review.

### One-time hosted migration history recovery

The original workflow used `--workdir backend/supabase`, which made the CLI scan
the empty path `backend/supabase/supabase/migrations`. A successful Actions run
therefore did not prove that any repository migration had been applied.

Do not solve an empty hosted migration history with `db push --include-all` when
the hosted schema already exists. That can rerun historical DDL against live
objects. First back up the hosted database and verify which migrations were
applied manually. If the hosted database was built from
`manual/manual_apply_all_migrations.sql`, that bundle ends at migration 035.
Verify it without mutations:

```powershell
$env:DATABASE_URL = "postgresql://..."
powershell -ExecutionPolicy Bypass -File `
  backend/supabase/manual/run_phase1_target_verification.ps1
```

Only after that verification succeeds, link the correct project and baseline
the versions contained in the manual bundle. `migration repair` changes history
records only; it does not execute the migration SQL:

```powershell
supabase --workdir backend link --project-ref $env:SUPABASE_PROJECT_ID

$versions = Get-ChildItem backend/supabase/migrations/*.sql |
  Where-Object Name -LE '202607070035_overall_assessment.sql' |
  Sort-Object Name |
  ForEach-Object { ($_.BaseName -split '_')[0] }

supabase --workdir backend migration repair @versions `
  --status applied --yes
supabase --workdir backend migration list --linked
supabase --workdir backend db push --dry-run
```

The dry run should list only migrations after 035. Review that list, then apply
it with `supabase --workdir backend db push --yes`. The CI workflow intentionally
fails when hosted migration history is missing or empty, preventing accidental
historical reapplication.

Before pushing a migration, run the disposable local proof from the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File backend/supabase/manual/run_phase1_local_docker_verification.ps1
```

## Apply

1. Back up the current Supabase project.
2. Apply migrations in filename order from `backend/supabase/migrations/`.
3. After migrations 003 and 004 succeed, obsolete pilot tables can be removed with
   `backend/supabase/manual/drop_obsolete_pilot_tables.sql`.
4. If replacing the old pilot vocabulary, run
   `backend/supabase/manual/reset_vocabulary_content_for_rebuild.sql`.
5. Follow
   `backend/content-pipeline/constructed_data/band_4_0_v1/supabase_import/README.md`
   to load the Phase 1 combo package: deep Levels 1-5 plus compact
   lightweight Band 4 Levels 6-33.

The reset script is intentionally separate from migrations. It deletes shared
vocabulary and dependent sense progress, so it must never run automatically.

## Prototype Username Authentication

The Android prototype signs users in with a username and password. Internally,
the username is converted to a deterministic placeholder email because Supabase
Auth requires an email or phone identity. Passwords remain hashed and managed by
Supabase Auth; they are never stored in `public.profiles`.

In the Supabase dashboard:

1. Open **Authentication > Providers > Email**.
2. Leave the Email provider enabled.
3. Turn off **Confirm email**.
4. Save the configuration.

Existing accounts created with real email addresses are not compatible with
username-only login and should be recreated for prototype testing. This flow has
no password recovery because the user does not provide a real email address.

## Regenerate Content

From the repository root:

```powershell
python backend/content-pipeline/scripts/00_filter_sources.py
python backend/content-pipeline/scripts/01_select_candidates.py
python backend/content-pipeline/scripts/02_enrich_candidates.py
python backend/content-pipeline/scripts/04_fill_source_gaps.py
python backend/content-pipeline/scripts/03_validate_constructed_data.py
python backend/content-pipeline/scripts/06_build_approved_level_content.py
python backend/content-pipeline/scripts/07_validate_approved_content.py
python backend/content-pipeline/scripts/05_export_supabase_imports.py
```

Do not import a generated batch unless validation passes.

## Complete Band 4.0 package

Generate and validate:

```powershell
python backend/content-pipeline/scripts/10_build_band4_content.py
python backend/content-pipeline/scripts/11_validate_band4_content.py
```

Then follow:

`backend/content-pipeline/constructed_data/band_4_0_v1/supabase_import/README.md`

For a target Supabase project, the repeatable operator command is:

```powershell
# Requires PostgreSQL client tools (`psql`) on PATH.
$env:DATABASE_URL = "postgresql://..."
powershell -ExecutionPolicy Bypass -File backend/supabase/manual/run_phase1_target_verification.ps1 -ApplyMigrations -ResetVocabulary -ImportBand4
```

Use `-ResetVocabulary` only after backing up the project. To verify an already
loaded target database without changing data, omit `-ApplyMigrations`,
`-ResetVocabulary`, and `-ImportBand4`.

For local proof without hosted Supabase credentials, run the disposable Docker
verification:

```powershell
powershell -ExecutionPolicy Bypass -File backend/supabase/manual/run_phase1_local_docker_verification.ps1
```

This starts a temporary `postgres:17-alpine` container, applies the local
Supabase auth shim, applies every migration, imports the Band 4 package, runs
the SQL tests below, and removes the container unless `-KeepContainer` is set.

The script runs the same tests listed below:

```text
backend/supabase/tests/202606220005_user_bootstrap_and_onboarding_test.sql
backend/supabase/tests/202606240007_onboarding_starts_at_level_one_test.sql
backend/supabase/tests/verify_project_installation.sql
backend/supabase/tests/202606240009_spaced_review_practice_rounds_test.sql
backend/supabase/tests/202606240010_band4_content_runtime_test.sql
backend/supabase/tests/202606240012_conditional_context_hints_test.sql
backend/supabase/tests/202606250016_sentence_cloze_level_rounds_test.sql
backend/supabase/tests/202607060025_combo_scope_practice_type_selection_test.sql
backend/supabase/tests/202607060026_band_upgrade_exam_core_test.sql
backend/supabase/tests/202607060027_band4_unlock_chain_test.sql
backend/supabase/tests/202607060029_phase1_practice_logging_evidence_test.sql
backend/supabase/tests/202607070029_review_before_new_sense_priority_test.sql
backend/supabase/tests/202607150043_speaking_self_check_submission_test.sql
```

The runtime tests open server-created rounds for Band 4, verify configurable
completion, confirm the final Band 4 level cannot bypass the upgrade exam,
enforce the Level 6-33 lightweight question-type policy, test the Band 4 -> 4.5 exam
pass/fail threshold, verify the compact Band 4 Level 1 -> 33 unlock chain, and prove
practice logging/reward/streak/mistake persistence after a generated round.

## Current migration status

Repository migrations after the base round implementation:

- `202606240011_profile_streak_and_reward_refresh.sql`
  - persistent duck power refresh and once-per-day streak;
- `202606240012_conditional_context_hints.sql`
  - context hints for explicit multiple meanings or `wrong_count >= 3`;
- `202606240013_simplify_english_meaning_stems.sql`
  - removes redundant `Which word means:` text;
- `202606240014_level_word_statuses.sql`
  - result-screen Level word/status RPC.

Apply all migrations in filename order through
`202607070029_review_before_new_sense_priority.sql`, then rerun
`tests/verify_project_installation.sql` and the targeted SQL tests listed
above. The Band 4 -> 4.5 upgrade exam backend exists in
`202607060026_band_upgrade_exam_core.sql`; the Level 6-33 lightweight practice
policy is in `202607060025_combo_scope_practice_type_selection.sql`; the
due-review new-word gate is in `202607060028_due_review_new_word_gate.sql`;
and the review-before-new-sense round assembly priority fix (2026-07-07 audit)
is in `202607070029_review_before_new_sense_priority.sql`.
Android is wired through `BandUpgradeExamScreen` / `BandUpgradeExamViewModel`.
