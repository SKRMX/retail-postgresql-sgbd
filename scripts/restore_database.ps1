param(
    [Parameter(Mandatory = $true)]
    [string]$BackupFile,
    [string]$PgHost = "127.0.0.1",
    [int]$PgPort = 5432,
    [string]$PgUser = "postgres",
    [string]$TargetDatabase = "retail_inventory_restore_test",
    [switch]$RecreateTarget
)

$ErrorActionPreference = "Stop"

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "No se encontró '$Name' en PATH."
    }
}

Require-Command "pg_restore"
Require-Command "createdb"
Require-Command "dropdb"
Require-Command "psql"

if (-not (Test-Path $BackupFile)) { throw "No existe el respaldo: $BackupFile" }

$checksumFile = $BackupFile + ".sha256"
if (Test-Path $checksumFile) {
    $expected = (Get-Content $checksumFile -Raw).Trim().Split()[0]
    $actual = (Get-FileHash $BackupFile -Algorithm SHA256).Hash
    if ($expected -ne $actual) { throw "Checksum inválido. El respaldo puede estar corrupto." }
    Write-Host "Checksum SHA-256 verificado."
}
else {
    Write-Warning "No se encontró archivo .sha256; se continuará sin validación."
}

if ($TargetDatabase -eq "retail_inventory_db") {
    throw "Por seguridad no se restaura directamente sobre retail_inventory_db."
}

if ($RecreateTarget) {
    & dropdb "--host=$PgHost" "--port=$PgPort" "--username=$PgUser" "--if-exists" $TargetDatabase
    if ($LASTEXITCODE -ne 0) { throw "dropdb falló." }
    & createdb "--host=$PgHost" "--port=$PgPort" "--username=$PgUser" $TargetDatabase
    if ($LASTEXITCODE -ne 0) { throw "createdb falló." }
}

& pg_restore "--host=$PgHost" "--port=$PgPort" "--username=$PgUser" "--dbname=$TargetDatabase" "--clean" "--if-exists" "--verbose" $BackupFile
if ($LASTEXITCODE -ne 0) { throw "pg_restore finalizó con código $LASTEXITCODE." }

& psql "--host=$PgHost" "--port=$PgPort" "--username=$PgUser" "--dbname=$TargetDatabase" "--command=SELECT current_database() AS database, COUNT(*) AS productos FROM producto;"
if ($LASTEXITCODE -ne 0) { throw "La validación posterior a la restauración falló." }

Write-Host "Restauración de prueba completada correctamente."
Write-Host "Base destino: $TargetDatabase"
