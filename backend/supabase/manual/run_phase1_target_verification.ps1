param(
    [string]$DatabaseUrl = $env:DATABASE_URL,
    [switch]$ApplyMigrations,
    [switch]$ResetVocabulary,
    [switch]$ImportBand4,
    [switch]$UpsertBand4,
    [switch]$SkipTests,
    [switch]$UseDocker
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
    throw "Set DATABASE_URL or pass -DatabaseUrl with the target Supabase Postgres connection string."
}

if ($UseDocker) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "docker was not found on PATH. Install Docker Desktop, or omit -UseDocker and install psql instead."
    }
} elseif (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    throw "psql was not found on PATH. Install PostgreSQL client tools, or pass -UseDocker to run psql inside a disposable postgres:17-alpine container instead (only needs Docker Desktop, which this repo's local test harness already uses)."
}

$psqlImage = "postgres:17-alpine"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$supabaseDir = Join-Path $repoRoot "backend\supabase"
$migrationDir = Join-Path $supabaseDir "migrations"
$testDir = Join-Path $supabaseDir "tests"
$importDir = Join-Path $repoRoot "backend\content-pipeline\constructed_data\band_4_0_v1\supabase_import"

function Convert-ToPsqlPath([string]$Path) {
    return ((Resolve-Path $Path).Path -replace "\\", "/")
}

function Invoke-PsqlFile([string]$Path) {
    $resolved = (Resolve-Path $Path).Path
    Write-Host "psql -f $resolved"
    if ($UseDocker) {
        $dir = Split-Path $resolved -Parent
        $file = Split-Path $resolved -Leaf
        docker run --rm -v "${dir}:/work" $psqlImage psql $DatabaseUrl -v ON_ERROR_STOP=1 -f "/work/$file"
    } else {
        & psql $DatabaseUrl -v ON_ERROR_STOP=1 -f $resolved
    }
    if ($LASTEXITCODE -ne 0) {
        throw "psql failed for $resolved"
    }
}

function Invoke-PsqlCommand([string]$Command) {
    Write-Host "psql -c $($Command.Substring(0, [Math]::Min(90, $Command.Length)))"
    if ($UseDocker) {
        docker run --rm -v "${importDir}:/import" $psqlImage psql $DatabaseUrl -v ON_ERROR_STOP=1 -c $Command
    } else {
        & psql $DatabaseUrl -v ON_ERROR_STOP=1 -c $Command
    }
    if ($LASTEXITCODE -ne 0) {
        throw "psql command failed"
    }
}

function Assert-Band4ImportSchemaReady {
    $requiredTables = @(
        "content_sources",
        "topic_clusters",
        "bands",
        "levels",
        "words",
        "word_senses",
        "word_forms",
        "pronunciations",
        "level_sense_assignments",
        "usage_evidence",
        "examples",
        "collocations",
        "question_types",
        "questions",
        "question_options"
    )

    foreach ($table in $requiredTables) {
        if ($table -notmatch '^[a-z_][a-z0-9_]*$') {
            throw "Invalid table identifier: public.$table"
        }
    }

    $values = ($requiredTables | ForEach-Object { "('$_')" }) -join ","
$check = @"
with required(table_name) as (
  values $values
),
missing as (
  select table_name
  from required
  where to_regclass('public.' || table_name) is null
),
existing_public_tables as (
  select coalesce(string_agg(tablename, ', ' order by tablename), '<none>') as names
  from pg_tables
  where schemaname = 'public'
),
migration_versions as (
  select case
    when to_regclass('supabase_migrations.schema_migrations') is null then '<schema_migrations table missing>'
    else '<schema_migrations table exists; detailed versions checked below>'
  end as versions
)
select
  current_database() as database_name,
  current_user as database_user,
  inet_server_addr() as server_addr,
  inet_server_port() as server_port,
  (select names from existing_public_tables) as existing_public_tables,
  (select versions from migration_versions) as recorded_migrations,
  coalesce((select string_agg(table_name, ', ' order by table_name) from missing), '<none>') as missing_required_tables;

do `$`$
declare
  missing_required_tables text;
  existing_public_tables text;
  recorded_migrations text;
begin
  with required(table_name) as (
    values $values
  ),
  missing as (
    select table_name
    from required
    where to_regclass('public.' || table_name) is null
  )
  select coalesce(string_agg(table_name, ', ' order by table_name), '')
  into missing_required_tables
  from missing;

  select coalesce(string_agg(tablename, ', ' order by tablename), '<none>')
  into existing_public_tables
  from pg_tables
  where schemaname = 'public';

  if to_regclass('supabase_migrations.schema_migrations') is null then
    recorded_migrations := '<schema_migrations table missing>';
  else
    execute 'select coalesce(string_agg(version, '', '' order by version), ''<no migrations recorded>'') from supabase_migrations.schema_migrations'
    into recorded_migrations;
  end if;

  if missing_required_tables <> '' then
    raise exception 'Band 4 import schema is not ready. Missing required tables: %. Existing public tables: %. Recorded migrations: %',
      missing_required_tables,
      existing_public_tables,
      recorded_migrations;
  end if;
end
`$`$;
"@

    Invoke-PsqlCommand $check
}

