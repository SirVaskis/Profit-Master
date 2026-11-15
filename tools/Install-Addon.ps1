[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$Name,
    [string]$GameRoot
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Validate-Addon.ps1') -Name $Name
$workspace = Split-Path -Parent $PSScriptRoot
if (-not $GameRoot) {
    $settings = Get-Content -LiteralPath (Join-Path $workspace 'project.json') -Raw | ConvertFrom-Json
    $GameRoot = $settings.gameRoot
}
$client = [IO.Path]::GetFullPath($GameRoot)
if (-not (Test-Path -LiteralPath $client -PathType Container)) { throw "Client folder is missing: $client" }
$addons = [IO.Path]::GetFullPath((Join-Path $client 'Interface\AddOns'))
$destination = [IO.Path]::GetFullPath((Join-Path $addons $Name))
if (-not $destination.StartsWith($addons.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Installation target must stay inside the specified Interface\AddOns folder.'
}
if ((Test-Path -LiteralPath $destination) -and
    (Get-Item -LiteralPath $destination).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
    throw 'Installation target must not be a symbolic link or junction.'
}
if ($PSCmdlet.ShouldProcess($destination, 'Back up existing addon and copy staged source files')) {
    if (Test-Path -LiteralPath $destination) {
        $backups = Join-Path $workspace 'backups'
        New-Item -ItemType Directory -Path $backups -Force | Out-Null
        $backup = Join-Path $backups "$Name-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff').zip"
        Compress-Archive -LiteralPath $destination -DestinationPath $backup
        Write-Output "Backup: $backup"
    }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath (Join-Path $workspace "addons\$Name") -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force
    }
    Write-Output "Installed $Name. WoW has not been controlled or reloaded."
}
