# Profit Master

Current build: **0.2.1**. See the [performance review](profit-master-performance-20261115.md)
for the preparation handoff fix and large-book simulations. Use `/reload` first;
a full restart is a fallback if the
new controls fail to load. The scan/buy merge, checks and manual checklist are in
[the 2026-11-15 comparison](profit-master-comparison-20261115.md). Development and
the connected Git checkout now live at `C:\src\Profit-Master`; older entries below
record their original build dates and limitations.

Recovered chat: **Design Profit Master Addon**,
`6af5c489-1a64-83eb-a9cd-9cd7ffafa8d9`. Its final user instruction was
"Okay, let's build it."

Accepted requirements: WoW Forever, alongside Auctionator, a dedicated Auction
House tab (latest clarification), auctions below NPC vendor sell value, purchase cost/vendor
value/profit, highest profit first, and Buy buttons. The separate Check step is
removed. Latest clarification: a failed submitted buy removes its item from the
current list; other items remain. This supersedes keeping the failed item in 0.1.8.
Hide results below the configurable minimum profit (default 3 copper); offers
at exactly the selected threshold remain eligible.
After success, refresh only that item: keep it if the same variant remains at the
price just paid, otherwise remove it. Populate quantity as observed availability.
Publish candidates as valuation/vendor loading progresses. Prioritize user buys,
avoid a panel-wide stock-check lock, and offer quantity goals with one player click
per individual auction at the same price. True commodities now buy the selected
quantity as one authorized transaction. Internal auction buy errors remove that item.

Latest integration decision (2026-11-12): the user canceled the move to Auctioneer
after reporting its UI was buggy. Keep Profit Master on Auctionator. The partial
0.2.0 migration was never installed; its three staged file changes were reverted
to the installed 0.1.12 source. All five source/installed hashes match. The 3c
minimum, purchase rules and saved history remain as before. 453 integrated plus
56 history assertions and manifest validation passed again after the revert.

## External SQL history archive (2026-11-13)

User selected SQL for market history. A local SQLite companion archive now reads
the existing SavedVariables snapshot without executing Lua, changing the native
file or adding a game service/native extension. See
[SQL usage and data semantics](profit-master-sql.md) for import/query commands.
The SQL companion does not change the addon's live tables, scans, purchases or
30-day retention. Imports are manual after a completed client save.
SQL preserves older imported days indefinitely and computes equal-scan means
from cumulative daily mean sums/counts. Legacy quote observations remain separate.

## Bag advice retained outside the AH: 0.1.34 (2026-11-14)

User clarified that vendor/DE bag icons must remain available away from the AH.
The login handler now activates the existing bag module, and AH open/close no
longer controls its lifetime. This supersedes 0.1.33's AH-only bag advice. The
existing Disenchant profits toggle and Safe disenchant valuation still govern
icons everywhere. Standard bags and Baganator retain their event-driven updates,
filtered metadata readiness, reusable textures and unchanged normal item input.
No polling, timers, API changes or new settings are added for this correction.

Auction-only idle cleanup remains: scans/listeners/timers stop and transient
candidates/caches are released on close. Bag advice legitimately handles native
bag changes, public material-price updates and relevant metadata events outside
the AH; loaded code, saved history and the minimap/settings remain available.
Settings help and shipped README now reflect this exception explicitly.

Offline validation: production harness1124, bag markers1438, settings/minimap168
additional and auction-idle18 additional assertions passed. The idle test keeps
the bag event listener active on close while confirming auction subscriptions
detach, candidates are collectible, late callbacks cannot restart auction work,
and10000 warmed closed-AH auction cycles allocate0.000 KiB in the LuaJIT mock.
This is not a claim of zero live RAM or zero work for requested bag updates.
Manual check: /reload, enable Disenchant profits, open bags before visiting the
AH and after leaving it, move one supported item and confirm the appropriate
vendor/DE icon follows it. In-game behavior and rendering remain unverified.
Manifest/file validation passed; changed Lua was parsed/executed by the Lua5.1
mock suites (standalone luac is unavailable). Installed only ProfitMaster after
the helper preview, preserving `backups/ProfitMaster-20261114-215116-754.zip`.
All11 staged/installed file hashes match. No game input or reload was performed.

## Previous minimap settings and idle cleanup: 0.1.33 (2026-11-14)

User requested settings behind a minimap icon, explicitly including square-map
compatibility, then clarified that outside-AH overhead should be as small as
possible while the icon/settings remain available. Zero loaded RAM was clarified
as unnecessary. Saved history and existing bounded diagnostics are retained.

Settings.lua adds one gold-coin launcher and a lazy, reused 480x430 settings panel
for debug, DE, safe DE, minimum copper profit and the existing manual report.
The existing AH handlers are shared with that panel; controls synchronize via
the existing event-driven Refresh and retain scan/quote/purchase locks. Alternate
access is /pmaster settings; normal /pmaster still selects the AH tab. Frames are
unnamed/private, with native templates, readable descriptions and a Close button.

Native dragging uses saved, scale-correct x/y offsets relative to Minimap TOPLEFT.
It does not infer a circular radius or change the map's shape. Round and square
positions stay arbitrary, including square corners. There is no OnUpdate/input
hook or drag timer. Combat prevents starting a drag; nonpublic/unavailable map
coordinates do not overwrite the last valid position. Source/client baseline:
1.60.1.70938, interface16001, revision bebcb6bf309cf41b41bd74f8ca651e6a105b2676.
Primary docs/templates/callers are recorded in research/profit-master.txt.

Auctionator scan subscriptions now connect only at AH open and unregister on
close. Late callbacks return immediately while closed. Main work events subscribe
only while open; startup ADDON_LOADED/PLAYER_LOGIN subscriptions are released.
Closing cancels existing scanner/loader/purchase timers, releases candidate/price
caches and hidden-row deal references, and preserves saved history. Reopening
requires a fresh scan. BagMarkers initializes idle, enables advice/events only
while at the AH, and hides/unsubscribes on close. Existing nonremovable bag hooks,
Baganator callbacks and the public price callback become immediate no-op guards
while inactive; no item reads, valuation or refresh broadcasts occur there.
This intentionally supersedes earlier always-available bag-advice behavior.

Offline: production harness1124, settings/minimap168, idle118, bag markers1438,
minimum-profit UI169 additional, safe-DE UI129 additional, purchase-flow89
additional, purchase-latency70 additional, native browse96 and owned-auctions115
assertions passed. Idle checks release weakly referenced candidate objects,
preserve history, verify timer/event cleanup and reentry, and run10000 warmed
closed-house cycles with0.000 KiB Lua allocation growth in the host LuaJIT mock
with collection stopped. This is not a measurement of live client RAM/CPU.
Bag checks also run1000 inactive bag/hook/price cycles with zero extra reads,
valuation, cache invalidation or refresh broadcasts.

Visual QA is static: control/description areas have separate rows, status text
has a62px area above the bottom buttons, and native templates/fonts match the
existing UI. Real minimap addon compatibility, tooltip assets, scaling/contrast,
drag/input and rendered layout still require the user's manual /reload check.
Validate-Addon passed manifest/files for9 Lua entries; the Lua5.1 mock suites
parsed/executed the changed modules (standalone luac remains unavailable).
Installed only ProfitMaster after the WhatIf preview, with backup
`backups/ProfitMaster-20261114-210335-592.zip`. All11 staged/installed file hashes
match. No game input/reload or release packaging was performed.

## Previous safe disenchant build: 0.1.32 (2026-11-14)

User requested a mode which only offers DE profit when the cheapest possible
outcome covers purchase cost. Safe disenchant is a persisted checkbox on the
second control row, default ON for new and legacy version-1 DE settings. DE
profits itself remains opt-in; explicit safe=false retains average valuation.
Both scan/live purchase valuations and bag advice share the selected valuation.

Safe gross is the minimum of each supported material's price times its minimum
possible quantity. Net is floor(gross * 0.85); auction profit subtracts purchase
cost and still requires positive profit and the configured minimum. Bag advice
continues to compare the selected net with vendor, not historical purchase cost.
Minima were independently encoded from the installed Auctionator 346 Classic
probability table inspected read-only; see the dated disenchant research. No new
client API, event, dependency, timer, input hook or automatic game action is added.

Mode switching is allowed only while idle with no selected search, quote, pending
purchase or recheck. It resets valuation caches, removes stale DE valuations,
keeps legitimate vendor fallbacks and asks for a fresh scan. Active scan/purchase
callbacks cannot silently change the setting. Purchase-time repricing applies the
same minimum calculation. The header/dialog label minimum versus average and
disclose unverified Forever yields, saved prices and excluded relisting costs.
This is a model-based minimum, not a promise of actual drops, sale or profit.

Offline validation: 409 disenchant assertions; the production purchase harness
(1112 assertions) plus 128 safe UI assertions; minimum-profit UI (169 additional
assertions); bag markers (426 assertions). Tests cover cheap dust/essence/shard
outcomes, rare crystals, epic minimum quantities, fee/profit boundaries, stacks,
cache mode changes, legacy persistence, unknown data, stale UI callbacks, scan/
quote/purchase locks and Buy-time rejection after the cheapest price falls.
Purchase-flow (78 additional), purchase-latency (64 additional) and standalone
minimum-profit (108) checks also passed. Validate-Addon passed manifest/files;
luac is unavailable, while the Lua 5.1 harness parsed/executed the changed Lua.
Installed only ProfitMaster with the helper after its WhatIf preview. Backup:
`backups/ProfitMaster-20261114-205344-961.zip`. All 10 staged/installed file hashes
match; no game input or reload was performed. No release ZIP was requested.
Native layout, client load, actual drops and real purchases remain unverified.
Manual next step: /reload, enable Disenchant profits, keep Safe disenchant checked,
run a fresh scan, compare minimum outcome values, check checkbox/header/dialog
layout at the user's UI scale and confirm persistence after /reload.

## Previous purchase latency build: 0.1.31 (2026-11-13)

User reports roughly 3–5 seconds after clicking Buy; their clarification places
the wait before the confirmation opens. They do not recall whether the status
showed waiting for the channel or verifying price. No fresh 0.1.30 purchase
timing was persisted in the available current save/backup, so the split between
query-slot waiting, response time and local work remains unmeasured.
The older saved purchases completed 840ms/556ms after PlaceBid; multi-second
preview-to-click gaps in those records are not measured stock-recheck waits.

Two avoidable local conditions were found. TryRecheck gated cached result reads
on query readiness, and the final copy in a quantity goal always sent a stock
refresh even when another known auction ID at the exact link/price remained.
All confirmed individual purchases now take the existing deferred cached pass;
cached getters run without a query slot. A known matching unpurchased ID updates
stock/continues the goal locally. Grouped rows with no known replacement and
apparent exhaustion still take the normal refresh fallback before deciding stock
is gone. Other rows were already clickable during a recheck; avoiding a redundant
refresh prevents that request from consuming the next selected item's channel.

