[CmdletBinding()]
param([string]$ServerUrl = 'http://localhost:8787')
$ErrorActionPreference = 'Stop'
$envPath = Join-Path $PSScriptRoot '.env'
$clientPath = Join-Path $PSScriptRoot 'client-config.json'
if ((Test-Path -LiteralPath $envPath) -or (Test-Path -LiteralPath $clientPath)) {
    throw 'Existing configuration preserved. Edit it directly instead of generating new credentials.'
}
function New-Secret {
    $bytes = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    [Convert]::ToHexString($bytes).ToLowerInvariant()
}
$names = 'ADMIN_PASSWORD','WRITER_PASSWORD','READER_PASSWORD','GRAFANA_DB_PASSWORD','GRAFANA_ADMIN_PASSWORD','GRAFANA_SECRET_KEY','UPLOAD_TOKEN'
$settings = @{}
foreach ($name in $names) { $settings[$name] = New-Secret }
$lines = foreach ($name in $names) { "$name=$($settings[$name])" }
$lines += 'API_PORT=8787','GRAFANA_PORT=3000','GRAFANA_ROOT_URL=http://localhost:3000/','GRAFANA_ANONYMOUS=false'
[IO.File]::WriteAllLines($envPath, $lines)
$client = [ordered]@{server_url=$ServerUrl; token=$settings.UPLOAD_TOKEN; game_root='C:/Program Files (x86)/World of Warcraft/_forever_'; saved_files=@(); poll_seconds=5}
[IO.File]::WriteAllText($clientPath, ($client | ConvertTo-Json -Depth 3))
Write-Output 'Created private .env and client-config.json. Credentials were not printed; do not commit or distribute these files.'
