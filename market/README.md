# Profit Market 0.1.0

Windows collector → HTTPS receiver → PostgreSQL → provisioned Grafana dashboard.
Both addons keep working independently. The external application only reads
SavedVariables after WoW saves them on a player-initiated `/reload` or logout.
It does not control WoW, read game memory, execute Lua, or accelerate AH requests.
This first version is a console application, not a tray application or Windows service.

## Current demonstration

The local stack is at **http://localhost:3000/d/profit-market?kiosk**.
It defaults to Trade Goods with AH category/subcategory filters, up to 12 item
line charts per page, and a separate material-comparison view. The comparison
uses one line per item; use the legend to hide individual materials. Recent
price, period change and the high/low appear in chart legends. Timestamps are UTC.
The view takes visual cues from WoW Price Hub's token charts, without copying
its assets or adding its token, sales, alerts or forecast features.

A real save supplied 109,091 Profit Master daily quote slots. Those records are
archived but **do not appear as averages**. No valid trimmed averages exist in
the inspected real save yet. Two ProfitTop records and twelve average records
for three fake item IDs were uploaded explicitly for local UI/compatibility QA
under `CompatibilityFixture-Alliance`; they are synthetic, not live scans.
They are not automatically seeded on a deployed server.

PostgreSQL 18.7, Grafana 13.3.1 and the receiver were run natively on Windows.
Data survived a stack restart. Twenty-four new offline/integration tests and the
existing 31 parser/SQL tests passed. Compose configuration was validated with
Compose 5.7.1. **Docker images have not been built or run here: this PC has no
Docker or WSL.** Container startup remains a server-host acceptance check.

## Compatibility and price meaning

| Saved source | Accepted schema | Imported measurements |
| --- | --- | --- |
| `ProfitMaster.lua`, current addon 0.2.2 | `ProfitMasterDB.version = 1` | Daily low/high/latest quotes, sample counts, item/vendor/category metadata; validated trimmed scan rollups when present |
| `ProfitTop.lua`, supplied addon 0.1.13 | `ProfitTopDB.version = 3` | Browse floors (`b`), sampled listing VWAP (`l`), with retained legacy floor/listing history as a fallback |

Unknown schemas fail clearly without deleting queued data. ProfitTop private
purchase snapshots (`p`), account paths, debug logs, settings and acquisition
costs are not sent. The parser supports literal tables and never executes Lua.
The raw source file stays on the client. A source hash and persistent random
client/source identities are sent to make retries and corrections identifiable.
Contributor identity is assigned by the receiver's upload key.

All prices are **copper per item**; fractional copper averages are retained as
PostgreSQL numeric values. These are asking prices, not completed sales.
ProfitTop VWAP units describe its sampled listings, not all listed inventory or
sales volume. Market keys and item variants remain separate exactly as saved.
No realm/faction equivalence between the two addons is assumed.

The Daily trimmed average mode only uses explicitly saved unit-weighted scan means
with 10% removed from each tail. The average of averages gives each completed
scan equal weight (`SUM(mean_sum) / SUM(scan_count)`). Daily latest quotes and
ProfitTop VWAPs cannot supply that statistic. The current real save has no valid
trimmed rollups, so the real market's average charts correctly show no data.
Daily rollups use sum/count, not the last scan's mean. Pricing methods and item
variants stay separate. Multiple saved source revisions never add a cumulative
day's scan counts twice. This is scan activity, not a measure of completed sales.

Profit Master 0.2.2 captures item class/subclass IDs and names using its existing
GetItemInfo call, with no extra item loads or AH requests. The receiver shares
that catalog with ProfitTop observations for the same item IDs. A ProfitTop-only
server has unclassified items until it receives category metadata from a Profit
Master contributor. Old items are not categorized by guessing from their names.
After updating Profit Master, the player must reload, scan, then reload/logout
to save new metadata. Full distributions are required for trimmed averages;
quick/browse scans cannot supply them.

Each price row keeps the source observation time, file-save revision and server
receipt separately. Both formats carry UTC observation timestamps. Older Profit
Master daily rollups retain the latest scan time for that day and cannot be
expanded into individual historical scan timestamps or per-scan prices.

Version 0.2.2 additionally retains each successfully completed full-distribution
scan's UTC timestamp once per daily bucket. The collector sends these separately
to `market.scan_times`, with idempotent storage independent of upload receipt
time. ProfitTop's saved snapshot timestamps are also retained, excluding private
purchases. New scan markers do not invent missing historic prices. A timestamp
update alone is uploaded without creating a new price slot. Daily average chart
points remain daily aggregates; they are not falsely expanded into per-scan prices.

## Windows client

Unzip the Windows client package into a user-owned folder. It contains
`ProfitMarketClient.exe`, `client-config.example.json` and these instructions.
No Python or Docker installation is needed to run the EXE. The EXE is currently
unsigned; signing and a GUI installer are outside this first version.

