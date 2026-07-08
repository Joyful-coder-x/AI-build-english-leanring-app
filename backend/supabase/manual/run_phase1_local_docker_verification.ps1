param(
    [string]$Image = "postgres:17-alpine",
    [string]$ContainerName = "",
    [switch]$KeepContainer
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker was not found on PATH. Install Docker before running local verification."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$supabaseDir = Join-Path $repoRoot "backend\supabase"
$migrationDir = Join-Path $supabaseDir "migrations"
$testDir = Join-Path $supabaseDir "tests"
$importDir = Join-Path $repoRoot "backend\content-pipeline\constructed_data\band_4_0_v1\supabase_import"

if ([string]::IsNullOrWhiteSpace($ContainerName)) {
    $ContainerName = "phase1-sql-test-" + (Get-Date -Format "yyyyMMddHHmmss")
}

function Invoke-DockerExecPsqlFile([string]$ContainerPath) {
    Write-Host "psql -f $ContainerPath"
    docker exec $ContainerName psql -U postgres -v ON_ERROR_STOP=1 -f $ContainerPath
    if ($LASTEXITCODE -ne 0) {
        throw "psql failed for $ContainerPath"
    }
}

function Invoke-DockerExecPsqlCommand([string]$Command) {
    docker exec $ContainerName psql -U postgres -v ON_ERROR_STOP=1 -c $Command
    if ($LASTEXITCODE -ne 0) {
        throw "psql command failed"
    }
}

function Copy-ToContainer([string]$Source, [string]$Target) {
    docker cp $Source "${ContainerName}:$Target"
    if ($LASTEXITCODE -ne 0) {
        throw "docker cp failed for $Source"
    }
}

try {
    Write-Host "Starting $ContainerName from $Image"
    docker run --name $ContainerName -e POSTGRES_PASSWORD=postgres -d $Image | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "docker run failed"
    }

    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        docker exec $ContainerName pg_isready -U postgres | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        throw "Postgres did not become ready in $ContainerName"
    }

    Invoke-DockerExecPsqlCommand "select version();"

    docker exec $ContainerName mkdir -p /migrations /tests /imports | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create container work directories"
    }

    Copy-ToContainer "$migrationDir\." "/migrations"
    Copy-ToContainer "$testDir\." "/tests"
    Copy-ToContainer "$importDir\." "/imports"

    Invoke-DockerExecPsqlFile "/tests/local_supabase_auth_shim.sql"

    Get-ChildItem $migrationDir -Filter "*.sql" |
        Sort-Object Name |
        ForEach-Object { Invoke-DockerExecPsqlFile "/migrations/$($_.Name)" }

    Invoke-DockerExecPsqlFile "/tests/load_band4_import_for_local_test.sql"

    $phase1Tests = @(
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

    foreach ($test in $phase1Tests) {
        Invoke-DockerExecPsqlFile "/tests/$test"
    }

    Write-Host "Phase 1 local Docker verification passed in $ContainerName."
} finally {
    if (-not $KeepContainer) {
        docker rm -f $ContainerName | Out-Null
    } else {
        Write-Host "Kept container $ContainerName for inspection."
    }
}