The native item's BuyoutDialogOnAccept and commodity Start/Confirm paths, plus
installed Auctionator 346 callers, submit verified user purchase requests without
testing IsThrottledMessageSystemReady. The earlier all-purpose Ready check was
too broad. PurchaseReady now checks session/AH visibility, combat and the external
provider; Ready adds native throttled-query readiness for search/refresh/paging.
Confirmation controls and hardware Accept use PurchaseReady. Exact listing/value,
funds, pending-result lock and commodity quote consistency remain unchanged.
Neither throttle events nor cached reads submit or retry purchases. This follows
the verified native caller pattern; it does not guarantee an unthrottled server
channel or eliminate acknowledgement/replacement-ID latency.

The first check for a new item still needs its server reply: generated replicate
data has no auction ID, and browse summaries contain no executable auction ID.
The redundant previous-item refresh can delay dispatch of that new query; it is
removed when another known ID already resolves the previous item's stock. No
speculative query prefetch, guessing auction IDs or buying scan estimates is used.

A single LastPriceCheck runtime summary now survives debug-ring wrapping. It
records queue_ms (start to query dispatch), reply_ms (dispatch to first matching
results), results_to_preview_ms (first results to the shown confirmation, which
can include pages/processing), and total_ms at the last recorded transition.
States are queued/sent/results/preview/ended. It works with logging off; final
preview/ended transitions are also logged when debug is enabled. First-response
timing is not pure network latency. Report only formats saved scalar values,
with no polling, queries or moving clock introduced. Subsequent copies retain
the initial check profile; the next item selection/reload replaces it.

Source changes are confined to ProfitMaster.lua, Diagnostics.lua, version and README.
Client remains 1.60.1.70938 / interface 16001, pinned primary source revision
bebcb6bf309cf41b41bd74f8ca651e6a105b2676. Primary caller evidence includes
[native buyout controls](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseSharedTemplates.lua),
the native frame's direct PlaceBid callback and installed Auctionator item and
commodity dialogs. No query limit/CVar or protected native state was altered.

Validation: 2,663 distinct offline Lua 5.1 assertions passed, including 64 latency
checks, 78 updated purchase-flow checks and the existing integration, profiling,
minimum-profit, market-history, owned-auction, disenchant, bag, browse and debug
checks. Shared main-suite runs are counted once. Manifest validation passed for
all eight Lua files; standalone luac is unavailable, while the compatible runner
parsed/executed the changed script. Actual native latency remains pending the
user's manual check; mocks establish eliminated requests/gates, not seconds saved.

Installed after clean helper preview and independent source review. Previous
0.1.30 was backed up to `backups/ProfitMaster-20261113-160617-481.zip`. All ten
installed files match staged SHA-256 hashes, with no extra installed files. No
game input/reload, other installed-addon edits, SQL archive change or native
SavedVariables modification was performed. User check: /reload, select an item,
and copy /pmaster log as soon as its confirmation opens; Latest price check
separates queued, first-reply and results-to-popup timing for the reported wait.

