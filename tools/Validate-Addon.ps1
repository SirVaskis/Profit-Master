[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$Name)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$source = Join-Path $workspace "addons\$Name"
$manifest = Join-Path $source "$Name.toc"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "Missing manifest: $manifest" }
if (Get-ChildItem -LiteralPath $source -Recurse -Attributes ReparsePoint) {
    throw 'Addon source must not contain symbolic links or junctions.'
}
$lines = Get-Content -LiteralPath $manifest
if (-not ($lines -match '^## Interface:\s*\d+')) { throw 'Missing Interface metadata.' }
if (-not ($lines -match '^## Version:\s*\S+')) { throw 'Missing Version metadata.' }
$prefix = [IO.Path]::GetFullPath($source).TrimEnd('\') + '\'
$listed = 0
foreach ($line in $lines) {
    $entry = $line.Trim()
    if (-not $entry -or $entry.StartsWith('#')) { continue }
    $file = [IO.Path]::GetFullPath((Join-Path $source $entry))
    if (-not $file.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest entry escapes addon folder: $entry"
    }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing manifest file: $entry" }
    $listed++
}
if ($listed -eq 0) { throw 'The manifest lists no addon files.' }
foreach ($file in Get-ChildItem -LiteralPath $source -Filter '*.xml' -Recurse -File) {
    try { [xml](Get-Content -LiteralPath $file.FullName -Raw) | Out-Null }
    catch { throw "Invalid XML in $($file.FullName): $_" }
}
$compiler = Get-Command luac -ErrorAction SilentlyContinue
if ($compiler) {
    foreach ($file in Get-ChildItem -LiteralPath $source -Filter '*.lua' -Recurse -File) {
        & $compiler.Source -p $file.FullName
        if ($LASTEXITCODE -ne 0) { throw "Lua syntax check failed: $($file.FullName)" }
    }
} else {
    Write-Warning 'luac is unavailable. Manifest/XML checks passed; Lua syntax and in-game behavior are not verified by this helper.'
}
Write-Output "Validated $Name manifest and $listed listed file(s)."
