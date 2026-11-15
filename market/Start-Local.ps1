[CmdletBinding()]
param(
    [string]$RuntimeRoot,
    [int]$PostgresPort = 55439,
    [int]$ApiPort = 8787,
    [int]$GrafanaPort = 3000
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $RuntimeRoot) { $RuntimeRoot = Join-Path $repo 'scratch\market-runtime' }
$runtime = [IO.Path]::GetFullPath($RuntimeRoot)
$python = Join-Path $repo '.venv-market\Scripts\python.exe'
$pg = Join-Path $runtime 'pgsql\bin'
$grafanaHome = Get-ChildItem -LiteralPath $runtime -Directory -Filter 'grafana-*' | Select-Object -First 1
if (-not $grafanaHome -or -not (Test-Path -LiteralPath (Join-Path $pg 'initdb.exe'))) { throw 'Download the documented PostgreSQL/Grafana runtimes first.' }
$local = Join-Path $PSScriptRoot '.local'
$data = Join-Path $local 'pgdata'
New-Item -ItemType Directory -Path $local -Force | Out-Null
$envFile = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
    & $python (Join-Path $PSScriptRoot 'configure.py') --directory $PSScriptRoot --server-url "http://localhost:$ApiPort"
    if ($LASTEXITCODE) { throw 'Configuration generation failed.' }
}
$settings = @{}
foreach ($line in Get-Content -LiteralPath $envFile) {
    if ($line -match '^([A-Z_]+)=(.*)$') { $settings[$Matches[1]] = $Matches[2] }
}
if (Test-Path -LiteralPath (Join-Path $local 'processes.json')) { throw 'Local runtime already configured. Use Stop-Local.ps1 before starting it again.' }
foreach ($port in @($PostgresPort,$ApiPort,$GrafanaPort)) {
    if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) { throw "Local port $port is already in use." }
}
$passwordFile = Join-Path $local 'postgres-password.txt'
[IO.File]::WriteAllText($passwordFile, $settings.ADMIN_PASSWORD)
if (-not (Test-Path -LiteralPath (Join-Path $data 'PG_VERSION'))) {
    $init = Start-Process -FilePath (Join-Path $pg 'initdb.exe') -ArgumentList @('-D',"`"$data`"",'-U','market_admin','--pwfile',"`"$passwordFile`"",'--auth','scram-sha-256','--locale=C','-E','UTF8') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $local 'initdb.log') -RedirectStandardError (Join-Path $local 'initdb-error.log')
    if ($init.ExitCode) { throw 'PostgreSQL initialization failed; see .local/initdb-error.log.' }
}
$start = Start-Process -FilePath (Join-Path $pg 'pg_ctl.exe') -ArgumentList @('-D',"`"$data`"",'-l',('"' + (Join-Path $local 'postgres.log') + '"'),'-o',"`"-p $PostgresPort -h 127.0.0.1`"",'-w','start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $local 'pgctl.log') -RedirectStandardError (Join-Path $local 'pgctl-error.log')
if (-not $start.WaitForExit(30000)) { throw 'PostgreSQL startup command timed out.' }
if ($start.ExitCode) { throw 'PostgreSQL start failed; see .local/pgctl-error.log.' }
$env:PGPASSWORD = $settings.ADMIN_PASSWORD
$databaseExists = & (Join-Path $pg 'psql.exe') -h 127.0.0.1 -p $PostgresPort -U market_admin -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='profit_market'"
if (-not $databaseExists) {
    & (Join-Path $pg 'createdb.exe') -h 127.0.0.1 -p $PostgresPort -U market_admin profit_market
    if ($LASTEXITCODE) { throw 'Could not create the local market database.' }
}
Remove-Item Env:PGPASSWORD
$env:ADMIN_DATABASE_URL = "postgresql://market_admin:$($settings.ADMIN_PASSWORD)@127.0.0.1:$PostgresPort/profit_market"
$env:WRITER_PASSWORD = $settings.WRITER_PASSWORD
$env:READER_PASSWORD = $settings.READER_PASSWORD
$env:GRAFANA_DB_PASSWORD = $settings.GRAFANA_DB_PASSWORD
Push-Location $repo
try { & $python -m market.bootstrap; if ($LASTEXITCODE) { throw 'Database bootstrap failed.' } }
finally { Pop-Location }
$env:DATABASE_URL = "postgresql://market_writer:$($settings.WRITER_PASSWORD)@127.0.0.1:$PostgresPort/profit_market"
$env:UPLOAD_TOKEN = $settings.UPLOAD_TOKEN
$api = Start-Process -FilePath $python -ArgumentList @('-m','uvicorn','market.server:app','--host','127.0.0.1','--port',"$ApiPort",'--limit-concurrency','16') -WorkingDirectory $repo -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $local 'receiver.log') -RedirectStandardError (Join-Path $local 'receiver-error.log')
$provision = Join-Path $local 'provisioning'
New-Item -ItemType Directory -Path (Join-Path $provision 'datasources'),(Join-Path $provision 'dashboards') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'grafana\provisioning\datasources\postgres.yaml') -Destination (Join-Path $provision 'datasources\postgres.yaml') -Force
$dashboardPath = (Join-Path $PSScriptRoot 'grafana\dashboards').Replace('\','/')
[IO.File]::WriteAllText((Join-Path $provision 'dashboards\market.yaml'), "apiVersion: 1`nproviders:`n  - name: Profit Market`n    folder: Profit Market`n    type: file`n    editable: false`n    options:`n      path: '$dashboardPath'`n")
$env:GF_SERVER_HTTP_ADDR = '127.0.0.1'
$env:GF_SERVER_HTTP_PORT = "$GrafanaPort"
$env:GF_SERVER_ROOT_URL = "http://localhost:$GrafanaPort/"
$env:GF_PATHS_DATA = Join-Path $local 'grafana-data'
$env:GF_PATHS_LOGS = Join-Path $local 'grafana-logs'
$env:GF_PATHS_PROVISIONING = $provision
$env:GF_SECURITY_ADMIN_USER = 'admin'
$env:GF_SECURITY_ADMIN_PASSWORD = $settings.GRAFANA_ADMIN_PASSWORD
$env:GF_SECURITY_SECRET_KEY = $settings.GRAFANA_SECRET_KEY
$env:GF_AUTH_ANONYMOUS_ENABLED = 'true' # Localhost-only demonstration, Viewer role.
$env:GF_AUTH_ANONYMOUS_ORG_ROLE = 'Viewer'
$env:GF_USERS_ALLOW_SIGN_UP = 'false'
$env:GF_DATABASE_TYPE = 'postgres'
$env:GF_DATABASE_HOST = "127.0.0.1:$PostgresPort"
$env:GF_DATABASE_NAME = 'profit_grafana'
$env:GF_DATABASE_USER = 'market_grafana'
$env:GF_DATABASE_PASSWORD = $settings.GRAFANA_DB_PASSWORD
$env:GF_DATABASE_SSL_MODE = 'disable'
$env:MARKET_DB_HOST = "127.0.0.1:$PostgresPort"
$env:MARKET_READER_PASSWORD = $settings.READER_PASSWORD
$grafana = Start-Process -FilePath (Join-Path $grafanaHome.FullName 'bin\grafana.exe') -ArgumentList @('server','--homepath',('"' + $grafanaHome.FullName + '"')) -WorkingDirectory $grafanaHome.FullName -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $local 'grafana.log') -RedirectStandardError (Join-Path $local 'grafana-error.log')
$state = [ordered]@{repo=$repo; pgdata=$data; pgctl=(Join-Path $pg 'pg_ctl.exe'); apiPid=$api.Id; apiStarted=$api.StartTime.ToUniversalTime().ToString('o'); grafanaPid=$grafana.Id; grafanaStarted=$grafana.StartTime.ToUniversalTime().ToString('o'); apiPort=$ApiPort; grafanaPort=$GrafanaPort; postgresPort=$PostgresPort}
[IO.File]::WriteAllText((Join-Path $local 'processes.json'), ($state | ConvertTo-Json))
Write-Output "Started local PostgreSQL, receiver and Grafana. Dashboard: http://localhost:$GrafanaPort/d/profit-market"
Write-Output 'Processes are local test helpers, not installed Windows services. Stop them with market/Stop-Local.ps1.'
