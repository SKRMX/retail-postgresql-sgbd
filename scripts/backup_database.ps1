param(
    [string]$PgHost = "127.0.0.1",
    [int]$PgPort = 5432,
    [string]$Database = "retail_inventory_db",
    [string]$PgUser = "postgres",
    [string]$OutputDirectory = ".\backups",
    [int]$RetentionDays = 14
)

$ErrorActionPreference = "Stop"

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "No se encontró '$Name' en PATH."
    }
}

Require-Command "pg_dump"
Require-Command "pg_dumpall"

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$dbBackup = Join-Path $OutputDirectory ($Database + "_" + $timestamp + ".dump")
$globalsBackup = Join-Path $OutputDirectory ("postgres_globals_" + $timestamp + ".sql")

Write-Host "[1/4] Generando respaldo lógico de $Database..."
& pg_dump "--host=$PgHost" "--port=$PgPort" "--username=$PgUser" "--format=custom" "--compress=9" "--verbose" "--file=$dbBackup" $Database
if ($LASTEXITCODE -ne 0) { throw "pg_dump finalizó con código $LASTEXITCODE." }

Write-Host "[2/4] Respaldando roles y objetos globales..."
& pg_dumpall "--host=$PgHost" "--port=$PgPort" "--username=$PgUser" "--globals-only" "--file=$globalsBackup"
if ($LASTEXITCODE -ne 0) { throw "pg_dumpall finalizó con código $LASTEXITCODE." }

Write-Host "[3/4] Calculando checksums SHA-256..."
Get-FileHash $dbBackup -Algorithm SHA256 |
    ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" } |
    Set-Content ($dbBackup + ".sha256")

Get-FileHash $globalsBackup -Algorithm SHA256 |
    ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" } |
    Set-Content ($globalsBackup + ".sha256")

Write-Host "[4/4] Aplicando retención de $RetentionDays días..."
$cutoff = (Get-Date).AddDays(-$RetentionDays)
Get-ChildItem $OutputDirectory -File |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    Remove-Item -Force

Write-Host ""
Write-Host "Respaldo completado:"
Write-Host "  Base:     $dbBackup"
Write-Host "  Globales: $globalsBackup"
Write-Host "Nota: la contraseña NO se almacena en este script."
