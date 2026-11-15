# Profit Master SQL market history

Profit Master now has a local SQLite archive at
`C:\src\WoWForeverAddons\data\ProfitMaster\market-history.sqlite`.
It uses the existing Python installation and its bundled SQLite support; there
is no server, dependency installation or background process.

The companion imports the last completed WoW SavedVariables write. The addon
cannot directly open/query SQLite: gameplay still uses its current Lua tables.
This archive does not change in-game RAM usage, scan requests, purchase behavior
or the addon's existing 30-day retention. No addon update/reinstall is needed.
WoW's own `/reload` or normal logout flushes its current saved data. Import after
that write finishes, before another 30 days of unarchived data can be pruned.

## Update the archive

From `C:\src\WoWForeverAddons`, after your `/reload` or logout:

```powershell
.\tools\Import-ProfitMasterHistory.ps1
```

The helper reads `project.json` and finds the account's existing
`SavedVariables\ProfitMaster.lua`. If more than one account file exists, choose
one explicitly:

```powershell
.\tools\Import-ProfitMasterHistory.ps1 -SavedVariables 'C:\path\to\SavedVariables\ProfitMaster.lua'
```

`-Database` selects another archive. Imports are manual; no watcher, scheduled
task or service was installed. The native save is opened read-only. One bounded
bytes buffer is parsed as literal data, never evaluated as Lua. Its size/mtime
are checked across reading, and the SHA-256 identifies successful imports.
Malformed, unsupported, executable or excessively large/deep input is rejected.

Each resolved account-file path has its own source ID. Reimporting an already
imported snapshot is a no-op, including an A → B → A sequence. Updated cumulative
daily rows replace the earlier saved totals rather than being added again.
Archived days/variants missing from a later save remain in SQL. Older timestamps,
decreasing counts and conflicting equal-count aggregates are preserved and
reported in `skipped_rows`; inspect those before relying on a restored/reset
save. Without an addon generation ID, arbitrary resets/branched histories cannot
always be distinguished from normal growth. A moved/copied source path becomes
a separate source, so accounts and copied backup files cannot silently merge.

All accepted changes and the successful-import ledger commit in one transaction.
Import output counts describe rows present in the input; `skipped_rows` counts
daily rows deliberately left unchanged. `unchanged: true` means that exact source
snapshot was already imported.

## Query it

Any SQLite client can open the archive. The included query command opens it
read-only, denies mutating SQL/attachments, limits output to 1,000 rows, and
interrupts queries taking more than approximately five seconds:

```powershell
py -3 tools/ProfitMasterHistory.py summary
py -3 tools/ProfitMasterHistory.py query --sql "SELECT market, item_id, variant, average_copper, scan_count, days FROM market_averages WHERE item_id = 6040"
py -3 tools/ProfitMasterHistory.py query --sql "SELECT date(utc_day * 86400, 'unixepoch') AS utc_date, market, variant, low, high, last, samples FROM daily_quotes WHERE item_id = 6040 ORDER BY utc_day DESC"
```

For another database, put `--database 'C:\path\archive.sqlite'` before
`summary`, `query` or `import`. All prices are copper per item; fractional copper
is retained. Days are UTC day numbers, not local calendar dates. The example
item 6040 is Golden Scale Bracers.

Tables:

| Table/view | Meaning |
|---|---|
| `sources` | Resolved source paths; accounts/client files stay separate |
| `imports` | Successful snapshot hashes, write/import times and row counts |
| `items` | Observed item names and latest verified vendor quotes; zero differs from unknown |
| `daily_quotes` | Legacy low/high/latest quote and observation counts, by source/market/day/exact history key |
| `daily_trimmed` | Daily sum/count of completed scan means plus latest-scan details |
| `market_averages` | Equal-scan average across archived days, separately per source/market/item/key |

Browse keys preserve item level, suffix and pet fields. Replicate keys are broader
item-ID observations and remain separate. Legacy `samples` are observed quotes,
not units or completed sales. Legacy low/high/latest data cannot recover a
historical arithmetic or trimmed mean and never feeds the averages view.

