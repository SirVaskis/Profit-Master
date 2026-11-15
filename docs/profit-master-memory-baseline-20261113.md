# Profit Master saved-data baseline — 2026-11-13

This is an **offline measurement of saved data**, not WoW's RAM usage or native
addon memory attribution. WoW's live tables and native item cache can differ from
the last file written on logout/reload. No game input, native extension, additional
cache, installation or SavedVariables change was used for this measurement.

## Input snapshots

The requested 15:06 snapshot became the game's `.bak` file while this analysis was
in progress. Both files were measured read-only; SHA-256 hashes remained unchanged
across the successful measurements. Filesystem times below are local Berlin time.

| | Current `ProfitMaster.lua` | Native `ProfitMaster.lua.bak` |
|---|---:|---:|
| Last written | 2026-11-13 15:29:34 | 2026-11-13 15:06:07 |
| File bytes | 7,205,771 | 6,948,894 |
| File MiB | 6.872 | 6.627 |
| Item records | 6,282 | 6,270 |
| Verified vendor values | 6,278 | 6,266 |
| Known zero vendor values | 171 | 171 |
| Markets / stored UTC days | 1 / 2 | 1 / 2 |
| UTC history dates | Nov 12–13 | Nov 12–13 |
| Legacy daily price rows | 45,024 | 44,405 |
| Legacy observation samples | 1,086,854 | 788,760 |
| Trimmed rollup rows / snapshots | 0 / 0 | 0 / 0 |
| Retained diagnostic events | 1,000 | 1,000 |
| Retained event sequences | 8,252–9,251 | 4,997–5,996 |

Both saved tables use schema version 1, have debugging/disenchant mode enabled,
and contain no `minimumProfit` field. These are saved preferences, not a live UI
inspection. Existing legacy rows do not establish that trimmed averages exist.

Current SHA-256:
`8B30DA69BDDA33AEEA42BC1EB494A4F860D27AD1A0DB7C29017D7B1CAE802E5B`

Backup SHA-256:
`4C0497EA1744ABDEBD04BC15828B7D55EB1F416C33D0B78AB536EE49174A9838`

## Offline Lua heap

Measured with the existing OBS `lua51.dll` through `tools/Run-LuaChecks.py`, with
LuaJIT disabled. This runtime implements Lua 5.1 semantics but has different
allocation/layout/sharing behavior from WoW. Values below are retained Lua heap
deltas after releasing compiled/input data and collecting garbage to stability.
They exclude UI frames, textures, native item records, temporary scan histograms,
and the game process's other allocations.

| Retained data | Current | Backup |
|---|---:|---:|
| All three saved roots, measured by release | 16.512 MiB | 16.178 MiB |
| Main database, marginal release | 16,746.895 KiB | 16,403.723 KiB |
| Debug ring, marginal release | 160.840 KiB | 162.270 KiB |
| Disenchant settings, marginal release | 0.109 KiB | 0.109 KiB |

Current main-database breakdown:

| Subtree | Marginal release |
|---|---:|
| `db.items` — item/vendor catalog | 2,061.281 KiB / **2.013 MiB** |
| `db.markets` — daily observations | 14,685.457 KiB / **14.341 MiB** |
| Remaining main table | 0.156 KiB |

Release order was settings → debug → items → markets → remaining main table.
Shared strings and allocator effects are charged to whichever subtree releases
them last; these are approximate partitions. The independent load-minus-prior-GC
baseline check was 16,913.242 KiB for the current file and 16,571.453 KiB for the
backup, within about 5.4 KiB of the root-release totals. The current catalog is
about 2 MiB in this offline runtime; most retained saved-data heap is daily history.

## What the existing timings establish

| Latest retained completed scan | Current | Backup |
|---|---:|---:|
| Source | replicate | replicate |
| Completion sequence | 9,233 | 5,870 |
| Prepared source rows | 131,736 | 133,707 |
| Recorded whole-scan wall span | 44.270s | 42.841s |
| Recorded provider span | 43.290s | 42.052s |
| Accumulated valuation batch time | 2.259s | 2.220s |
| History finalization time | 0.004s | 0.004s |

The ring no longer contains either completed scan's start or vendor-load events.
Missing retained vendor events **does not mean vendor loading took zero time**.
The current completed scan explicitly reports an incomplete price snapshot and
zero saved trimmed means. Provider time can include native/controller item work
and waiting; it is not a pure network-latency measurement. Provider and valuation
work overlap, so their timings cannot be added or subtracted to predict a cache's
wall-clock benefit. These replicate runs also differ from the earlier 16.170s
browse run (15.251s provider / 0.434s recorded local work).

The backup additionally contains a later, **incomplete browse scan**:

- Scan start: sequence 5,883, client time 65,899.161s.
- Vendor loading began: sequence 5,892, time 65,899.562s; `receiving=true`, 62
  currently queued item IDs.
- Last retained vendor progress: sequence 5,989, time 65,905.516s; 996/996 IDs
  ready at that point, zero failed, with 44 retained vendor events.
- The observed vendor-event span is **5.954s**, while incoming pages were still
  being received. No completion follows that scan start in the saved report.

That span includes time between incoming batches. It is neither exclusive
vendor-loading CPU nor a measured final loading stall. A complete live report
with the new dedicated vendor-stage measurements is needed before choosing a
persistent vendor cache or claiming a speed improvement.

## Reproduction

From the workspace root, set the exact file path and run the read-only tool:

```powershell
$env:PROFITMASTER_SAVED_PATH = 'C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\<account>\SavedVariables\ProfitMaster.lua'
Get-Item -LiteralPath $env:PROFITMASTER_SAVED_PATH | Format-List Length,LastWriteTime
Get-FileHash -LiteralPath $env:PROFITMASTER_SAVED_PATH -Algorithm SHA256
& 'C:\Users\runev\AppData\Local\Programs\Python\Python314\python.exe' tools/Run-LuaChecks.py 'C:\Program Files\obs-studio\bin\64bit\lua51.dll' tools/Measure-ProfitMasterSavedData.lua
Get-FileHash -LiteralPath $env:PROFITMASTER_SAVED_PATH -Algorithm SHA256
```

Repeat with the `.bak` path to inventory the earlier snapshot. The tool prints
completed scan windows; the incomplete backup-window timestamps above were also
checked directly in chronological ring-sequence order.

The direct sandboxed `loadfile` attempt encountered LuaJIT's 65,536-constant
compiler limit on these real files. The tool therefore uses a strict data-only
literal parser for this case, rejecting executable expressions/functions. Quoted
strings use an empty-environment Lua literal decoder. Parsing/execution is bounded
by a debug instruction hook, input by 64 MiB and nesting by 64 levels. The literal
source and decoder chunks are released before heap measurement. No third-party
parser, native addon extension, or access from saved code to filesystem/network
functions is introduced.