Observed follow-up: after the user reloaded again following purchases, the native
save written 2026-11-13 16:30:32 Berlin contains session 0.1.31 (#16540 onward).
The automatic provider is Auctionator's `full_incremental_scan_start`, not Profit
Master's pausable browse scanner. Guardian Gloves (5966) waits 7,180ms in queued
search while that provider repeatedly takes the native query slot. Dispatch
occurs on a native READY event after the provider's 0.99 progress; its subsequent
search receives no matching item-results event and times out after 15s (22,203ms
total). The log does not establish the cause of that missing result or prove a
ScanComplete-callback race.

Golden Scale Bracers (6040), selected after the provider finished, records queue
0ms, first reply 268ms, results-to-preview 6ms and total 274ms. Four individual
purchases succeed, taking 682/562/553/549ms from submission to completion. Their
next confirmation previews appear 82/53/54/56ms after success, using cached IDs
with no stock-refresh request. Thus the queued automatic browse scan is a
demonstrated source of the long pre-confirmation wait; local valuation/UI cost
was 6ms in the measured successful check. Two intervening Buy attempts report
missing item-key metadata without dispatching a query. No new implementation is
claimed for external-scan pause/priority or the unresolved missing response.

Read-only Auctionator configuration confirms `autoscan_2=true`,
`replicate_scan_3=false`, interval 15 minutes. Installed 346's Core/Mixin.lua
schedules the incremental autoscan two seconds after AH initialization. Its
incremental controller queues another browse page on each response, and its FIFO
AH queue exposes no supported external pause/priority operation. The safe manual
workaround is disable Auctionator automatic scanning and start scans from Profit
Master; PM already chooses its own pausable browse scanner when full replication
is unavailable. No other addon setting or installed file was changed in this
diagnostic turn. Auctionator's SearchScan source additionally warns that absent
item-key metadata can silently discard a query and rechecks it at dispatch; PM
currently checks before queuing. Cache loss during the long queue is a hypothesis
for the missing response, not established by the saved dispatch fields.

## Previous installed purchase correction build: 0.1.30 (2026-11-13)

User reports Auction House errors buying multiple items, recalling a throttling
message. Both supplied attachments are byte-identical 0.1.28 reports (SHA-256
AB947F86FD9287A4B2F2664D0A272819F6069334CF298D1E23A93CFAD5844233).
The 1,000-event ring begins mid-scan; earlier purchases have been overwritten.
Retained attempt 3 sends a search for item 6040, Golden Scale Bracers, at
t=68232.770 with itemLevel=37. Readiness arrives 542ms later, but there is no
result event, quote, purchase submission or native purchase error before a tab
change cancels it at 7.813s. This evidence does not establish the cause of the
reported native error.

Source review found a concrete API contract violation: SendSellSearchQuery must
receive an item key with level/suffix cleared. The replicate path used the
nonzero key returned by MakeItemKey. PreparePurchase now copies and normalizes
only that non-commodity sell-search key; selectedKey/event matching and later
stock requests use it consistently. Browse queries retain their original exact
key, commodity routing is unchanged, and the client/candidate key is not mutated.
All live price, link, vendor-value, funds and auction-ID checks remain.
This fixes a verified violation consistent with the stalled request; its native
frequency and relation to the unrecorded throttling error remain unverified.

Also corrected the two event-order races reproduced in the earlier improvement
review. Own item/commodity confirmation buttons follow native readiness via
THROTTLED_MESSAGE_SENT and THROTTLED_SYSTEM_READY. A busy quote remains open with
its quantity/goal; a stale early accept returns without purchasing and keeps the
dialog. Readiness never queues or sends a purchase. Cancellation, expiry, combat,
price/funds rechecks and one hardware click per individual auction still apply.
The reusable quote dialog pointer is cleared on hide and live-state cleanup.

RequestMoreResults handles both item/commodity rechecks and manual More listings.
Already-full results avoid an unnecessary request; a public hasFullResults=true
return or a completed coverage check rereads the same current result set. State,
key, candidate, commodity mode, verification and in-progress processing guards
prevent a synchronous event from reapplying the old request after replacement.
Stock pagination does not extend its deadline or submit any purchase.

Verified against executable 1.60.1.70938, interface 16001, primary Blizzard source
revision bebcb6bf309cf41b41bd74f8ca651e6a105b2676: generated AuctionHouseDocumentation
SendSellSearchQuery, RequestMore signatures and throttle events; loaded native
Shared item-buy/commodity-list callers and installed Auctionator 346 callers.
In-game verification remains pending the user's manual test and immediate report.
Validation: 2,602 distinct offline Lua 5.1 assertions passed, including 80 new
purchase-flow checks and all existing main, profiling, minimum-profit, market
history, owned-auction, disenchant, bag, browse and diagnostics checks. Repeated
main-suite assertions and the audit alias are counted once. Manifest validation
passed for all eight Lua files; standalone luac remains unavailable, while the
compatible runner parsed and executed the changed script. Independent source
review found no blocker. Native purchase/UI behavior is not established by mocks.

Installed after a clean helper preview; backup of 0.1.29 is
`backups/ProfitMaster-20261113-154710-418.zip`. All ten installed files match staged
SHA-256 hashes with no additional installed files. No game input/reload,
SavedVariables modification or other installed-addon changes were performed.

## Previous installed measurement build: 0.1.29 (2026-11-13)

User authorized measurement of Profit Master's memory and time spent loading
vendor prices before adding more caching. No vendor cache or SQL backend is added.
The read-only actual saved-data inventory/heap experiment is in
[the baseline report](profit-master-memory-baseline-20261113.md). Its current
snapshot is 7,205,771 bytes with 6,278 verified vendor values and 45,024 daily
history rows. Offline LuaJIT reconstruction retains 16.512 MiB, approximately
2.013 MiB for item/vendor records and 14.341 MiB for history; these are not WoW's
RAM counters. The latest retained replicate scan took 44.270s, provider 43.290s
and measured batches 2.259s. Vendor events were overwritten, so missing records cannot
establish zero loading time or a precise cache benefit. No trimmed averages were
present in this saved snapshot; legacy rows are not trimmed means.

Diagnostics.Show now manually calls the verified global UpdateAddOnMemoryUsage
and GetAddOnMemoryUsage for ProfitMaster/Auctionator, at most once per 15s. Native
AddonList's comment calls the updater expensive and forbids OnUpdate usage. The
copyable report includes current/previous timestamped samples, MiB from KB/1024,
signed deltas, capture age/cache delay and update cost. Report only formats stored
measurements. UI creation precedes capture so first-use frame allocation is not
charged only to the post-scan side. No explicit GC, background memory polling or
other process/native extension is used. Attribution/deltas are not process RAM,
native item-cache size, retained-cache-only growth or measured peaks.

Main scan instrumentation retains a single LastScanProfile independent of the
debug ring, including on cancellation/failure. Precise active clocks exclude Buy
pauses. Existing active-ID slots hold request timestamps before native dispatch,
supporting synchronous completions. First outstanding request opens a union
interval; last ready/failed completion closes it. Intersections after input close
identify the pending tail. Timeout/cancel snapshots include unresolved requested
IDs separately from queued-unsent IDs. Average/max readiness include only actual
usable vendor completions; record-loaded success alone remains pending.

Outermost loading-entry timing avoids counting synchronous nested callbacks
twice. Retry, initial valuation, DE and history slices are reported separately.
Pending/provider/CPU measurements overlap; they are not additive or pure network
latency. Post-input elapsed includes all remaining work. CPU means instrumented
elapsed slices and may include loading callbacks during a purchase pause.
Metadata dispatch, native query rates, shared timer, deadlines, pricing and
purchase authorization remain unchanged. Exact client remains 70938/interface 16001;
PerformanceDocumentation globals and loaded AddonList/PerformanceBar callers were
checked at source revision bebcb6bf309cf41b41bd74f8ca651e6a105b2676.

User capture procedure is in the shipped README: one initial /reload, report open
before scan, close, scan without purchases, reopen after completion with at least
15s between fresh captures, then copy before another reload. Actual WoW memory
and the new vendor-specific timings remain pending that native report.

Validation: 2,522 distinct offline Lua 5.1 assertions passed across the main,
profiling, minimum-profit, history, owned-auction, disenchant, bag, browse and
diagnostics suites. Repeated main-suite assertions in integration wrappers are
counted once. Manifest validation passed for all eight Lua files; the standalone
luac checker is unavailable, while the compatible runner parsed/executed the
touched scripts. Native measurements and in-game UI checks remain pending.

Installed after the clean helper preview. The helper backed up 0.1.28 to
`backups/ProfitMaster-20261113-154150-390.zip`; all ten installed files match
staged SHA-256 hashes, with no additional installed files. No game input or reload
was performed, and no SavedVariables or other installed addons were changed.

## Previous installed update: 0.1.28 (2026-11-13)

User requested a minimum scan-profit setting immediately right of Disenchant
profits, and authorized bringing the two existing checkboxes closer together.
The previous cutoff was 3c per item. The new Min profit field accepts whole copper
0..999999999, defaults to 3, and saves in the existing valid v1 ProfitMasterDB as
minimumProfit. No new SavedVariables or runtime Lua file is introduced. Unsupported
databases are preserved; invalid saved thresholds use the default until corrected.

Enter or focus loss commits, Escape restores, and invalid input restores the
previous value. Raising prunes visible candidates and the private scan best map;
Consider/Publish also enforce the current threshold, preventing later batches,
vendor readiness or DE repricing from resurrecting removed offers. Lowering shows
a fresh-scan notice because earlier rejected rows cannot all be reconstructed.
The field remains usable during scan work but is guarded throughout selected-key
verification, quotes, purchases, More listings and stock rechecks. It never starts
a new network query. Completed progress counts refresh after filtering; mixed
scan rejection statistics say below minimum when checked.

Deals.Calculate uses the selected minimum for vendor/DE, browse/replicate/live
and commodity paths; purchase-time revalidation inherits it. KeepVendorDeal uses
the same cutoff when DE is disabled. Zero still requires strictly positive profit,
including DE-to-vendor fallback. The independent 3c DE-versus-vendor strategy and
bag advice comparison are unchanged.

Client remains 1.60.1.70938, interface16001, pinned source bebcb6bf309cf41b41bd74f8ca651e6a105b2676.
InputBoxTemplate and its normal EditBox numeric/focus/enable methods/scripts were
checked against generated SimpleEditBox documentation and loaded SharedXML/AH
callers. Template focus-gained highlighting is retained, with explicit highlight
clearing on focus loss. Own controls only; no global keyboard/input changes.
Checkboxes now begin at x152/x258; the label/50px edit box sit at x400/x480 and
the copper unit at534. Progress width decreases from250 to220, leaving space on
the same top row. Actual font fit, UI scaling and gameplay interaction remain
manual QA.

Validation passes 1109 integration, 15 market-history integration, 108 minimum
settings/valuation, 167 minimum UI, 115 owned-footer, 112 history, 148 valuation,
426 bag, 96 pager and 13 diagnostics assertions (2309 distinct assertions; the
two wrapper suites each also run the shared main harness). Manifest checks pass
for all 8 Lua files; compatible mocked Lua 5.1 parses/executes the shipped source,
with luac unavailable. UI checks cover saved values, exact 9/10c boundary,
invalid/Escape/focus behavior, raising during input/CPU/vendor-readiness phases,
lowering and later publication, purchase/quote/recheck/More-listings locks,
commodity locks, DE-off fallback at10 and0, and preserving strictly positive
profit when the selected minimum is zero. No game input or reload was performed.

Installed after preview and validation. Previous 0.1.27 backup:
`backups/ProfitMaster-20261113-151752-573.zip`. All ten staged/installed hashes
match; actual SavedVariables and other installed addons were not changed.

## Previous installed fix: 0.1.27 (2026-11-13)

User confirmed this update works: Total and Incoming now display in-game after
the validation fix. This records the previously failing footer as working.

Before this fix, the footer was visible but both figures said Unavailable. Source
inspection found an unsupported validation requirement: every owned row needed
a positive unique auctionID before its status or money was read. The generated
structure only documents a number; native value display and Auctionator's owned
totals do not impose this cancellation-action requirement on financial rows.
An isolated regression changing only a valid Sold row ID from 4 to 0 reproduces
both Unavailable labels under the old code. Actual rejected live row fields have
not been captured, so zero/reused user IDs are a source-backed suspect, not an
observed fact.

The calculation now sums each canonical indexed cache row exactly once without
validating/deduplicating auction IDs. Financial checks remain public, finite,
integer and bounded. Priced active quantity zero contributes zero; excluded
bid-only rows need no quantity. Active and Sold validity are tracked separately,
so an invalid active price cannot hide an otherwise complete Incoming amount.
Total requires both components; unknown rows/status or Sold money still prevent
complete values. Incoming remains the native reported whole-sale amount, without
quantity multiplication or a second fee.

Debug-enabled visible refreshes log owned_totals with known total/incoming, row
count and the first failing field category/index. The diagnostic does not depend
on a changed label, allowing debug enabled after Unavailable to capture the next
ordinary refresh. No raw restricted values or cancellation identifiers are logged.
Existing UI text caching, native queries and event-only updates remain unchanged.

Validation passes 1106 integration, 15 market-history integration, 115 owned-footer,
112 history, 148 valuation, 426 bag, 96 pager and 13 diagnostics assertions (2031
total), plus the eight-file manifest check. The former zero-Sold-ID reproduction
now passes, as do shared/nonfinancial restricted-ID fixtures, quantity zero,
irrelevant bid-only quantity, independent Incoming validity and debug enabled
after an unchanged Unavailable display. Compatible mocked Lua 5.1 parses and
executes the shipped files; luac remains unavailable. No game input or reload was
performed. Client indexing was rechecked: native ItemList explicitly documents
getEntry indexes 1 through getNumEntries; the existing enumeration is correct.

Installed after preview and validation. Previous 0.1.26 backup:
`backups/ProfitMaster-20261113-150414-579.zip`. All ten staged/installed hashes
match; actual SavedVariables and other installed addons were not changed.

## Previous installed fix: 0.1.26 (2026-11-13)

The user reloaded 0.1.25 and supplied a screenshot with a blank footer, including
no Loading placeholder. Installed/staged hashes matched. Client General.log
records the concrete error `Baganator/API/Main.lua:22: bad argument #1 to
'ipairs' (table expected, got string)`, with ProfitMaster BagMarkers.Refresh,
BagMarkers.Initialize and the main PLAYER_LOGIN handler in the startup stack.
The same faulty call also appears in price-update stacks.

Baganator 851's public RequestItemButtonsRefresh(reason) iterates a list of refresh
reasons, or its default list when nil; Profit Master incorrectly passed an addon
name string. The smallest fix uses the public ItemWidgets reason list at both
refresh sites. The earlier mock accepted the wrong signature; it now reproduces
the real ipairs contract and rejects that argument. Only widget refreshes are
requested, avoiding an unnecessary bag-search refresh.

OwnedAuctions.Initialize now runs first on PLAYER_LOGIN, before the independent
scan and bag integrations. A new startup regression first reproduced failure
under the old order, then passed with the corrected order: an injected bag startup
failure leaves the owned listener registered and able to receive native events.
Repeated initialization still creates one listener. No footer positioning or
auction arithmetic change was justified; the disabled button's native OnDisable
only swaps textures and does not hide children.

The prior build added a Lua file to the manifest. Request one full client exit/
reopen to ensure its file list is refreshed; whether manifest caching contributed
to this screenshot is unverified. The confirmed Baganator error is fixed in source;
actual footer rendering still needs the user's next check.

Validation passes 1106 integration, 15 market-history integration, 89 owned-footer,
112 history, 148 valuation, 426 bag, 96 pager and 13 diagnostics assertions (2005
total), plus the eight-file manifest check. Compatible mocked Lua 5.1 parses and
executes the shipped files; luac remains unavailable. Each old Baganator string
call was independently restored in an isolated regression run and reproduced the
captured ipairs error; both corrected call sites pass with the actual reason-list
contract. The startup-order regression failed before the move and passes after it.
No game input or reload was performed.

Installed after preview and validation; previous 0.1.25 backup:
`backups/ProfitMaster-20261113-145320-242.zip`. All ten staged/installed hashes
match. Only Profit Master's installed files were changed; actual saved data,
Baganator and other installed addons were left alone.

## Previous installed build: 0.1.25 (2026-11-13)

User requested a potential return total in the native Auctions footer beside
Cancel Auction, then selected estimated payout after fees and a 5% faction-house
cut. The final requirement is two figures: Total = active estimates + Incoming;
Incoming = native amounts from Sold rows awaiting payment. `OwnedAuctions.lua`
creates one mouse-transparent child of
`AuctionHouseFrame.AuctionsFrame.CancelAuctionButton`, right-aligned in the
430px area to its left. Cancel's normal visibility also hides it on Bids and
other native/LibAHTab screens. No native click handler or attributes are changed.

The estimate reads the complete native owned-auction store, independent of the
selected item filter. Active buyout per unit x quantity, less 5% per listing
rounded down to copper, is added to reported Incoming to produce Total. Known
expired active rows are excluded. Unpriced active bid-only listings are explicitly
excluded in a compact caption; their final price is unknown. Sold amounts are
already the native whole-sale Incoming Amount, so neither quantity nor a second
fee is applied. Sold quantity/time may be zero or missing and do not exclude them.
Missing/secret/malformed/duplicate rows produce Unavailable; incomplete owned
results remain Loading. Each AH session waits for its first OWNED_AUCTIONS_UPDATED
before showing a number. Subsequent updates and showing the footer refresh it;
unchanged text is reused. There is no query, timer, polling or saved-data change.

Exact build remains 1.60.1.70938 / source `bebcb6bf309cf41b41bd74f8ca651e6a105b2676`.
Owned APIs/structures/events and active/sold enums were checked against generated
AuctionHouseDocumentation and native AuctionsFrame/TableBuilder callers. The
installed Auctionator346 owned-cancelling provider independently confirms unit
price x quantity. The native button is 158x22, BOTTOMRIGHT(-3,-22); the label uses
RIGHT-to-LEFT(-12,0) and leaves the existing gold display clear in source layout.
Rendered scale/clipping and disabled-button appearance remain manual QA.

Blizzard AuctionHouse DB2 at this build gives ConsignmentRate=5 for faction
houses, 15 for Blackwater; DepositRate is a separate field. No verified runtime
cut/current-house getter was found, so the display explicitly says 5% cut rather
than infer it from player faction or reuse the disenchant 15% reserve. Deposit
refunds and acquisition costs are unavailable. Active estimates do not add refunds;
Incoming matches native reported amounts without guessing their deposit content.
This is estimated proceeds rather than exact mail payout or net profit. Fee data
was cached outside the addon from
[AuctionHouse DB2](https://wago.tools/db2/AuctionHouse/csv?build=1.60.1.70938).

Validation passes 1103 integration, 15 market-history integration, 89 owned-footer,
112 history, 148 valuation, 424 bag, 96 pager and 13 diagnostics assertions (2000
total). The new footer tests cover quantity/fees, whole-sale Incoming, no second
cut, Total including Incoming, bid-only and bid fallback, sold removal, malformed/
restricted/overflow data, native event ordering, reopening and hidden-tab work.
The visibility mock distinguishes local IsShown from inherited IsVisible, matching
the native API; hidden or restricted visibility performs no owned-row reads.
Manifest checks pass (8 Lua files). luac is unavailable; compatible mocked Lua
5.1 runs parse/execute the shipped files. No game input or reload was performed;
actual layout and auction/payment updates remain manual QA.

Installed after preview and validation. Previous 0.1.24 backup:
`backups/ProfitMaster-20261113-144422-728.zip`. All ten staged/installed file hashes
match. Other installed addons and actual SavedVariables were not changed.

## Previous installed build: 0.1.24 (2026-11-13)

Vendor buying defaults to the maximum verified stock affordable at the exact
quote price. Item quantity edits immediately update the remaining goal, total
cost/value/profit and `Buy 1 of N` caption. Individual auctions still submit one
known auction ID per confirmation; grouped stock does not supply the next IDs.
Commodities show `Buy N` and request the selected quantity as one transaction.
Invalid input clears stale totals and disables confirmation. DE item goals keep
their conservative half-stock default; completed-copy goals keep counting down.

The user selected unit-weighted history and full-snapshot preference. Profit
Master now prefers Auctionator's full replicate scan when available, falling back
to its own paced browse during the shared 15-minute cooldown. It does not change
Auctionator's settings. External Auctionator scans still use their own mode.

Complete raw replicate price distributions yield a per-item-ID mean after exactly
10% of units are trimmed from each tail. Stacks are normalized to unit price and
count by units; fractional boundary weights retain exact 10% trimming. Bid-only
rows are excluded. These are asking prices, not completed sales. The series keeps
its broader `replicate:<ID>` scope, distinct from exact browse variants.

Auctionator may compact away rows with unavailable descriptions. Statistics read
all zero-based native financial tuples locally, in slices of at most 1000 rows
and an approximate 4ms clock budget, without another query or metadata wait.
Finalization shares the existing timer and pauses for Buy. It persists only after
all valid data is processed; changed snapshot/count, invalid/restricted financial
fields, replacement scans and AH close discard pending means. Scan statistics
also finalize in small steps; a native per-item price sort cannot be preempted.
Fast browse only exposes minima, so it explicitly reports that trimmed means
require a full snapshot. Existing low/high/latest observations remain intact.

To avoid millions of saved per-snapshot tables, daily `trimmedMeans` records keep
each item's sum/count of completed scan means plus its latest mean/unit counts.
Each scan retains equal weight for the future average of averages. The existing
30-day pruning also removes these rollups; no old history is backfilled.

Client executable metadata now reports 1.60.1.70938. The matching Forever source
revision is `bebcb6bf309cf41b41bd74f8ca651e6a105b2676`. Affected Auction House
generated API documentation and native callers, GameDialog, SharedTemplates and
SharedDialogDefs match the previous 70888 baseline. StaticPopup differs only by
a trailing blank line. The exact interfaces used by this update are unchanged.

Offline validation passes 1100 integration, 15 market-history integration, 112
history, 148 valuation, 424 bag, 96 pager and 13 diagnostics assertions (1908
total). Manifest checks pass; luac is unavailable, with the shipped Lua files
parsed/executed using the existing compatible mocked Lua 5.1 runtime.
Market-history integration covers omitted metadata, zero-based raw reads, no
extra queries/bids, bounded work, Buy pause/resume, replacement/cancellation,
native count/generation changes and invalid/restricted financial fields.
Statistics use `history_rows`, `history_means` and `history_ms` in debug summaries;
history CPU slice time is included in `batch_ms`, with purchase pauses excluded.
No game input or reload was performed. Actual layout, server behavior and mail/
gold changes remain for the user's manual test in the shipped README.

Installed after preview and validation. The previous 0.1.23 build was backed up
to `backups/ProfitMaster-20261113-143027-784.zip`; all nine installed file hashes
match staged source. Other installed addons and actual SavedVariables were not
changed.

## Previous installed build: 0.1.23 (2026-11-13)

User reported needing to disable debug before disabling DE, then clarified an
automatic scan was probably active. The settings and handlers are separate; the
confirmed source discrepancy was the DE checkbox's scan-busy lock while debug
remained clickable. Exact pinned UICheckButtonTemplate has no inherited expanded
hit rectangle or click script, and the 24px checkbox regions do not overlap. No
layout change or actual shared-preference dependency was established.

DE can now be switched off while an automatic or manual scan is in progress,
without touching debug. Enabling it again still waits for idle; an active selected
price-check/quote/purchase/stock flow retains its authorization lock until finished
or canceled. The checkbox enabled state and click-handler guard use the same rule.

Turning DE off clears private scan best-result entries as well as visible rows,
so subsequent publications cannot resurrect DE offers. Known DE rows also
profitable at NPC value are converted to vendor values and re-sorted; DE-only
rows are removed. Further scan valuation proceeds vendor-only and the existing
fresh-scan notice remains. Bag advice is refreshed/hidden by the same opt-out.
No network query, scan restart, preference migration or input behavior is added.

The integrated regression checks both debug preferences, their saved tables,
automatic scan events, DE-off while receiving rows, converted/dropped offers,
later publication/completion, rejecting busy DE-on and preserving an active quote.
Actual checkbox interaction on the user's client remains a manual check.

1076 integration, 148 valuation, 424 bag, 96 pager, 56 history and 13 diagnostics
assertions pass offline (1813 total). Manifest validation passes; luac unavailable,
with all shipped Lua parsed/executed under the compatible mocked runtime.
Installed after preview; previous 0.1.22 backup:
`backups/ProfitMaster-20261113-141647-437.zip`. All nine installed/source hashes
match. Only the main controller, TOC and shipped README changed; other addon files,
actual saved data and game input/reload were not changed.

Manual next check after the user's /reload: keep Enable debug checked, allow the
automatic scan to start, then uncheck Disenchant profits. Debug should remain on,
DE bag icons/DE-only rows should disappear and discovery should continue. Enabling
DE can be done once idle. Finish/cancel an active purchase flow before changing it.

## Previous installed test build: 0.1.22 (2026-11-13)

User requested a small vendor-sale bag icon when selling to an NPC is preferable
to disenchanting, then explicitly clarified icon only, without a label. Native
and Baganator bag slots now use one small top-right region: the client's actual
Disenchant spell texture for DE advice or the native bags-junkcoin atlas for vendor
advice. Neither bag icon has SELL/DE text; AH row DE text is unchanged.

Disenchant.Recommendation returns disenchant/vendor/no advice only when the
supported expected-value comparison is complete. The existing 15% sale-fee
allowance applies to expected DE materials. DE wins by >=3c, vendor wins by >=3c;
close ties, missing/restricted metadata/material prices and unsupported yields
remain unmarked. Non-disenchantable consumables/junk do not automatically become
SELL recommendations. ShouldMark remains a compatibility predicate for DE only.

The same Disenchant profits checkbox controls both types of bag advice for all
eligible inventory, including unpurchased gear. This compares DE against NPC value,
not intact-item resale or the item's usefulness to the player. No junk flags,
inventory clicks, auto-selling, disenchanting, game queries or new timers are added.

Existing event-driven bag/metadata/Auctionator-price updates and combat recovery
are retained. The existing Baganator widget ID/position survives. Atlas/texture
styles update only when changed; switching back to spell art resets texture
coordinates. The same path also repairs the reviewed initially unavailable icon
case: an existing region can acquire its texture on a later refresh.

Primary icon evidence: pinned Forever Mainline/ContainerFrame.xml uses
bags-junkcoin for its JunkIcon region, with Camelot loading that base UI. The
Disenchant icon continues to come from C_Spell.GetSpellTexture(13262). This is
decoration only and does not change native junk classification.

1031 integration, 148 valuation/recommendation, 424 bag, 96 pager, 56 history and
13 diagnostics assertions pass offline (1768 total). Checks include both signed
3c boundaries, ties, zero values, unknown/secret data, per-item stack behavior,
icon-only regions, DE/vendor/unknown transitions, texture coordinates, deferred
icon readiness, native/Baganator lifecycle and unchanged input. Manifest validation
passes seven Lua files; luac unavailable, with all Lua parsed/executed under the
existing compatible mocked runtime. Native rendering remains unverified.

Installed after -WhatIf preview. Previous 0.1.21 backup:
`backups/ProfitMaster-20261113-134254-103.zip`. All nine installed/source hashes
match. ProfitMaster.lua, BrowseScanner.lua, Deals.lua, History.lua and Diagnostics.lua
are unchanged. No other installed addon files, actual saved-data files, game input
or reload were changed.

Manual check after the user's next /reload: enable Disenchant profits; compare
known supported vendor-winning and DE-winning items in native/Baganator bags.
Check there is only an icon, it switches after price/item changes, unknown data
stays blank, and disabling hides both. Normal clicks/dragging and combat exit must
still work. Actual appearance remains game QA.

## Previous installed test build: 0.1.21 (2026-11-13)

Fresh 0.1.20 saved diagnostics establish the current bottleneck. Two complete
browse scans: 14,195 rows / 77 candidates took 16.130s (provider 15.258s, measured
slices 424ms); 14,142 rows / 64 candidates took 16.170s (provider 15.251s, slices
434ms). First candidates appeared at 240/243ms and vendor loading began at
382/320ms. Both had zero unavailable rows. The old ProviderBusy gate nevertheless
kept Buy disabled until provider release. These are actual client report timings;
slice sums are not an exhaustive CPU profile and differ from full elapsed time.

User requires Buy while discovery is running, the actual Disenchant icon, and
continuously updated recommendations for all bag items, including unpurchased
gear. Auctionator346 resets its browse buffers on item-search browse updates and
has no public pause API, so dropping the busy guard alone is unsafe. Pinned native
Blizzard browse UI keeps browse and specific-item result stores concurrently and
resumes pages from the same query. This supports an owned paced browse producer
for Profit Master's button, while retaining Auctionator as a required pricing and
external-scan dependency. Native runtime coexistence still requires game QA.

BrowseScanner.lua owns native browse query/page scheduling, streamed row delivery,
logical-key deduplication and one bounded request watchdog, with no polling or
Auctionator field mutations. Buy pauses future pages; in-flight rows are captured.
Native readiness gives the selected read-only verification priority. The original
manual confirmation/hardware-click rules still apply. Resume occurs after flow
cleanup. Leaving the tab stops owned browsing and labels captured results partial;
AH close cancels the pager and pending read checks. External Auctionator browse
rows are clickable but their checks wait for safe provider release; independent
replicate processing permits item checks. Existing server throttles are respected.

A queued read check is bounded to 30 seconds and its normal 15-second verification
deadline starts on send. Stale same-key events cannot open a quote while queued.
Missing/unaffordable terminal results release paused work; manual More listings
is retained for a bounded 15 seconds, then releases it. Actual pending purchases
survive discovery failure, and neither query scheduling nor scan callbacks buy.

Final DE reconciliation now keeps only the cheapest offer per valuation reference
(base item ID for browse, exact item link for replicate), instead of revaluing every
duplicate source row. The 10,000-offer regression preserves the best price with
10,001 total item-key reads (10,000 initial + one final) rather than a second full
pass. History/source-row counts are unchanged and fresh live stock still wins.

Disenchant.Icon() reads C_Spell.GetSpellTexture(13262), verified in pinned
SpellDocumentation and the native SpellFlyout caller. Both AH and bag markers use
that actual spell texture; unavailable/restricted icon data does not substitute an
Enchant icon. The icon is cached once available.

BagMarkers registers once with Auctionator.API.v1.RegisterForDBUpdate; genuine DB
updates invalidate material prices and refresh enabled recommendations without a
Profit Master scan. Native bag updates and combat recovery remain event-driven.
Only visible native slots waiting on metadata are tracked, and only matching public
successful item events recheck them. 1,000 unrelated load events do zero bag work.
Baganator uses its public nil=pending widget readiness path. No new bag polling,
per-frame handlers, game input, disenchanting or external addon file edits.

1031 integrated, 116 DE, 346 bag, 96 native-pager, 56 history and 13 diagnostics
assertions pass offline (1658 total). Manifest validation passes with seven Lua
files; luac is unavailable, with every shipped Lua file parsed/executed under the
compatible mock runtime. Tests cover buying before full discovery, native throttle
priority, stale event suppression, resume/partial cleanup, external isolation,
replicate coexistence, icon identity and independent bag/price updates. Native
server coexistence, actual icon rendering and bag widgets still need game QA.

Installed after preview and validation. Previous 0.1.20 backup:
`backups/ProfitMaster-20261113-132135-864.zip`. All nine installed/source hashes
match. Deals.lua, History.lua and Diagnostics.lua are unchanged. No other installed
addon files, actual SavedVariables or game input/reload were changed.

Manual next checks: user /reload and use Profit Master's Scan button. Select an
early Buy, verify the quote before discovery completes, confirm or cancel, and
observe resumed discovery. Check unavailable/partial search cleanup, tab leave
and AH close. Enable DE once, inspect the actual spell icon and markers on old or
newly acquired eligible bag gear, including after independent Auctionator price
updates and combat exit. Unsupported yields and unknown prices remain unmarked.

## Previous installed test build: 0.1.20 (2026-11-13)

User asked to continue performance work. The latest on-disk report shows 0.1.19
loaded but contains no new scan after 0.1.17, so no real before/after scan speed
claim is possible. This pass reduces measured local work and adds timing fields;
Auctionator scan mode, server queries, cooldown and purchase rules are unchanged.

Scan-only publication now coalesces for up to 250ms instead of 50ms. The first
candidate, final completion and purchase/user controls remain immediate. An
unchanged final payload does not rebuild/sort again. Owned controls cache their
displayed text, amounts, colors and enabled states; unchanged rows avoid native
text/layout work and money formatting. Twenty unchanged refreshes perform zero
text setters and zero money formatting in the instrumented integration test.

Disenchant metadata rejects obvious unsupported slots/classes/quality/expansion
before detailed-level lookups. Known metadata with missing material prices caches
an unavailable result only within its price generation. Missing/restricted item
metadata remains retryable. Exact metadata survives generation changes and cache
eviction as before; final material repricing and fresh live checks are unchanged.

Bag refreshes no longer discard scan material-price caches. Disabled markers skip
bag traversal/valuation after one cleanup. Native bag events still update native
slots but do not broadcast another Baganator refresh; explicit option/value changes
and combat recovery still do. For 20 instrumented native events, enabled duplicate
Baganator broadcasts fell 20 to 0, and disabled bag reads 40 to 0 / valuations
60 to 0. Existing behavior and input checks remain covered.

GetTimePreciseSec now measures processing slices and their approximate 4ms budgets
(valuation, load dispatch, item/commodity stock reads). Same-build Blizzard_Console
uses this clock for a 1.5ms budget at pinned source commit
4cd0ab752a77164f654ccbca9d0c1fe8dafceebe. No shared profiler timer is reset. Test
coverage holds frame GetTime unchanged while the precise clock advances and
verifies valuation still yields. Publication pacing still uses GetTime; a single
native operation or full sort can exceed a slice and is not preemptible.

Existing debug events now include processing stage/batch_ms. Completion records
scan_ms (elapsed scan, including waits/pauses), provider_ms (until Auctionator's
completion callback, including its local work), and batch_ms (summed slice time,
including publication within slices). Loading callbacks and all UI work are not
fully included, so these are diagnostic client timings rather than a CPU profile.

Offline benchmarks outside the addon compare identical output/order. Actual sort
code with virtual one-candidate/ms arrival, five JIT-disabled trials: 6000 rows,
120 to 25 publications, 175ms to 37ms median sorting work; 12000 rows, 239 to 49,
785ms to 169ms. Longest large publication remains roughly 7-8ms; fewer sorts do not
bound one sort. A separate 200000-row/1000-link seven-trial valuation benchmark
preserved all candidate/profit results across DE off/known/unknown/eviction+refresh.
Detailed-level calls fell 1000 to 750; unknown-material median Lua time fell
0.121s to 0.088s. Other profiles were approximately unchanged. These do not measure
native API cost, game FPS, server latency or actual C_Timer delivery.

990 integrated, 112 DE, 304 bag, 56 history and 13 diagnostics assertions pass
(1475 total). Manifest validation passes; luac unavailable, with all Lua parsed
and executed under the compatible mocked runtime. Changes are confined to
ProfitMaster.lua, Disenchant.lua, BagMarkers.lua, metadata/docs and development
checks/benchmarks. No in-game performance claim is made.

Installed after -WhatIf preview. Previous 0.1.19 backup:
`backups/ProfitMaster-20261113-111924-865.zip`. All eight installed/source hashes
match; Deals.lua, History.lua and Diagnostics.lua are unchanged. No other installed
addon files, actual SavedVariables or game input/reload were changed.

Manual next step: user /reload, enable debug, run a fresh scan (with DE enabled if
used), check early/final rows and normal buys, and copy the report. Bag indicators
should still update after moves, disabling/re-enabling and combat exit. Compare
scan_ms/provider_ms/batch_ms plus actual responsiveness before tuning further.

## Previous installed test build: 0.1.19 (2026-11-13)

User requested a checkbox next to debugging to include disenchant opportunities
in scans, distinguish them in AH results, and put a disenchant marker at the top
right of bag slots. Clarification: mark ALL bag items whose estimated disenchant
proceeds exceed vendor value, not only Profit Master purchases. Existing scan and
purchase behavior from 0.1.18 remains the baseline.

Disenchant.lua supplies opt-in settings and expected-material valuation. Its own
small factual baseline table covers supported original items; no library, new
dependency or code from another addon was added. Auctionator's loaded Forever
DE API uses mainline expansion tables and does not value this gear, so only its
public material-price API is used. Exact-client DB2 establishes eligibility, not
server loot probabilities. Primary research and exclusions are in
`research/disenchant-yield-research-20261113.md`. All yields are explicitly baseline
estimates, and known unknown/changed cases are skipped rather than guessed.

Expected gross materials are reduced by a conservative 15% sale-fee allowance;
deposits/relisting losses and profession/perk bonuses are excluded. Every material
outcome must be priced. DE is selected only when its expected net beats vendor by
3c, and net minus acquisition cost must still be >=3c. Vendor value is retained
separately; grouped availability never multiplies a single auction's return.
Bag icons instead compare estimated net against vendor value. They do not assess
the usefulness/intact resale price of gear or the player's ability to disenchant.

The checkbox is disabled during active scan/purchase flows and defaults off in
new ProfitMasterDisenchantDB settings. DE rows show icon + DE text and estimated
proceeds. Their Buy confirmation explicitly says DISENCHANT and explains random
outputs, saved material prices and fees. Buy revalues the exact link with refreshed
material prices and rejects strategy/net drift. There is no automatic disenchant,
vendoring, mail collection, posting or additional purchase authorization.

The existing bounded valuation loop performs a final DE reconciliation against
material prices learned at provider completion, without repeating history/vendor
statistics. Per-reference public metadata survives native cache eviction. The
final pass preserves fresher live-stock values, exclusions and purchase pauses.

BagMarkers.lua observes standard Blizzard combined/individual bag updates using
mouse-transparent texture/font regions and a verified native post-hook. Installed
Baganator 851 is enabled; its documented public RegisterCornerWidget API supplies
an optional top_right default icon and RequestItemButtonsRefresh updates. Initial
widget insertion is handled normally by Baganator and later user customizations
are respected. No direct Baganator settings/code writes. No polling/timer/input
overrides; updates defer during combat. Other replacement bag UIs are unsupported.

984 integrated, 101 valuation, 122 bag-widget, 56 history and 13 diagnostics
assertions pass offline (1,276 total). Manifest validation passes with six listed
Lua files. luac is unavailable; all shipped Lua parses/executes in compatible
mocked Lua 5.1. Checks include fresh-scan material prices, metadata eviction,
uncached/restricted values, all-outcome pricing, exact Buy-time revaluation, live
stock precedence, mode persistence/defaults, disabled state and bag API lifecycle.
These are not in-game validation of rates, FPS, secure behavior or rendering.

Installed after -WhatIf preview. Previous 0.1.18 backup:
`backups/ProfitMaster-20261113-105422-560.zip`. All eight installed/source hashes
match. History.lua and Diagnostics.lua are unchanged. No other installed addon
files, actual SavedVariables or game input were changed; no reload was sent.

Manual next step after installation: user /reload, enable Disenchant profits while
idle, run a fresh scan and inspect DE rows/confirmation. Open bags and check the
top-right Baganator/default icon on supported profitable gear, normal clicks and
dragging, disabling/re-enabling and combat exit. New/custom/unknown yields stay
unmarked. Capture a debug report and actual screenshots for game QA if needed.

## Previous installed test build: 0.1.18 (2026-11-13)

The user's pasted 0.1.17 diagnostic report contains a new browse scan of 15,367
rows: 16.356 seconds through Auctionator's completion event, 19.654 seconds total,
42 candidates and zero unavailable rows. The remaining 3.298 seconds include
5,762 vendor loads and valuation. There is no new replicate scan or Auctionator
debug-chat capture in that report; it does not establish bulk-scan performance.
Four latest buys received matching completion events; two received error 10
(DatabaseError). Later gold samples decreased by the exact two prices, but neither
money changes nor the error prove the transaction outcome.

Browse vendor loading now starts between incoming valuation batches, using one
queue across all pages. It keeps the existing 32 outstanding/request-per-dispatch
limits, yields after roughly 4ms, retains loaded prices through native-cache
eviction and shares the existing timer with valuation and purchases. There is no
idle polling while waiting for incoming data. Final loading gets 60 seconds after
incoming valuation drains, excluding purchase pauses. Exact-link replicate loading
still begins after input closes; scan-mode selection and Auctionator are unchanged.

Individual-auction DatabaseError responses and localized internal-error messages
remove/exclude the offer and stop its quantity goal, while retaining the matching
confirmation listener until the original 15-second purchase deadline. New buys
stay locked during that bounded wait. Matching completion reports confirmed after
error; timeout reports an uncertain outcome and asks the user to check mail/gold.
Duplicate errors do not extend the window, gold is never confirmation, and neither
resolution restores the offer or sends another purchase. Commodity flow is unchanged.

937 integrated, 13 diagnostics and 56 history assertions pass offline (1,006 total),
including early loading, cache eviction, one request per ID, limits, no idle timer,
provider failure, long provider wait, purchase pauses/final payload reconciliation,
localized/synchronous errors, matching/unrelated/late confirmations, duplicate
errors, original deadline, quantity-goal termination and no retries. Manifest
validation passed; luac is unavailable, but all Lua parses and executes under the
existing Lua 5.1-compatible mocked runtime. Actual FPS, latency and game permissions
are not established by these checks.

Installed after -WhatIf preview; previous 0.1.17 backup:
`backups/ProfitMaster-20261113-104315-653.zip`. All six installed/source hashes
match. History.lua, Deals.lua and Diagnostics.lua are unchanged. Other addons,
actual SavedVariables and game input were not changed; WoW was not reloaded.

Manual next check after installation and the user's /reload: keep debug enabled,
run a browse scan and check that vendor_load_start has receiving=true and loaded
candidates arrive before scan completion. Try a normal buy; if an internal error
occurs, check the uncertain/late-confirmed status, no automatic repeat, and mailbox
before retrying an unresolved buy. Copy the new report for real timing comparison.

## Previous installed test build: 0.1.17 (2026-11-12)

User reports that quantity buying partly works but nonpurchasable offers remain
at the top, and explicitly asks for an Enable debug option with extensive logging.
There was no transaction log: only the latest status text and price history.
Source inspection confirmed deliberate keep-item branches after rejected commodity
quotes and changed individual listings. The user's exact live failure event is
still unknown until a diagnostic report is captured.

Changed/unavailable/expired server quotes, vendor failures at the commodity Buy
step, complete empty/unverified commodity searches, complete empty item searches
and changed/disappeared individual listings now remove the selected candidate.
Rows compact and page bounds update through the existing failure-removal path;
current-scan exclusions prevent remaining valuation from restoring it. A fresh
scan can rediscover it. User cancellation and temporary gold/busy/combat conditions
keep the result. The exact price/quantity safety checks are unchanged.

Diagnostics.lua provides an event-driven, optional ring log. Enable debug is an
unchecked-by-default control in the header; Debug log opens a copyable snapshot
or /pmaster log works outside the AH. /pmaster debug on/off also sets the preference.
ProfitMasterDebugDB separately persists the choice and newest 1000 bounded events
on native save/reload. Logging covers searches, prices/quantities, server quotes,
stock results, error events, approximate client timing, gold/throttle/combat context,
scan/loader/batch summaries and removed/kept reasons. Restricted values are redacted.
No clipboard call, chat spam, upload, per-frame handler or background service exists.
The copy panel is created once and refreshes only on request; Ctrl+C is manual.

853 integrated, 13 diagnostics and 56 history assertions pass offline (922 total).
They cover retention/persistence, redaction, disabled logging, ring overflow,
copy-panel focus, checkbox/command synchronization and stale-row removal. Manifest
validation passed; luac is unavailable but all four Lua files parse and execute
under the compatible mocked runtime. Actual control rendering and the user's
original failure remain game QA.

Installed after -WhatIf preview. Previous 0.1.16 backup:
`backups/ProfitMaster-20261112-184656-353.zip`. All six installed/source hashes
match. History.lua and Deals.lua are unchanged; no other addon, actual saved-data
file or game input/reload was changed by the assistant.

Manual next step: /reload, check Enable debug, reproduce the failed Buy, then open
Debug log and press Ctrl+C. Paste that report back here. The stale row should
disappear immediately on a rejected quote and the list move up. Turning debug off
keeps captured entries; /reload preserves both the choice and the bounded log.

## Previous installed test build: 0.1.16 (2026-11-12)

User explicitly requested commodity support to buy the selected quantity at one
price with one click. Browse commodity candidates are now included and labeled
Buy qty; replicate candidates are classified again by the live key metadata.
The commodity search selects the cheapest eligible price, aggregates only its
stock, subtracts ordinary owned quantities and skips account-containing rows.
The 3c minimum remains per item. Vendor data comes from the client, never history.

A native confirmation has Quantity to buy, defaulting to half known same-price
stock with the existing rounding/gold cap. Edits update quantity totals. One Buy
quantity click invokes StartCommoditiesPurchase once. Its server quote must match
both the exact unit price and selected quantity times that price, with a valid
quote lifetime, current gold and freshly verified vendor profit. Only then does
the public ConfirmCommoditiesPurchase complete that same request from the quote
event. There is no retry, extra quantity or bid loop. This uses the pinned API's
restricted Start/public Confirm distinction; no protected-action bypass is used.
In-game permission and behavior remain unverified by the assistant.

Changed/unavailable quotes keep the candidate and cancel the request. Failed,
blocked or unconfirmed purchases remove only the attempted item. A pending quote
is canceled on tab leave or AH close; committed requests retain their completion
handling. Success refreshes that commodity under the existing deadline/throttle
rules and keeps only known eligible stock at the purchased price. Checks are
bounded to 200 rows/~4ms, use one shared timer, and coexist with paused streaming
valuation and the unchanged 30-day history. Individual-auction buying is unchanged.

823 integrated plus 56 history assertions pass offline. New cases verify one-click
quantity/total arithmetic, ownership, unit minimum, asynchronous/synchronous
quote completion, duplicate events, stale dialogs, price changes, secrets, expiry,
gold/vendor changes, combat, failure/blocked/internal errors, bounded reads,
pagination, post-success metadata gaps, stock retention/removal and cancellation.
Manifest validation passed (luac unavailable; all Lua parsed/executed under the
mocked compatible runtime). Installed after -WhatIf preview, with all five installed
hashes matching staged files. Previous 0.1.15 backup:
`backups/ProfitMaster-20261112-182404-301.zip`. History.lua, SavedVariables and other
addons were not modified. No game input/reload was sent. Layout, actual quantity
delivery, gold totals, secure execution and game latency need the user's game test.

Manual next step: /reload and scan. On a cheap commodity use Buy qty, set 2, check
the total and press Buy quantity once. Verify gold/mail and same-price row refresh.
Confirm individual auctions still use Buy 1. A changed quote must cancel; it must
not switch price tiers or start a second transaction.

## Previous installed test build: 0.1.15 (2026-11-12)

The user requested one-click selected-quantity purchasing and overlapping scan,
price comparison and list population. Source inspection found no quantity-buy
call for the individual-auction rows used here: PlaceBid takes one auction ID and
amount. A grouped row can expose only one actionable ID. Quantity-based purchase
calls belong to the separate commodity path, which this addon does not implement.
No multi-ID purchase loop, automatic action or protected-action bypass was added;
the full selected quantity with one click remains unimplemented/unverified.

Valuation now begins during Auctionator's scan progress events. Browse rawScan
buffers supply new rows after the first fresh buffer replaces the old one.
Replicate scanData is sparse: the progress/index relation from installed 346
limits reads to already-visited positions, then the final payload reconciles late
rows. Provider-final payloads reuse those row objects, allowing identity-based
de-duplication of queued valuation/history. No other addon is modified and no
second AH scan is sent. Missing vendor metadata uses the existing loader after input ends.

The existing 1000-row/4ms batches consume incoming rows and coalesce display
updates. An empty queue sleeps until another progress/completion event; one bounded
render timer flushes a dirty list while waiting. Provider progress remains visible
during receipt. A purchase pauses valuation; final rows can arrive safely during
the pause and resume afterward. Buy stays gated by the provider's active busy
state, then becomes available during its local database-finishing phase. This is
cooperative overlap, not multicore execution or a server-throttle bypass.

692 integrated plus 56 history offline assertions pass. Coverage includes early
browse/replicate rows, canceled stale buffers, sparse delayed metadata, duplicate
progress/final payloads, bounded processing, no idle polling, render flushes,
provider busy states, completion during an early quote, failure and AH-close cleanup.
Actual time to first row/Buy, secure purchases and popup layout remain user checks.

Installed after validation and -WhatIf preview; all five installed/source hashes
match. Previous 0.1.14 backup: `backups/ProfitMaster-20261112-173227-146.zip`.
History.lua and Deals.lua are unchanged. No other addon, saved-data file or game
input was changed, and WoW was not reloaded by the assistant.

Manual next step: /reload and scan. Watch for candidates while Auctionator is
still processing; Buy should become enabled when its active scan releases the AH.
Test a cheap quote during database finishing, then cancel or purchase and verify
that final rows and the remaining quantity goal persist. Report first-row and
first-buyable delays separately from server/purchase waits.

## Previous installed test build: 0.1.14 (2026-11-12)

The user wants the quantity goal to start at half available stock so they can
click Buy immediately. The first confirmation now defaults to half the observed
stock at the exact live link/price, rounded down with a minimum of one and capped
by affordable gold. Later confirmations preserve the remaining goal rather than
halving it again. The value stays editable; each Buy 1 click submits one auction.

An active goal first checks native results for another unpurchased same-price ID
after success. A known matching ID can open the next quote without a server
refresh. Each click still reads the current exact auction and vendor price before
PlaceBid. If no known ID remains, the check falls back to one refresh before
deciding stock is exhausted; a grouped quantity never fabricates another ID. A
finished goal still refreshes stock for the list. Native readiness, bounded work,
the 3c minimum, failure removal and history are preserved. Server races remain
possible and actual in-game latency has not been measured.

670 integrated plus 56 history assertions pass under the existing Lua 5.1-compatible
runtime. New coverage includes even/odd/single stock, gold caps, exact price/link
counts, remaining-goal preservation, cached-ID revalidation and synchronous
completion, no extra refresh between known IDs, native readiness, grouped-ID
refresh fallback and the final stock refresh. Manifest validation passed; luac is
unavailable, but all three Lua files execute under the mocked runtime.

Installed after validation and -WhatIf preview. Previous 0.1.13 backup:
`backups/ProfitMaster-20261112-172338-811.zip`. All five installed files match
staged hashes. History.lua and Deals.lua remain unchanged; no other addon or
SavedVariables file was modified, and no game input/reload was sent.

Manual next step: /reload, scan, and check the default on an inexpensive deal
(5 same-price copies -> goal 2, gold permitting). Click Buy 1 for each wanted copy.
Check the goal counts down and stops, then the row updates or disappears according
to remaining same-price stock. Compare the delay between copies; no in-game speed
or secure-action result has been verified by the assistant.

## Previous installed test build: 0.1.13 (2026-11-12)

The latest screenshot shows a confirmed purchase and the whole panel disabled
during stock refresh. It establishes a visible global wait state, not a measured
FPS stall. The old recheck also valued/sorted every returned auction on each
response. It now checks only matching link/price rows, yields after at most 200
rows or about 4ms, and stops paging once eligible stock is known. Partial counts
show >=. Only the checked row waits; other rows and paging remain usable.

Buy confirmations now have a Quantity goal and Buy 1. Each click revalidates and
submits one auction ID; grouped availability never becomes a buy quantity. Matching
success refreshes stock and opens a next-copy quote only while the goal remains.
The next copy requires another player click. Cancellation, error, lost same-price
stock or insufficient gold ends the goal. PlaceBid runs only from the player's
confirmation click, never from search, success-event or timer callbacks.

Local valuation publishes candidates before Finish and as vendor data arrives,
coalescing redraws. Row processing yields after about 4ms or 1000 rows. Buy pauses
valuation and takes the existing shared timer; cleanup resumes the saved stage.
Metadata arriving while paused is still captured, with at most the original 32
in-flight requests. Resuming neither repeats processed history observations nor
restores removed items/overwrites fresher live values. Auctionator's network phase
still precedes this valuation; no client busy state or server cooldown is bypassed.

Pending buys now listen for UI_ERROR_MESSAGE and match the client's localized
ERR_AUCTION_DATABASE_ERROR. That internal error removes the attempted item, ends
its goal and releases the listener. The existing AUCTION_HOUSE_SHOW_ERROR path
continues removing failed submitted buys. Unrelated errors and errors after
confirmed success do not remove other results or trigger a retry.

613 integrated plus 56 history assertions pass under Lua 5.1. Tests cover early
publishing, purchase priority/resumption, metadata eviction while paused, history
de-duplication, removed-item suppression, time budgets, batched rechecks, partial
counts, multi-copy goals, cancellation, price changes, funds and localized internal
errors. Purchase pauses preserve the remaining vendor-loading budget. Actual
latency, native edit-box layout and in-game repeat buys remain user
checks. History.lua and Deals.lua are unchanged from installed 0.1.12.

Installed after validation and -WhatIf preview. Previous 0.1.12 backup:
`backups/ProfitMaster-20261112-171246-762.zip`. All five installed files match staged
hashes. Auctionator remains required; no other addon, game input or saved-data file
was changed by the installation tools.

Manual next step: /reload and scan; buy an early candidate while valuation continues.
On a cheap item set goal 2 and click Buy 1 for each fresh copy. Check that other
rows remain usable during stock refresh, and verify gold/mail quantities. Confirm
an internal auction error removes only that item and stops the goal.

## Previous installed test build: 0.1.12

Matching purchase completion now saves the purchased link/price and starts a
deferred, read-only RefreshItemSearchResults for its selected key. It waits for
the documented throttle-ready event and reads matching item-search updates.
Partial results request more pages using one shared 15-second total deadline.
Bought IDs are excluded, and duplicate IDs do not inflate availability.

Full results with eligible same-link/same-price stock retain the row, update its
availability and per-item values and re-sort profit. Full results with no match
remove only that candidate and clamp pages. Different prices/variants do not keep
the old offer. The 3c minimum and ownership exclusions still apply. Missing vendor
data, errors, unavailable throttle and timeout keep the row with unable-to-verify
feedback. Rechecking never opens a Buy popup or submits a purchase. Tab changes
preserve it; AH close cancels its deferred work, deadline and readiness listener.

Quantity was deliberately rendered as a dash for browse estimates. The column is
now Avail.: initial browse values are total observed copies across prices, while
replicate values retain the observed source count. Both scan modes display unit
prices/vendor/profit, using buyout/count for replicate estimates. After a successful
stock recheck, Avail. becomes the eligible count at the purchased price. Quantity
is separate from the one item purchased by each confirmed Buy.

453 integrated plus 56 history assertions pass under Lua 5.1. New cases cover
deferred and synchronous purchase completion, same-price stock, exhausted and
changed prices/variants, pagination, throttle readiness, duplicate IDs, minimum
profit, tab switches, errors/missing data, deadline recovery, AH close, populated
availability and consistent unit prices. All game interaction remains untested
by the assistant; the user handles /reload and manual purchase checks.

Installed after manifest validation and -WhatIf preview; all five installed file
hashes match staged source. Backup of 0.1.11:
`backups/ProfitMaster-20261112-163315-031.zip`. Other installed addons were untouched.

Manual next step: /reload and rescan. Check populated Avail. and unit vendor prices.
Buy one cheap eligible item with multiple copies at one price; the row should stay
and its count update. Buy the last eligible copy at that price; only that row should
disappear. Verify no second confirmation/purchase occurs without another click.

## Previous installed test build: 0.1.11

The shared Deals.lua calculator filters profit below 3 copper for browse estimates,
replicate results, live quotes and Buy revalidation. Exactly 3 copper is included.
The heading states min 3c, and coverage counts hidden positive profits separately
as profit under 3c; these remain priced rows rather than unavailable vendor data.
Observed history continues to collect quotes regardless of the display filter.

351 integrated and 56 history assertions pass under Lua 5.1, including 1c/2c/3c
boundaries for scan results and live auctions, grouped availability and coverage.
Manual next step: /reload and rescan; confirm 1c/2c rows are absent and 3c can appear.

Installed after manifest validation and -WhatIf preview; all five installed files
match staged hashes. Previous 0.1.10 backup:
`backups/ProfitMaster-20261112-162448-560.zip`. No other installed addon was changed.

## Previous installed test build: 0.1.10

User explicitly requested removing an item when its attempted buy fails. The
existing failure cleanup now removes selectedCandidate by table identity before
clearing purchase state. It updates the visible count, compacts rows and clamps
pagination, while preserving all other candidates and the vendor/history database.

Removal applies after submission: AH rejection, client blocked/forbidden action,
or the bounded 15-second unconfirmed-purchase timeout (including interrupted
handlers). Timeout still reports uncertainty and asks the user to check mail/gold.
No retry is sent. Canceled/expired confirmation, search errors/timeouts and local
validation that prevents submission keep the item. Successful buys retain their
item groups. A fresh scan can rediscover an item; there is no saved blacklist.

344 integrated plus 56 history assertions passed under Lua 5.1. Coverage includes
each failed-submission path, only the selected row disappearing, unrelated/late
errors, cancellation/preflight preservation, fresh-scan rediscovery, last-page
clamping and removing the final candidate. No new API or timer was introduced.
Next manual step: /reload; cancel a quote and confirm it remains, then verify that
an actual failed submitted buy removes that item and leaves other results usable.

Installed after validation and -WhatIf preview. Backup of 0.1.9:
`backups/ProfitMaster-20261112-162234-809.zip`. All five installed files match the
staged source hashes. Other installed addons and game input remain untouched.

## Previous installed test build: 0.1.9

User's 0.1.8 screenshot now shows Scan complete, 8 candidates, 12871 priced and
5365 verified vendor prices / 5404 stored item IDs. This is observed evidence of
much broader vendor coverage after the retention fix. It does not verify a buy.

The same screenshot exposes a separate unit bug: Small Blue Pouch x139, a 3s
buyout, 3g47s50c vendor value and 3g44s50c profit. One pouch's vendor value is
2s50c. Non-commodity ItemSearchResultInfo.quantity groups available copies; the
PlaceBid call buys one auction ID / one item. LiveDeal incorrectly multiplied
that single item's vendor value by grouped quantity. Prior mocks also made this
incorrect stack assumption, so their arithmetic checks did not detect the bug.

0.1.9 values each returned auction ID using one item's exact-link sell price and
that auction's buyout. Group availability must be positive but never multiplies
vendor value or purchase quantity. The confirmation shows x1 and the auction ID.
The pouch at 3s is rejected; a pouch at 2s40c shows 2s50c vendor and 10c profit.
Existing browse/replicate snapshots remain estimates; neither authorizes a buy.

301 integrated and 56 history assertions passed under Lua 5.1. The screenshot
regression and mixed live-results test reject false grouped profits and choose a
genuinely profitable individual auction. Changed price/link/vendor, unavailable
results, blocked action, cancellation and retained-list checks continue passing.
Purchase permission and real gold/mail/vendor revenue remain unverified in-game.

The before/after reproduction produces the screenshot's false 34450-copper profit
with saved 0.1.8 Deals.lua and rejects it with 0.1.9. Source copy and comparison
script are under scratch/, outside the shipped addon. Installed after validation
and -WhatIf preview; backup `backups/ProfitMaster-20261112-161229-425.zip` contains
0.1.8. All five installed files match staged hashes; other addons are untouched.

Next: /reload, scan and try Small Blue Pouch again. If the cheapest current pouch
is 3s, there must be no Buy confirmation. A genuine profitable quote must show
one auction ID, x1, and one item's vendor value. Confirm an inexpensive auction
and compare actual gold, mail quantity and vendor revenue. Keep the results list.

## Previous installed test build: 0.1.8

User reported "interface action failed because of an add-on" on Buy, followed by
the list disappearing. Code confirmed that the old Buy handler cleared its live
rows and refreshed the UI before PlaceBid. The disappearing list is explained;
the exact client-blocked function/cause was not captured in the original report.

0.1.8 keeps candidate results throughout query, confirmation, purchase and failure.
Each candidate now has Buy. It searches live stacks, chooses the highest-profit
affordable returned stack and opens a stock StaticPopup confirmation showing its
exact link, quantity, cost, vendor total and profit. Only that confirmation's Buy
click revalidates and calls PlaceBid. It calls before hiding/updating the controls,
matching the installed Auctionator purchase ordering. There is no asynchronous
purchase, automatic retry or protected-action workaround.

Cancel, expiry, server errors, interrupted calls and purchase timeouts preserve
the candidate list and recover controls. Confirmed auction IDs are remembered
privately for this session so stale cache copies cannot be offered again. Item
groups remain available to fetch further stacks. Blocked/forbidden events now
report their addon/function in the existing status line and cancel the request.
The normal client warning is not suppressed. No taint logging setting was changed.

293 integrated assertions and 56 history assertions pass under Lua 5.1, including
the actual installed LibAHTab with mocked frames. Checks cover hardware-click
submission ordering, changed/stale quotes, cancellation, both blocked events,
an interrupted purchase call, synchronous completion and preservation of rows.
Manifest validation passes; luac is absent, but all three shipped Lua files parse
and execute through the focused mocks. These checks cannot establish permission
for a protected action in-game or prove the original blocked-action cause fixed.

Installed after validation and -WhatIf preview. The helper backed up 0.1.7 to
`backups/ProfitMaster-20261112-160622-666.zip`; all five installed file hashes match
staged source. No other installed addon or game state was changed.

Next manual check: /reload, scan, click Buy and cancel once; results must stay.
Then confirm one inexpensive stack, check gold/mail and retained results. If
blocked again, report the addon/function now shown in Profit Master's status.
Also report priced/unavailable versus vendor-ready/database counts: 0.1.7 vendor
coverage remains unconfirmed in-game. Historical underpricing work stays deferred.

## Earlier test builds

### 0.1.7

Current vendor investigation: latest user screenshot shows 12938 scanned, only
4 priced, 12916 unavailable, 18 unsupported; 5341 record loads OK and 5341 vendor
values ready, zero failures, but only 4 saved vendor values. The user also noted
the below-vendor warning when posting an auction.

The installed Auctionator implements that matching warning in GetConfirmationMessage
at Source_ModernAH/Tabs/Selling/Mixins/SaleItem.lua:635. It directly reads Blizzard's
sell-price field for the sale link, then compares against seller proceeds after
the AH cut. This is not the same as a profitable buyer buyout below vendor value.

Found another concrete code loss: VendorReady discarded the actual fields after
verifying them, then Retry cleared its cache and read everything again. Blizzard's
matching Item.lua explicitly marks item data evictable. 0.1.7 captures public name,
price/link fields immediately, preserves them for the scan retry, and persists the
verified vendor observation while available. Exact replicate-link variants retain
separate references and must each have actual values. Buy still does a fresh lookup.

A new regression makes native data unavailable after every loaded item callback.
Installed 0.1.6 fails at the 12948-item valuation; patched 0.1.7 succeeds. 245 addon
assertions and 56 history assertions passed. Actual live cache behavior and the
in-game fix remain unverified. No new features were added.

The helper installed 0.1.7 with matching file hashes and backup
`backups/ProfitMaster-20261112-155305-921.zip`. Next: user's /reload and scan; compare
priced/unavailable with vendor ready and stored vendor-price count. Keep vendor
pricing as the only priority until live coverage is confirmed.

Current priority: reliable vendor prices before further feature work. The latest
user screenshot of 0.1.5 shows 12894 scanned, 3 priced, 12872 unavailable, 19 unsupported,
5332 native item-record successes and zero failures. Database vendor coverage is
only 3 of 5354 item IDs. This remains a live failure; successful record notifications
were being mistaken for vendor-metadata readiness.

0.1.6 addresses two concrete code paths: browse valuation uses the numeric ID's
returned name/vendor value directly, without discarding that price and requiring
a display link plus second lookup. Browse prices remain base-item estimates.
The load queue now checks for actual readable vendor fields before a successful
completion and also listens for GET_ITEM_INFO_RECEIVED. Basic-record OK counts
and vendor-data-ready counts are shown separately. The original 32-item bounds,
60-second total deadline and cleanup on close remain. Exact live Buy uses only the
exact auction link and fresh price; missing live values have an explicit message.

242 integrated and 56 history assertions passed. New regressions cover valid
numeric vendor prices with an unavailable display link/link lookup, early basic
load events and later metadata events, and never borrowing a base estimate for
an exact-link Buy. This is not an in-game verification of the remaining failure.
The installer backed up 0.1.5 to `backups/ProfitMaster-20261112-154736-737.zip` and
installed 0.1.6; hashes match staged source. History.lua/schema are unchanged.

Next manual step: /reload, scan once, report priced/unavailable plus Item records
OK and vendor data ready/failed. Do not proceed with historical underpricing work
until vendor coverage is confirmed. The user is responsible for all game input.

Latest request: persist item/vendor data and the last 30 days of auction-price
history. Historical underpricing detection is explicitly deferred. 0.1.5 adds
History.lua and the account-wide ProfitMasterDB SavedVariables entry, initializes
on this addon's ADDON_LOADED event and reuses Auctionator's connected-realm/ruleset
market key. It records only observed data; history begins after this update.

Items retain the latest verified name, exact vendor-observation link, per-item
vendorPrice and vendorSeenAt. This value is not assumed valid for every variant
of the same item ID. No saved price is used in candidate valuation or Buy checks.
Unknown vendor data is kept absent; a verified zero is stored as zero.

Market history stores UTC-day records keyed by actual browse item ID/level/suffix/
pet species, or by a separate broader replicate item ID series. Records contain
low/high/latest observed unit price, sample count and latest observation timestamp.
Samples are quotes, not sales, and sources are not silently merged. Repeated item
loads do not repeat quote recording. Partial processed scans contain only quotes
actually observed; the database does not assert market-wide coverage.

Today plus 29 preceding UTC dates are retained, with whole expired buckets pruned
on login/new scan after a date change. Item/vendor records remain persistent.
There is no extra scan, polling timer, dependency, external service or backfill.
A Database status line shows item/vendor/observed-day counts in the existing tab.

The screenshot supplied during this task still shows incomplete 0.1.4 coverage:
12956 scanned, only 5 priced, 12934 unavailable, 17 unsupported. That live issue is
not claimed solved. Native item-load OK/failed counts are now reported to help
distinguish API failures from data that remains unavailable after a reported load.
Auction quotes can be saved independently of missing vendor data.

Validation: 230 integrated assertions plus 56 history assertions passed using Lua
5.1. Checks cover SavedVariables initialization, persistence round-trip, market and
variant isolation, per-unit arithmetic, missing versus zero values, chronological
updates, retry de-duplication, 30-day pruning across markets, and preserving unknown
schema versions. No historical detection/purchase behavior was introduced.

The helper installed 0.1.5 after preview/validation and backed up 0.1.4 to
`backups/ProfitMaster-20261112-153740-531.zip`. Installed file hashes match source.
Manual next step: /reload, scan once, note the Database and item-load counters,
then /reload again and confirm the database counts persist. Actual SavedVariables
disk writes, the added status-line layout, and live data coverage remain unverified.

Run the history checks with the same Python/Lua runner:
`tools/Run-LuaChecks.py <lua51.dll> tools/Test-ProfitMasterHistory.lua`.

Latest user observation: a scan returned zero candidates with 12948 unavailable
listings skipped. This is incomplete valuation, not evidence of no profitable
auctions. 0.1.3 gated vendor valuation on optional AH key metadata and never loaded
or retried missing item data; both paths were counted as unavailable.

0.1.4 removes the optional metadata prerequisite and requests missing item data
through the verified C_Item request/event pair. The queue requests each ID once,
with 32 maximum in flight and per synchronous dispatch, a shared 60-second deadline,
and one retry pass over affected rows. A separate progress phase shows loading.
Closing AH cancels the listener/queue/timer. Timeout/failure produces Incomplete
data with coverage counts, instead of a conclusive zero-candidate completion.
Commodity/pet exclusions are counted separately; commodity buying is still absent.

220 offline assertions passed, including a 12948-item cold-cache reproduction,
successful retry, missing optional metadata, non-item appearance links, duplicate
and synchronous load requests, failure/timeout and close cleanup. The helper
installed 0.1.4 after preview and validation, backing up the previous build to
`backups/ProfitMaster-20261112-152805-083.zip`. All installed file hashes match source.
The actual game rows and availability of real bargains remain unverified.

Source is `addons/ProfitMaster`. Only Profit Master's installed folder was updated;
0.1.3 addresses the user's reports of slow results/listing and a replicate cooldown
despite Auctionator's Scan button working. The exact source cause was forcing
replicate instead of following Auctionator's configured scan mode. The new path
selects its browse controller when configured, or when replicate is cooling down.
It listens to both completed scan payloads, including scans the user starts in
Auctionator, and does not change Auctionator's config or bypass server cooldowns.

Browse candidates show estimated profit per item and no stack quantity. Minimum
summary price does not imply that every available item is available at that price.
They retain exact level/suffix keys for a narrower live query. Live Buy rows always
show exact stack quantities/costs/vendor values and revalidate on the user click.
Reopened candidates report scan age. Per-pass exact-link price caching reduces
duplicate lookups; Buy uses fresh values. Batches now cap at 1000 rather than 250,
with zero-delay yields, and Buy locates the auction before calculating its value.

The 0.1.3 update passed 199 assertions, including browse-mode selection, replicate
cooldown fallback, scan reuse, exact-key live events, quantity/price units, and fresh
Buy validation. The existing helper installed it after preview/validation and
backed up 0.1.2 to `backups/ProfitMaster-20261112-152008-955.zip`. All four installed
files match staged hashes. No in-game end-to-end speed improvement is verified.

Installation history: other addons were not edited. Version 0.1.0 was installed at the user's request,
then replaced with 0.1.1 following their request for a native Auction House tab.
The helper backed up 0.1.0 to
`backups/ProfitMaster-20261112-150923-901.zip` before copying the update.
All four installed files were verified by hash against staged source.

Update 0.1.2 adds an event-driven progress bar using Auctionator's ScanProgress
fractions. It shows server waiting and database finishing, then a separate count
of Profit Master's vendor-price checks. Completion appears only when candidates
are ready. Failures, cooldown and stopping on AH close have explicit feedback.
The scanning control stays disabled until vendor checking finishes. The TOC still
declares `## Dependencies: Auctionator`; this is a required dependency.

The candidate heading now explains Check -> live listings -> Buy. An empty live
list explicitly reports that no profitable stacks were found. The user reported
seeing Check buttons and insufficient scan feedback; no completed purchase or
in-game progress-bar result has been supplied.

0.1.2 was installed with the same helper; the previous build was backed up to
`backups/ProfitMaster-20261112-151328-775.zip`. Installed hashes match staged files.

The Profit Master content frame is now inside AuctionHouseFrame. Its tab uses
the LibAHTab library already provided by Auctionator. Normal and addon tabs share
selection/visibility handling; the former floating window and launcher are removed.
Slash commands select the tab while the AH is open. No new library is bundled.

Requires Auctionator; shares its browse/replicate scan controllers and completed
payloads. Groups snapshot candidates by item ID using the highest displayed profit.
Check loads live auction stacks; each variant uses its exact link for vendor value.
Each player Buy click revalidates one live auction and submits one exact-price
buyout. No purchase from scan data, automatic retry, or unattended purchase.

Only one bounded timer is used for batched processing, live search timeout, or
purchase timeout. No idle polling, OnUpdate, SavedVariables, or new libraries.
Testing tools remain outside the shipped addon.

Known limits: commodity purchases, configurable budgets/thresholds, and session
profit tracking are not implemented. The latter features were suggested in the
old assistant's draft, rather than separately specified by the user. Partial sale
scans do not supply complete candidates. Internal scan integration
is verified in installed 346 source, not a stable public API guarantee.

## Validation and next step

Manifest validation passed. Both shipped Lua files parsed and executed under the
locally installed OBS Lua 5.1 DLL, without launching OBS or WoW. Offline mocked
checks cover stack and variant arithmetic, ownership, ordering, stale listings,
funds, throttling, purchase locking, unrelated completion events, timeout/error
handling, batching, pagination requests, and AH close cleanup. The tab update
passed 151 offline assertions, including running the actual installed LibAHTab
source against mocked Blizzard frames for native/other-addon tab switching,
single registration, and purchase locking while switching away and back.
The progress update passes 173 assertions, including required dependency metadata,
immediate feedback, upstream progress/regression handling, honest finishing state,
vendor-count progress, error/close cleanup, and preventing duplicate scan clicks.

The repeat-listing benchmark (tools/Benchmark-ProfitMaster.lua) verified identical
profit results with vendor lookups reduced from 200000 to 100 for 100 distinct
links. Mock timings (0.002s old / 0.004s new) do not demonstrate faster game or
network behavior. See research/profit-master.txt for the measured scope/limits.

Run from the workspace root using an existing Python and Lua 5.1 runtime:

```powershell
$env:PROFITMASTER_AHTAB_SOURCE = '<Auctionator folder>\Libs_ModernAH\LibAHTab\LibAHTab.lua'
& '<python.exe>' tools/Run-LuaChecks.py '<lua51.dll>' tools/Test-ProfitMaster.lua
.\tools\Validate-Addon.ps1 -Name ProfitMaster
.\tools\Package-Addon.ps1 -Name ProfitMaster
```

No game was controlled. This build is installed but not verified in-game. The ZIP
previously created for 0.1.0 predates the tab update. The next step is the user's
manual checklist in the shipped README.txt: restart the client for first discovery
(or /reload if already discovered), open the Auction House, select Profit Master,
check tab switching and scan results, then verify one inexpensive stack purchase.
For 0.1.4, use /reload, start Scan while replicate is on cooldown, and confirm the
browse scan runs with progress. Also scan from Auctionator and check that results
appear in Profit Master without another scan. Verify / item versus / stack headers
and one inexpensive Buy. Compare waits by phase (server, finishing Auctionator,
vendor checks, live query); do not attribute a server delay to local processing.
On cold data, confirm Loading item data followed by rechecking and priced coverage.
If zero candidates remain, report the coverage counts (especially priced versus
unavailable and unsupported) to distinguish non-deals from excluded/missing data.
Layout at different UI scales, clipping/contrast, and real purchase behavior remain
unobserved until the user tests in-game.

Primary API and integration evidence: `research/profit-master.txt`.
