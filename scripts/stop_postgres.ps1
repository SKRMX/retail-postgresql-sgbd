$baseDir = Split-Path -Parent $PSScriptRoot
$binDir = Join-Path $baseDir "pgsql\bin"
$dataDir = Join-Path $baseDir "data"
$pgctlExe = Join-Path $binDir "pg_ctl.exe"

Write-Output "Deteniendo PostgreSQL 17..."
& $pgctlExe -D $dataDir stop -m fast

