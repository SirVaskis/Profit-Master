[CmdletBinding()]
param([string]$Python)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Python) { $Python = Join-Path $repo '.venv-market\Scripts\python.exe' }
Push-Location $repo
try {
    & $Python -m PyInstaller --noconfirm --onefile --clean --name ProfitMarketClient --paths $repo --distpath market/dist --workpath market/build --specpath market/build market/client_main.py
    if ($LASTEXITCODE -ne 0) { throw 'Windows client build failed.' }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'client-config.example.json') -Destination (Join-Path $PSScriptRoot 'dist\client-config.example.json') -Force
    Write-Output 'Built market/dist/ProfitMarketClient.exe. It requires no Python installation.'
} finally { Pop-Location }