function Copy-Csv([string]$TableAndColumns, [string]$CsvName) {
    if ($UseDocker) {
        Invoke-PsqlCommand "\copy $TableAndColumns from '/import/$CsvName' with (format csv, header true, encoding 'UTF8')"
    } else {
        $path = Convert-ToPsqlPath (Join-Path $importDir $CsvName)
        Invoke-PsqlCommand "\copy $TableAndColumns from '$path' with (format csv, header true, encoding 'UTF8')"
    }
}

function Upsert-Csv([string]$TableName, [string[]]$Columns, [string[]]$ConflictColumns, [string]$CsvName) {
    $stageName = "public._band4_import_" + (($TableName -replace "^public\.", "") -replace "[^a-zA-Z0-9_]", "_")
    $columnList = $Columns -join ","
    $conflictList = $ConflictColumns -join ","
    $updateColumns = $Columns | Where-Object { $ConflictColumns -notcontains $_ }
    $updateList = ($updateColumns | ForEach-Object { "$_ = excluded.$_" }) -join ","

    if ([string]::IsNullOrWhiteSpace($updateList)) {
        $conflictAction = "do nothing"
    } else {
        $conflictAction = "do update set $updateList"
    }

    $copyPath = if ($UseDocker) {
        "/import/$CsvName"
    } else {
        Convert-ToPsqlPath (Join-Path $importDir $CsvName)
    }

    Invoke-PsqlCommand "drop table if exists $stageName; create table $stageName (like $TableName including defaults);"

    try {
        Invoke-PsqlCommand "\copy $stageName($columnList) from '$copyPath' with (format csv, header true, encoding 'UTF8')"

        $command = @"
insert into $TableName($columnList)
select $columnList
from $stageName
on conflict ($conflictList) $conflictAction;
"@

        Invoke-PsqlCommand $command
    } finally {
        Invoke-PsqlCommand "drop table if exists $stageName;"
    }
}

if ($ApplyMigrations) {
    Get-ChildItem $migrationDir -Filter "*.sql" |
        Sort-Object Name |
        ForEach-Object { Invoke-PsqlFile $_.FullName }
}

if ($ResetVocabulary) {
    Write-Warning "ResetVocabulary truncates shared vocabulary content and dependent learning rows. Confirm you have a backup."
    Invoke-PsqlFile (Join-Path $supabaseDir "manual\reset_vocabulary_content_for_rebuild.sql")
}

if ($ImportBand4) {
    Assert-Band4ImportSchemaReady
    Copy-Csv "public.content_sources(id,source_key,name,source_url,license_name,copyright_status,attribution_text,notes,human_review)" "01_content_sources.csv"
    Invoke-PsqlFile (Join-Path $importDir "02_topic_clusters_upsert.sql")
    Invoke-PsqlFile (Join-Path $importDir "03_band_levels_upsert.sql")
    Copy-Csv "public.words(id,headword,display_spelling,frequency_rank,human_review)" "04_words.csv"
    Copy-Csv "public.word_senses(id,word_id,part_of_speech,sense_number,definition_en,definition_zh,vocabulary_role,difficulty_band,cefr_level,register,is_primary,source_id,human_review,review_status)" "05_word_senses.csv"
    Copy-Csv "public.word_forms(id,word_id,sense_id,form_type,form_text,source_id,human_review)" "06_word_forms.csv"
    Copy-Csv "public.pronunciations(id,word_id,sense_id,ipa_us,audio_path,source_id,human_review)" "07_pronunciations.csv"
    Copy-Csv "public.level_sense_assignments(level_number,sense_id,placement_type,order_in_level,vocabulary_role,is_required,human_review)" "08_level_sense_assignments.csv"
    Copy-Csv "public.usage_evidence(id,sense_id,source_id,quoted_text,matched_span,source_locator,usage_analysis,paper_types,copyright_status,human_review)" "09_usage_evidence.csv"
    Copy-Csv "public.examples(id,sense_id,sentence_en,translation_zh,target_span,origin,difficulty_band,source_id,review_status,human_review,audio_path,sort_order)" "10_examples.csv"
    Copy-Csv "public.collocations(id,sense_id,collocation,translation_zh,difficulty_band,source_id,human_review,review_status)" "11_collocations.csv"
    Copy-Csv "public.questions(id,sense_id,question_type_id,type_code,category,answer_form,word_id,example_id,stem,correct_answer,difficulty,is_active,generation_version,human_review,prompt_hint,translation_zh,expected_time_ms,question_type_key,is_context_hint,context_for_multiple_meaning)" "12_questions.csv"
    Copy-Csv "public.question_options(id,question_id,option_text,target_sense_id,is_correct,sort_order,human_review)" "13_question_options.csv"
}

