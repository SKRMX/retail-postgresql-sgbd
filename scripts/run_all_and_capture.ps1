# =============================================================================
# PROYECTO: retail-postgresql-sgbd
# ARCHIVO: run_all_and_capture.ps1
# DESCRIPCIÓN: Script de ejecución completa y captura de evidencia técnica real.
# =============================================================================

$ErrorActionPreference = "Continue"
$env:PGOPTIONS = "--client-min-messages=warning"

$baseDir = Split-Path -Parent $PSScriptRoot
$binDir = Join-Path $baseDir "pgsql\bin"
$dataDir = Join-Path $baseDir "data"
$sqlDir = Join-Path $baseDir "sql"
$resultsDir = Join-Path $baseDir "results"

if (!(Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

$pgctlExe = Join-Path $binDir "pg_ctl.exe"
$psqlExe = Join-Path $binDir "psql.exe"
$createdbExe = Join-Path $binDir "createdb.exe"

# 1. Asegurar arranque de PostgreSQL 17
Write-Host "--- 1. Verificando estado de PostgreSQL 17 ---" -ForegroundColor Cyan
if (Test-Path (Join-Path $dataDir "postmaster.pid")) {
    & $pgctlExe -D $dataDir status
    if ($LASTEXITCODE -ne 0) {
        Remove-Item (Join-Path $dataDir "postmaster.pid") -Force
        & $pgctlExe -D $dataDir start
        Start-Sleep -Seconds 2
    }
} else {
    & $pgctlExe -D $dataDir start
    Start-Sleep -Seconds 2
}

# 2. Crear base de datos si no existe
Write-Host "--- 2. Creando base de datos retail_inventory_db ---" -ForegroundColor Cyan
& $psqlExe -h 127.0.0.1 -p 5432 -U postgres -d postgres -t -c "SELECT 1 FROM pg_database WHERE datname = 'retail_inventory_db';" | Out-String -OutVariable dbExists
if ($dbExists.Trim() -ne "1") {
    & $createdbExe -h 127.0.0.1 -p 5432 -U postgres retail_inventory_db
    Write-Host "Base de datos creada exitosamente." -ForegroundColor Green
} else {
    Write-Host "Base de datos retail_inventory_db ya existía." -ForegroundColor Yellow
}

# 3. Ejecutar 01_schema.sql
Write-Host "--- 3. Ejecutando 01_schema.sql ---" -ForegroundColor Cyan
& $psqlExe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f (Join-Path $sqlDir "01_schema.sql") 2>&1 | Out-File -FilePath (Join-Path $resultsDir "01_schema_output.txt") -Encoding utf8

# 4. Ejecutar 02_seed.sql
Write-Host "--- 4. Ejecutando 02_seed.sql (Carga de datos masivos) ---" -ForegroundColor Cyan
& $psqlExe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f (Join-Path $sqlDir "02_seed.sql") 2>&1 | Out-File -FilePath (Join-Path $resultsDir "02_seed_output.txt") -Encoding utf8

# 5. Ejecutar EXPLAIN ANALYZE antes de los índices (Línea base para comparación)
Write-Host "--- 5. Capturando EXPLAIN ANALYZE previo a la creación de índices ---" -ForegroundColor Cyan
& $psqlExe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f (Join-Path $sqlDir "05_explain_analyze.sql") 2>&1 | Out-File -FilePath (Join-Path $resultsDir "baseline_before_indexes.txt") -Encoding utf8

# 6. Ejecutar 03_indexes.sql
Write-Host "--- 6. Creando índices optimizados (03_indexes.sql) ---" -ForegroundColor Cyan
& $psqlExe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f (Join-Path $sqlDir "03_indexes.sql") 2>&1 | Out-File -FilePath (Join-Path $resultsDir "03_indexes_output.txt") -Encoding utf8

# 7. Ejecutar 04_queries.sql (Resultados de las consultas)
Write-Host "--- 7. Ejecutando 04_queries.sql ---" -ForegroundColor Cyan
& $psqlExe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f (Join-Path $sqlDir "04_queries.sql") 2>&1 | Out-File -FilePath (Join-Path $resultsDir "04_queries_output.txt") -Encoding utf8

# 8. Ejecutar 05_explain_analyze.sql (Planes con índices activos)
Write-Host "--- 8. Capturando EXPLAIN ANALYZE con índices optimizados ---" -ForegroundColor Cyan
& $psqlExe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f (Join-Path $sqlDir "05_explain_analyze.sql") 2>&1 | Out-File -FilePath (Join-Path $resultsDir "05_explain_analyze_after_indexes.txt") -Encoding utf8

# 9. Ejecutar 06_validation.sql
Write-Host "--- 9. Ejecutando 06_validation.sql ---" -ForegroundColor Cyan
& $psqlExe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f (Join-Path $sqlDir "06_validation.sql") 2>&1 | Out-File -FilePath (Join-Path $resultsDir "06_validation_output.txt") -Encoding utf8

# 10. Ejecutar 07_transactions.sql
Write-Host "--- 10. Ejecutando 07_transactions.sql ---" -ForegroundColor Cyan
& $psqlExe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f (Join-Path $sqlDir "07_transactions.sql") 2>&1 | Out-File -FilePath (Join-Path $resultsDir "07_transactions_output.txt") -Encoding utf8

# 11. Ejecutar 08_integrity_tests.sql
Write-Host "--- 11. Ejecutando 08_integrity_tests.sql ---" -ForegroundColor Cyan
& $psqlExe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f (Join-Path $sqlDir "08_integrity_tests.sql") 2>&1 | Out-File -FilePath (Join-Path $resultsDir "08_integrity_tests_output.txt") -Encoding utf8

Write-Host "--- Ejecución y captura completada con éxito. Archivos generados en $resultsDir ---" -ForegroundColor Green