Copy the example to `client-config.json`. Set `server_url` to the receiver's
HTTPS origin and `token` to its private upload key. Set `game_root` to the client
directory containing `WTF`, or set `saved_files` to explicit absolute paths and
remove `game_root`. Discovery checks all account-level saves for both addons;
only list the intended account's files if you use several accounts.

Run from PowerShell in that folder:

```powershell
.\ProfitMarketClient.exe inspect "C:\path\to\SavedVariables\ProfitMaster.lua"
.\ProfitMarketClient.exe --config .\client-config.json sync
.\ProfitMarketClient.exe --config .\client-config.json watch
.\ProfitMarketClient.exe status
```

`inspect` reads and validates without uploading. `sync` uploads once. `watch`
watches completed file writes every five seconds until Ctrl+C. It reads the
latest data only after the player saves it; an in-game scan alone does not write
the disk file. No automatic game reload is performed.

State is stored under `%LOCALAPPDATA%\ProfitMarket\collector.sqlite` by default.
Keep this file across upgrades: it contains persistent identities, record
digests and a compressed retry queue. Use `--state C:\path\collector.sqlite`
before the command to select another location. Run one collector per state file.
Transient failures retain the upload, with retries capped at five-minute delays.
An unchanged save is skipped; debug-only changes send no market records.
Changed records are sent in parts of at most 2,000. A part leaves the queue only
after its matching accepted/duplicate acknowledgment. Keep the same state when
moving a client installation. Moving native save paths changes source identity.

Protect `client-config.json` and the SQLite state; do not publish either.
Remote HTTP is rejected by default. Loopback HTTP is allowed for local testing.

## Linux Docker server handoff

Prerequisites: Docker Engine with Compose, and an existing HTTPS reverse proxy
for remote access. Extract the **server ZIP root**, preserving `.dockerignore`,
`market/` and `tools/`. Run these commands from the extracted root:

```sh
python3 market/configure.py --directory market --server-url https://market.example.com
docker compose --env-file market/.env -f market/compose.yaml config --quiet
docker compose --env-file market/.env -f market/compose.yaml up -d --build
docker compose --env-file market/.env -f market/compose.yaml ps -a
curl --fail http://127.0.0.1:8787/healthz
curl --fail http://127.0.0.1:3000/api/health
```

Python 3.10+ is sufficient for the one-time configuration generator; containers
use Python 3.14.6. Alternatively generate credentials with PowerShell 7 using
`market/New-Config.ps1 -ServerUrl https://market.example.com`. Both generators
preserve existing configuration and print no secrets.

The one-time `migrate` container should exit **0**. It initializes the schema,
writer/reader roles and Grafana's separate metadata database; the receiver and
Grafana start only after it succeeds. PostgreSQL is not published to a host port.
The receiver and Grafana are published only on host loopback, on ports 8787 and
3000 by default. Named volumes preserve PostgreSQL and Grafana state.

Edit private `market/.env` to set `GRAFANA_ROOT_URL` to the actual HTTPS Grafana
origin. Keep `GRAFANA_ANONYMOUS=false` for the server. Sign in as `admin` using
`GRAFANA_ADMIN_PASSWORD` from that private file; create normal Viewer access as
needed. The dashboard is at `/d/profit-market`. A fresh server correctly displays
no data until a collector uploads a save.

Configure the host reverse proxy with TLS to forward `/api/v1/uploads` to
`127.0.0.1:8787`, and the Grafana origin to `127.0.0.1:3000`. Preserve the
Authorization and Content-Encoding headers and gzip request bodies. Set a 2 MiB
request-body limit, an upload timeout of at least 30 seconds and a reasonable
per-key/IP request rate limit. The app independently caps compressed/expanded
bodies and concurrent requests. This package does not provision a domain,
certificate or internet-facing proxy. Do not expose PostgreSQL.

Securely deliver the generated **client-config.json only** to the collector
operator; it has no database credentials. `.env` remains on the server. The
initial key identifies one `pilot` contributor. For multiple contributors,
the receiver also accepts `UPLOAD_KEYS_JSON`, an object mapping contributor
labels to distinct random tokens of at least 32 characters. Supply it privately
in a Compose override/environment; never use a client-provided contributor label.
Back up `.env` with the data; Grafana's secret must remain stable across restarts.

Server acceptance check: run a real client `sync`, verify zero pending parts,
open the dashboard, select its addon/market/item, restart the stack and verify
the series remains. Repeating `sync` must not inflate the observation count.
No demo data is automatically seeded into a deployed server.

### Optional Docker collector

The client also has a Linux container target. Use
`market/compose.collector.yaml` on a Docker-capable client host. Copy
`client-config.docker.example.json` to a private location, add the HTTPS server
URL/token, and retain only the save paths actually present. Set absolute
`SAVED_VARIABLES_DIR` and `COLLECTOR_CONFIG` environment paths, then run:

```sh
docker compose -f market/compose.collector.yaml up -d --build
```

