[CmdletBinding()]
param(
    [string]$SavedVariables,
    [string]$Database
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
if (-not $Database) { $Database = Join-Path $workspace 'data\ProfitMaster\market-history.sqlite' }
if (-not $SavedVariables) {
    $settings = Get-Content -LiteralPath (Join-Path $workspace 'project.json') -Raw | ConvertFrom-Json
    $accountRoot = Join-Path $settings.gameRoot 'WTF\Account'
    $candidates = @(Get-ChildItem -LiteralPath $accountRoot -Directory | ForEach-Object {
        $savedPath = Join-Path $_.FullName 'SavedVariables\ProfitMaster.lua'
        if (Test-Path -LiteralPath $savedPath -PathType Leaf) { $savedPath }
    })
    if ($candidates.Count -ne 1) {
        throw 'Specify -SavedVariables with the account file to import; exactly one was not found.'
    }
    $SavedVariables = $candidates[0]
}
$python = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$pythonArguments = @()
if ($python) { $pythonArguments = @('-3') }
else { $python = Get-Command python.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1 }
& $python.Source @pythonArguments (Join-Path $PSScriptRoot 'ProfitMasterHistory.py') --database $Database import --saved $SavedVariables
if ($LASTEXITCODE -ne 0) { throw 'Profit Master history import failed; see the error above.' }
