$baseDir = Split-Path -Parent $PSScriptRoot
$binDir = Join-Path $baseDir "pgsql\bin"
$dataDir = Join-Path $baseDir "data"

$pgctlExe = Join-Path $binDir "pg_ctl.exe"
$psqlExe = Join-Path $binDir "psql.exe"

Write-Output "Iniciando PostgreSQL 17..."
& $pgctlExe -D $dataDir start

Start-Sleep -Seconds 2

& $psqlExe -h 127.0.0.1 -p 5432 -U postgres -d postgres -c "SELECT version();"