SavedVariables and config are mounted read-only; the queue uses its own named
volume. Container paths are `/saved/ProfitMaster.lua` and `/saved/ProfitTop.lua`,
not Windows paths. A remote server cannot read a Windows folder without this
collector or a separately configured file share. The Windows EXE is the intended
client on this PC, which does not have Docker.

## Storage, duplicates and operation

`market.uploads` stores committed part receipts; `market.observations` stores
one row per source/observation slot. A repeat batch is acknowledged without new
rows. Reusing its identity with different contents returns 409. A newer file
revision replaces its mutable daily slot; an older revision cannot replace it.
Historic slots absent from a later pruned addon save remain archived.
The import summary only marks a save/delta complete when all its parts commit.
An import is a saved-history transfer, not necessarily one scan.

Wire schema 1 uses decimal **strings** for prices. `snapshot_record_count` counts
the changed records in that transfer, not the total history on disk. Metadata
and updates within a part commit atomically before acknowledgment; different
parts commit independently and may appear in charts while an import is pending.
Rolling history, uploads and the client ledger currently have no retention limit;
decide an archive/retention policy before a public multi-contributor rollout.

The receiver has a writer role; Grafana's datasource can only read curated
`reporting` views, with a five-second SQL statement timeout. Grafana's own
configuration is held in separate `profit_grafana` PostgreSQL storage. That
keeps market ingestion credentials out of dashboard queries.

To stop containers while preserving data:

```sh
docker compose --env-file market/.env -f market/compose.yaml down
```

Do not use `down -v` if data must survive. For a backup, use PostgreSQL 18's
`pg_dump -Fc` for both `profit_market` and `profit_grafana`, using `market_admin`,
then protect those files and `.env`. Avoid redirecting binary dumps through
Windows PowerShell 5; use `pg_dump --file` inside the container, followed by
`docker cp`. A clean-host restore starts PostgreSQL with the same `.env`, runs
`migrate` to create roles/databases, restores each dump as `market_admin` using
`pg_restore --clean --if-exists`, reruns `migrate`, and then starts the apps.
Stop the apps while restoring. Test recovery before relying on backups.

## Source development and local verification

From repository root on Windows, using Python 3.14:

```powershell
py -3.14 -m venv .venv-market
.\.venv-market\Scripts\python.exe -m pip install -r market/requirements-server.txt -r market/requirements-build.txt
.\market\Build-Client.ps1
.\.venv-market\Scripts\python.exe -m unittest market.tests.test_pipeline -v
.\.venv-market\Scripts\python.exe -m unittest discover -s tools -p 'test_profit_master_*.py' -v
```

The native Windows demo helpers are optional development tools, not server
deployment. `Start-Local.ps1` expects the official portable PostgreSQL `pgsql/`
directory and Grafana `grafana-13.3.1/` under `scratch/market-runtime/`, or a
`-RuntimeRoot` containing them. It uses local ports 55439/8787/3000, private
`market/.env`, and `market/.local` for logs/data. It enables anonymous **Viewer**
only on loopback for the local demo. It installs no Windows services.

Official tested runtime downloads (verify SHA-256 before extracting):

| Runtime | Official binary | SHA-256 |
| --- | --- | --- |
| PostgreSQL 18.7 | [EDB Windows x64 binaries](https://get.enterprisedb.com/postgresql/postgresql-18.7-1-windows-x64-binaries.zip) | `ead0bbc27fb678fa24dcf86b738981323042abd073c744103bf7f3aed23f9a33` |
| Grafana 13.3.1 | [Grafana Windows amd64](https://dl.grafana.com/grafana/release/13.3.1/grafana_13.3.1_42849527790_windows_amd64.tar.gz) | `cb78dceb990948fe7f1a189a0737fa7f6cf212076fc139a57d48cbc45dc0393f` |

```powershell
.\market\Start-Local.ps1
.\.venv-market\Scripts\python.exe -m market.collector --config market/client-config.json --state market/.local/collector.sqlite sync
$env:MARKET_INTEGRATION = '1'
.\.venv-market\Scripts\python.exe -m unittest market.tests.test_integration -v
Remove-Item Env:MARKET_INTEGRATION
.\market\Stop-Local.ps1
```

Integration tests require that explicit flag and the native helper's local
configuration. They create unique synthetic producer identities and remove
only their own test rows. They check actual HTTP/PG transactions, duplicate ACKs,
conflicts, invalid/auth/gzip rejection, stale revision handling, rollback,
offline-queue recovery, reader restrictions and Grafana's real datasource query.
The Grafana assertion expects existing real Profit Master item 6040 history.
Unit tests use synthetic SavedVariables; raw user saves are never packaged.

Build handoff archives with `python -m market.package`. The packager uses an
explicit file list, verifies every ZIP entry and rejects private configuration,
saved data, local databases and comparison addon source. Inspect the generated
`market/dist/SHA256SUMS.txt` when sharing a build.
