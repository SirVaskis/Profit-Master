# Profit Master

An Auction House addon for **WoW Forever**, using **Auctionator** as its required
dependency. Current source version: **0.2.0** (Interface 16001).

Profit Master finds auctions below vendor value, estimates disenchant proceeds,
and verifies live listings before a player confirms a purchase. It includes
quantity goals, bag advice, minimap settings, diagnostics and market-history
collection. Safe disenchant mode uses the supported minimum material outcome.

Version 0.2.0 adds a Quick scan of up to 300 learned item keys and prepares up to
20 affordable item listings while the tab is idle. A prepared **Buy 1** row buys
one verified auction on that click; an unprepared row loads a confirmation.
Settings can restore confirmation for prepared rows. Commodity quantities keep
their existing server-quote confirmation. See [the comparison and checks](docs/profit-master-comparison-20261115.md).

## Install

Install Auctionator, then copy `addons/ProfitMaster` into your client's
`Interface/AddOns` directory. Use `/reload` to load the update, including the new
0.2.0 manifest files. Check that the Quick scan button appears. A full restart
is a fallback if the addon or new controls fail to load, not a requirement
established for this Forever build.

Open the **Profit Master** Auction House tab, or use `/pmaster`. The minimap
button and `/pmaster settings` open settings. `/pmaster log` opens the manual,
copyable diagnostic report.
Use **Quick scan** or `/pmaster quick` after a full scan has learned opportunities.

See [the addon README](addons/ProfitMaster/README.txt) for usage and limitations.

## Source layout

- `addons/ProfitMaster/`: the installable Lua addon and manifest.
- `tools/`: offline Lua/Python checks, install/package helpers and SQLite import.
- `docs/`: implementation notes, measurements and SQL usage.
- `research/`: client API and disenchant-source verification notes.

The SQL database, native SavedVariables, logs, local backups and generated
packages are excluded from this repository. The SQLite importer reads a saved
snapshot after a player reload/logout; synchronization is manual and the addon
does not query SQL during gameplay.

## Validate

```powershell
.\tools\Validate-Addon.ps1 -Name ProfitMaster
py -3 -m unittest discover -s tools -p 'test_profit_master_*.py' -v
```

The validator checks the manifest/files and XML; Lua syntax checking requires a
compatible `luac`. The offline Lua suites can also run using an existing Lua 5.1
DLL and the included runner:

```powershell
$env:PROFITMASTER_AHTAB_SOURCE = 'C:\path\to\Auctionator\Libs_ModernAH\LibAHTab\LibAHTab.lua'
py -3 tools/Run-LuaChecks.py 'C:\path\to\lua51.dll' tools/Test-ProfitMaster.lua
```

Run the remaining `tools/Test-ProfitMaster*.lua` suites the same way. The initial
source push passed **4,288 distinct Lua assertions** and **31 Python tests**;
the 0.2.0 comparison document records the new validation results.
Repeated main-harness checks in wrappers are counted once. Offline checks do not
establish in-game API permissions, rendering or latency. Historical benchmarks
require their specified baseline directories and are not standalone test suites.

`project.json` supplies the default game path for optional install/import helpers;
adjust it for your installation. Installation backs up the existing named addon.
The helpers never control or reload WoW.

## Market history

See [SQL history usage](docs/profit-master-sql.md) for archive/import commands and
queries. Historical quote observations are asking prices, not completed sales.
The average-of-averages view uses equal weight per completed trimmed scan.

Known issue: the latest inspected full scan was rejected as an incomplete price
distribution, so saved trimmed averages remain empty. Existing quote/vendor data
is preserved. Auctionator's automatic browse scan can also delay live purchase
checks by occupying the shared search channel.
