[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$Name)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Validate-Addon.ps1') -Name $Name
$workspace = Split-Path -Parent $PSScriptRoot
$source = Join-Path $workspace "addons\$Name"
$versionLine = Get-Content -LiteralPath (Join-Path $source "$Name.toc") |
    Where-Object { $_ -match '^## Version:\s*(\S+)' } | Select-Object -First 1
$version = ($versionLine -replace '^## Version:\s*', '').Trim()
if ($version -notmatch '^[A-Za-z0-9._-]+$') { throw 'Version contains unsafe filename characters.' }
$dist = Join-Path $workspace 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$archive = Join-Path $dist "$Name-$version.zip"
Compress-Archive -LiteralPath $source -DestinationPath $archive -Force
Write-Output "Packaged $archive"