if ($UpsertBand4) {
    Assert-Band4ImportSchemaReady
    Upsert-Csv "public.content_sources" @("id","source_key","name","source_url","license_name","copyright_status","attribution_text","notes","human_review") @("id") "01_content_sources.csv"
    Invoke-PsqlFile (Join-Path $importDir "02_topic_clusters_upsert.sql")
    Invoke-PsqlFile (Join-Path $importDir "03_band_levels_upsert.sql")
    Upsert-Csv "public.words" @("id","headword","display_spelling","frequency_rank","human_review") @("id") "04_words.csv"
    Upsert-Csv "public.word_senses" @("id","word_id","part_of_speech","sense_number","definition_en","definition_zh","vocabulary_role","difficulty_band","cefr_level","register","is_primary","source_id","human_review","review_status") @("id") "05_word_senses.csv"
    Upsert-Csv "public.word_forms" @("id","word_id","sense_id","form_type","form_text","source_id","human_review") @("id") "06_word_forms.csv"
    Upsert-Csv "public.pronunciations" @("id","word_id","sense_id","ipa_us","audio_path","source_id","human_review") @("id") "07_pronunciations.csv"
    Upsert-Csv "public.level_sense_assignments" @("level_number","sense_id","placement_type","order_in_level","vocabulary_role","is_required","human_review") @("level_number","sense_id","placement_type") "08_level_sense_assignments.csv"
    Upsert-Csv "public.usage_evidence" @("id","sense_id","source_id","quoted_text","matched_span","source_locator","usage_analysis","paper_types","copyright_status","human_review") @("id") "09_usage_evidence.csv"
    Upsert-Csv "public.examples" @("id","sense_id","sentence_en","translation_zh","target_span","origin","difficulty_band","source_id","review_status","human_review","audio_path","sort_order") @("id") "10_examples.csv"
    Upsert-Csv "public.collocations" @("id","sense_id","collocation","translation_zh","difficulty_band","source_id","human_review","review_status") @("id") "11_collocations.csv"
    Upsert-Csv "public.questions" @("id","sense_id","question_type_id","type_code","category","answer_form","word_id","example_id","stem","correct_answer","difficulty","is_active","generation_version","human_review","prompt_hint","translation_zh","expected_time_ms","question_type_key","is_context_hint","context_for_multiple_meaning") @("id") "12_questions.csv"
    Upsert-Csv "public.question_options" @("id","question_id","option_text","target_sense_id","is_correct","sort_order","human_review") @("id") "13_question_options.csv"
}

if (-not $SkipTests) {
    $tests = @(
        "202606220005_user_bootstrap_and_onboarding_test.sql",
        "202606240007_onboarding_starts_at_level_one_test.sql",
        "verify_project_installation.sql",
        "202606240009_spaced_review_practice_rounds_test.sql",
        "202606240010_band4_content_runtime_test.sql",
        "202606240012_conditional_context_hints_test.sql",
        "202606250016_sentence_cloze_level_rounds_test.sql",
        "202607060025_combo_scope_practice_type_selection_test.sql",
        "202607060026_band_upgrade_exam_core_test.sql",
        "202607060027_band4_unlock_chain_test.sql",
        "202607060029_phase1_practice_logging_evidence_test.sql",
        "202607070029_review_before_new_sense_priority_test.sql",
        "202607070030_login_tracking_test.sql",
        "202607070031_awards_system_test.sql",
        "202607070034_skill_scoring_test.sql",
        "202607070035_overall_assessment_test.sql"
    )

    foreach ($test in $tests) {
        Invoke-PsqlFile (Join-Path $testDir $test)
    }
}

Write-Host "Phase 1 target verification command completed."
