# Borra y vuelve a crear la base en el PostgreSQL local, y aplica las migraciones en orden.
# Uso:  .\scripts\recrear_bd.ps1            (psql pide la contraseña)
#       $env:PGPASSWORD = '...'; .\scripts\recrear_bd.ps1
param(
    [string]$Base = 'bodegas_atuel',
    [string]$Usuario = 'postgres',
    [string]$Puerto = '5432'
)

$ErrorActionPreference = 'Stop'
$psql = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'
$raiz = Split-Path -Parent $PSScriptRoot

& $psql -U $Usuario -p $Puerto -d postgres -v ON_ERROR_STOP=1 `
    -c "DROP DATABASE IF EXISTS $Base WITH (FORCE);" -c "CREATE DATABASE $Base;"
if ($LASTEXITCODE -ne 0) { throw 'No se pudo recrear la base' }

foreach ($archivo in Get-ChildItem "$raiz\db\migrations\*.sql" | Sort-Object Name) {
    Write-Host "== $($archivo.Name)"
    & $psql -U $Usuario -p $Puerto -d $Base -v ON_ERROR_STOP=1 -q -f $archivo.FullName
    if ($LASTEXITCODE -ne 0) { throw "Fallo $($archivo.Name)" }
}
Write-Host 'Migraciones aplicadas sin errores.'
