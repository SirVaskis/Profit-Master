# Profit Master / ProfitTop comparison — 2026-11-15

Profit Master 0.2.0 implements the useful scan and buying ideas from the supplied
ProfitTop 0.1.13 source by James Boyd. The supplied source, ZIP and patch notes
remain local under ignored `compare/`; they are not included in this repository.
The new modules are implementations for Profit Master's existing purchase and
history paths. No extra library, dependency or background service was added.

## Findings and implemented choices

| Area | Supplied ProfitTop behavior | Profit Master 0.2.0 |
| --- | --- | --- |
| Fast scan | `Quick.lua` refreshes a learned watchlist with `SearchForItemKeys` | Separate Quick scan, up to 300 keys, batches of 50. Full scans still discover new items. |
| Buying preparation | `Preload.lua` loads top item books before clicking | Prepare up to 20 affordable item opportunities, one request at a time, while the tab is idle. |
| Prepared purchase | `Buy.lua` permits a spending click on a prepared row | Explicit **Buy 1** row action; optional confirmation in settings. Each individual auction still needs a hardware click. |
| Cached book eviction | Supplied preload code can use a retained quote when native results disappear | Require the exact ID in the current native book. Missing/changed data falls back to a new search and confirmation. |
| Actual listing prices | Loaded item books replace browse estimates | Refresh the displayed candidate from the exact prepared listing. Revalidate its ID, ownership, link, price, vendor/DE value and funds on the click. |
| Search pacing | `Pace.lua` measures readiness and reserves foreground slots | Shared budget for our searches: 75 background / 100 total per rolling minute; native readiness, measured background gaps and dropped-message backoff. |
| Next purchase | Reuse known individual auction IDs | Retain Profit Master's local stock checks; also remember a remaining ID when a quantity goal ends. |
| Market model | Log-price medians, trend/confidence and lower-tail filtering | Retain requested unit-weighted 10% trimming and equal-scan averages, plus the existing manual SQLite archive. Browse minima remain separate. |
| Profit ledger | Supplied vendor-profit counter credits purchases before merchant sale | Retain explicit potential profit and after-fee owned-auction Total/Incoming. Do not label a purchase as a realized vendor receipt. |
| Existing advice | Different DE/highlight/model features | Retain Safe DE, actual Disenchant icon, all-bag advice outside the AH, vendor sell icons, minimum profit and minimap settings. |

ProfitTop's manifest requires Blizzard_AuctionHouseUI; Auctionator pricing is
optional in that source. Profit Master retains its existing required Auctionator
integration. A dependency alone does not determine query latency.

## Limits and lifecycle

Quick scan is deliberately narrower than full discovery. It preserves candidates
outside its coverage and removes missing watched IDs only after a successful
nonempty batch sequence. The supplied source reports transient empty replies on
Forever; our scan retries an empty batch once, then reports uncertain coverage and
keeps previous candidates. Unrelated result keys also stop the scan explicitly.

Preparation reads at most 200 rows / roughly 4 ms per slice and has a five-second
deadline per item. It retains at most 40 quotes and 40 retry timestamps, rather
than all result books or the entire vendor database. Quote freshness is 60 seconds;
failed items are not attempted again within 30 seconds. There is no idle refresh
loop. Work resumes on relevant events or a bounded outstanding-work timer.
AH close unregisters preparation/pacing events and clears temporary references.

Buying takes priority over future preparation and Quick queries. A request already
sent to the server cannot be canceled locally. A click on the item currently being
prepared joins that search. A previously prepared click sends no extra query when
the native book still matches. An unresolved purchase retains the existing lock;
no callback, timer, timeout or error retries a purchase.

The rolling budget tracks Profit Master's calls. It cannot count or pause another
addon's private requests; Auctionator's own automatic browse scan can still delay
foreground verification. No other addon's settings or internal queue are modified.

## API evidence

Target: installed Forever **1.60.1.70938**, Interface **16001**, Auctionator **347**.
The relevant primary source is pinned to
[`bebcb6bf309cf41b41bd74f8ca651e6a105b2676`](https://github.com/Gethe/wow-ui-source/tree/bebcb6bf309cf41b41bd74f8ca651e6a105b2676).
[AuctionHouseDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua)
defines keyed searches, browse coverage/paging, search readiness, result getters
and purchase restrictions. The native Auction House caller reuses cached search
results; an executable item purchase still requires an actual auction ID.
Fifty keys is our conservative batch size, not a claim about a documented API cap.

Source inspection does not establish Forever server event ordering, cache capacity,
hardware-call permissions or latency. Those remain manual in-game checks.

## Validation and measured scope

Offline scenarios exercise the actual purchase/UI handlers, the native browse
state machine, and a deterministic search clock. They cover exact-ID checks,
changed prices (including between the two click-time checks), evicted books,
expired quotes, moved result positions, one bid per click, joined preparation,
foreground priority, the top-20 limit, saved settings, close cleanup, Quick batch
limits/pause/empty/foreign replies and rolling budgets.

All 18 Lua suites pass: **4,703 distinct assertions**, counting the shared main
harness once. The 31 Python SQL/parser tests pass. `Validate-Addon.ps1` validates
the manifest and 11 listed Lua files. The helper has no local `luac`; the suites
also load/execute the shipped Lua using the existing Lua 5.1 runtime. None of
these checks establish native game behavior or rendered layout.

Request-count results from those mocks:

| Scenario | Result |
| --- | --- |
| 300 watched keys, one nonempty page per batch | 6 explicit key queries |
| Stable prepared item click | 0 additional queries, 1 bid, 2 native result reads |
| Next known auction at the same price | 0 extra search queries; another click required |
| Unprepared or evicted item | Fresh verification and confirmation |
| Idle preparation | Stops after 20 eligible targets; never submits a purchase |

These counts are not live timing measurements. Full-market scans and full-history
snapshots still perform more work and are not replaced by the six-query example.
The previous incomplete trimmed-snapshot issue remains; a debug event now records
the rejected raw row index and reason instead of accepting an inaccurate mean.

## Manual check after installation

1. Fully restart the client for the new TOC files. Confirm version 0.2.0.
2. Run a normal scan with debug enabled; use Quick scan afterward and compare
   coverage/time. Inspect `/pmaster log` for `source=quick` and preparation timing.
3. On an inexpensive prepared row, verify **Buy 1** spends once. Confirm another
   copy separately; cancel and switch items. An unprepared row should first open
   confirmation. Repeat with one-click disabled in minimap settings.
4. Check quantities, native AH errors/throttling, another addon/tab, combat locks,
   and closing the AH during preparation/scan/purchase. Check preferences after
   reload and bag advice after leaving the AH.
5. Inspect the footer buttons and expanded settings at the normal and enlarged UI
   scale. Their rendered layout and input remain unobserved offline.
