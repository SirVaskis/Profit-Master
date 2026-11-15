[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$statePath = Join-Path $PSScriptRoot '.local\processes.json'
if (-not (Test-Path -LiteralPath $statePath)) { Write-Output 'No local process record exists.'; return }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
foreach ($name in 'api','grafana') {
    $processId = $state.($name + 'Pid')
    $expectedStart = [datetime]$state.($name + 'Started')
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($process -and $process.StartTime.ToUniversalTime() -eq $expectedStart.ToUniversalTime()) {
        $resolved = [IO.Path]::GetFullPath($process.Path)
        if (-not $resolved.StartsWith(([IO.Path]::GetFullPath($state.repo).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Process executable is outside this checkout; preserved.' }
        Stop-Process -Id $processId
    }
}
$pgdata = [IO.Path]::GetFullPath($state.pgdata)
$allowed = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.local')).TrimEnd('\') + '\'
if (-not $pgdata.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw 'PostgreSQL data path is outside the local test folder; preserved.' }
$stop = Start-Process -FilePath $state.pgctl -ArgumentList @('-D',('"' + $pgdata + '"'),'-w','-m','fast','stop') -WindowStyle Hidden -Wait -PassThru
if ($stop.ExitCode) { throw 'Local PostgreSQL could not stop cleanly.' }
Remove-Item -LiteralPath $statePath
Write-Output 'Stopped local receiver, Grafana and PostgreSQL. Data and credentials were preserved.'