For completed full snapshots, the addon already normalizes stacks to unit price,
trims exactly 10% of units from each price tail and calculates the middle-80%
mean. SQL imports those daily cumulative rollups as-is. `market_averages` uses:

```sql
SUM(mean_sum) * 1.0 / SUM(scan_count)
```

This weights every completed scan equally, rather than every day or every unit
across scans. Latest units/retained units describe only the latest scan and never
weight the average of means. These are asking-price statistics, not completed
sales. No missing historical means are fabricated.

## Validation and initial import

Implementation uses Python 3.14.6 / SQLite 3.50.4 already installed here. The
Python [SQLite documentation](https://docs.python.org/3.14/library/sqlite3.html)
and SQLite [UPSERT reference](https://sqlite.org/lang_upsert.html) were checked.
WoW sandbox/SavedVariables boundary is documented in the primary author
[Lua workshop presentation](https://www.lua.org/wshop08/lua-whitehead.pdf)
(historical background, pages 8/16/18), alongside the pinned 70938 addon-loading
and SavedVariables declarations already verified for this workspace.

Offline checks cover strict literal parsing, repeat imports, source/market/key
isolation, daily replacement, preserved old days, fractional prices, equal-scan
weighting, regressions, atomic rejection and read-only queries. Real-file smoke
import read 6,845,896 bytes: 6,285 catalog items and 45,236 daily quote rows, with
no skipped rows and no trimmed rollup rows. Source SHA-256 before/after was
`1BB03BF7E2302F58797ACBA73137CCC43C3256EEFDD66DECC70894AF05CD637E`.

The production archive was created at the path above: 5,771,264 bytes (5.50 MiB),
one source, one imported snapshot, 6,285 items and 45,236 quote rows spanning
2026-11-12 through 2026-11-13 UTC. It contains 1,140,984 observed quotes, not that
many distinct listings or sales. No trimmed means exist in this saved snapshot,
so the averages view correctly returns no estimate yet. A repeated real-file
import reported `unchanged: true`; SQLite integrity check returned `ok`.

All 31 offline unittest cases passed (17 literal-parser and 14 SQL/import cases),
including a forced mid-transaction SQLite error proving prior item/quote changes
and the import ledger roll back together. The PowerShell wrapper and read-only
summary/query commands were exercised against the real snapshot. No addon,
installed addon file or native SavedVariables file was modified. The database
and Python bytecode caches are ignored by Git.

## Archive check — 2026-11-15

The user requested a database status check. SQLite was healthy but its only
import was still November 13. The native SavedVariables file had newer scans;
it changed again during inspection as the client wrote another snapshot.
The existing import helper imported the newer completed buffer with SHA-256
`B263DDA71AFE2A682176A88085549D7D72780F68AE13E254583A3A2BEC2DA8FB`.
A consistent SQLite backup was created first at
`backups/ProfitMasterHistory-20261115-132445.sqlite`.

After the import: 106,159 daily quote rows, 1,864,225 quote observations, 6,863
catalog items, four UTC days (November 12–15), and two successful import snapshots.
There were no skipped/conflicting rows. SQLite occupies 13,754,368 bytes
(13.11 MiB); integrity check is `ok`, with zero foreign-key violations.

Trimmed rollups and average-of-averages rows remain zero. The earlier 11:52 save
contained recent completed browse scans and a canceled full-replicate attempt.
The newer imported 13:24 save contains a completed full scan (#23605): 181,975
listings, 181,957 priced, zero unavailable, history_rows=304/history_means=0.
Its status (#23603) explicitly reports "Trimmed means not saved: incomplete
price snapshot." The scan took 60.220s wall / 59.088s provider / 2.982s batches
(overlapping scopes). No vendor loads were needed. Thus merely requesting
another full scan is not an established remedy: distribution capture rejected
this completed scan after 304 rows. Existing logs do not distinguish an invalid
numeric row from snapshot count/generation changes during reconciliation.

SQL correctly imports zero averages because the addon saved none. The next
history priority is identifying that capture abort and obtaining validated
rollups before the averages view can produce estimates. The archive is manually
synced; this check does not install continuous synchronization or change in-game
retention, addon code or native SavedVariables.
