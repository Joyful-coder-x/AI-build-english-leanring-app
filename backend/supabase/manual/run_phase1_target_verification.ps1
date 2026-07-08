param(
    [string]$DatabaseUrl = $env:DATABASE_URL,
    [switch]$ApplyMigrations,
    [switch]$ResetVocabulary,
    [switch]$ImportBand4,
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
    throw "Set DATABASE_URL or pass -DatabaseUrl with the target Supabase Postgres connection string."
}

if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    throw "psql was not found on PATH. Install PostgreSQL client tools before running target verification."
}

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
    & psql $DatabaseUrl -v ON_ERROR_STOP=1 -f $resolved
    if ($LASTEXITCODE -ne 0) {
        throw "psql failed for $resolved"
    }
}

function Invoke-PsqlCommand([string]$Command) {
    Write-Host "psql -c $($Command.Substring(0, [Math]::Min(90, $Command.Length)))"
    & psql $DatabaseUrl -v ON_ERROR_STOP=1 -c $Command
    if ($LASTEXITCODE -ne 0) {
        throw "psql command failed"
    }
}

function Copy-Csv([string]$TableAndColumns, [string]$CsvName) {
    $path = Convert-ToPsqlPath (Join-Path $importDir $CsvName)
    Invoke-PsqlCommand "\copy $TableAndColumns from '$path' with (format csv, header true, encoding 'UTF8')"
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
        "202607060029_phase1_practice_logging_evidence_test.sql"
    )

    foreach ($test in $tests) {
        Invoke-PsqlFile (Join-Path $testDir $test)
    }
}

Write-Host "Phase 1 target verification command completed."
