# Profit Master performance follow-up — 2026-11-15

Build **0.2.1** fixes three issues found while the user is away. The new 0.2.0
scan/purchase capture has not yet been flushed to SavedVariables, so none of the
simulation results below is a finding about that live run.

## Saved evidence currently available

The read-only snapshot was last written at **16:01:14 CET** on November 15.
It contains retained events #24376–#25375. Its two newest session entries identify
0.2.0, but there are no scan, preparation or purchase events after those entries.
The user deferred the extra reload needed to save their subsequent tests.

The older completed browse scan at **15:39:46 CET** reports:

| Measurement | Recorded value |
| --- | ---: |
| Rows | 16,307 |
| Whole scan | 21.403 s |
| Receiving provider data | 20.532 s |
| Valuation / DE / retry slices | 0.468 s CPU |
| Instrumented vendor-loading work | 0.183 s CPU |
| Finalization after input | 0.859 s elapsed |

These slices can overlap; do not sum the CPU figures into a critical-path delay.
They point to receiving auction data as the main cost of that older full-house
browse run. They do not justify loading an entire vendor list into another cache.

The two retained old attempts are also informative: one commodity confirmation
opened in 254 ms (249 ms reply, 4 ms processing), then correctly canceled because
the server quote moved from 500 to 599 copper/unit. Another item spent 464 ms
waiting for the channel and about 278 ms awaiting/handling the reply, then found
zero eligible offers. The old log lacks a raw row count, so it cannot distinguish
an empty book from a book containing only ineligible auctions. No successful new
0.2.0 purchase is present in this saved snapshot.

## Reproduced fixes

**Preparation handoff.** An item reply starts background processing in slices.
Clicking before those slices finish previously joined the search and waited for
another result event, although the only reply had already arrived. The background
completion deliberately avoided replacing a selected purchase, leaving it waiting
until the verification timeout. A regression test reproduces this without another
server event. The foreground now takes ownership of the dispatched search, cancels
the remaining background work and reads existing results immediately when ready.
This does not send another query or authorize a purchase from a callback.

**Affordability.** With 100 copper available, a native book containing a profitable
500-copper variant and a profitable 50-copper variant made preparation select the
larger unaffordable profit. Preparation now selects an affordable candidate.
Foreground validation rechecks a changed gold balance before offering its quote.

**Large-book processing.** The old foreground reader stored every eligible deal,
sorted all of them, then traversed them again for availability. It now selects
the best affordable deal and groups availability in one pass, deduplicating IDs.
Each slice has an approximately four-millisecond budget and a 10,000-row cap.
The last getter can overrun the budget slightly. Cheap books can finish in the
same callback; the generous row cap avoids forcing cheap reads through many
frames. Book changes restart local valuation under the original deadline, with
no extra query. Closing cancels the job. Fired timers also release temporary
book caches in foreground, stock and commodity processing.

## Comparison and simulations

The supplied ProfitTop 0.1.13 uses an incremental minimum selection in
`Deals.ReadItemSearch`, but that reader is synchronous. Its chunked browse ingest
does not bound that item-book loop. Its market/tooltip index fixes address its
own model; Profit Master does not run that model or walk market history to price
each DE material. Those fixes should not be copied as unrelated machinery.

The benchmark loads actual Profit Master UI/purchase handlers and, optionally,
the supplied ProfitTop reader. Fixtures contain 200, 2,000 and 20,000 rows, owned
auctions and duplicate IDs. All tested native-cost scenarios preserve Profit
Master's selected cost, profit and available quantity. No real queries or bids
are made. The supplied reader finds the same lowest price; it also computes bids
and tiers, so total CPU is not a like-for-like comparison of entire addons.

Five trials of the 20,000-row fixture, using the existing offline Lua 5.1 runtime:

| Reader | Median offline CPU | Largest modeled native-read slice at 20 µs/read |
| --- | ---: | ---: |
| Profit Master 0.2.0 | 18 ms | 400 ms |
| Profit Master 0.2.1 | 3 ms | about 4.02 ms |
| Supplied ProfitTop 0.1.13 item reader | 43 ms | 400 ms |

Native read costs are assumed for the slice model, not measured from WoW.
Additional cases use 0.2 and 2 µs/read. In the cheap case, the 20,000-row new check
uses two callbacks, adding one modeled frame wait (16.7 ms at 60 FPS). At 2 µs it
uses ten callbacks, and at 20 µs it uses 100. These illustrate the responsiveness
versus elapsed-time tradeoff: yielding can add confirmation delay on huge books
while avoiding a long UI freeze. There is no claim that every book opens faster.
The handoff fix, independently, removes a wait for an event that will never recur.

Run `tools/Benchmark-ProfitMasterBooks.lua` through `Run-LuaChecks.py` with
`PROFITMASTER_AHTAB_SOURCE` set as for the other integration tests. Optional inputs:

- `PROFITMASTER_CORE_SOURCE`: a saved pre-change core file (a4f083d).
- `PROFITMASTER_COMPARE_PATH`: the supplied ProfitTop addon directory.
- `PROFITMASTER_READ_US`: modeled native getter cost, default 20 microseconds.

The comparison source remains ignored and unmodified. Benchmark results and raw
logs remain in ignored `scratch/`; no personal SavedVariables are committed.

## Diagnostics and pending checks

All **19 Lua suites** pass: **4,730 distinct assertions**, counting the shared
main harness once. The **31 Python SQL/parser tests** and manifest/file checks
also pass. Lua suites load/execute production code with the existing Lua 5.1
runtime; the validator itself has no local `luac`. These are offline checks.

`prepared_lookup` now reports hits, age/display changes, already bought IDs,
empty/unavailable native books, missing IDs and changed/unavailable valuations.
`prepared_search_handoff` records whether the reply was already received.
`item_book` includes raw rows, eligible rows, minimum raw buyout, batch count and
processing time. The minimum may include ineligible or owned auctions and is
diagnostic only. It does not authorize spending or become a market-history mean.

The supplied addon permits a retained buyout quote when native results disappear;
Profit Master continues requiring the native ID/value check. The new diagnostics
will show whether missing native books are costing actual waits. Their cause and
frequency remain unknown until the fresh capture is saved.

The next user reload can both save their 0.2.0 tests and load 0.2.1. Then inspect
the saved capture before claiming a live speedup. Test a click during preparation,
an affordable variant, normal quantities and one inexpensive purchase. The fixed
paths never buy automatically and retain exact-ID, value, price, ownership, funds,
hardware-click and uncertain-purchase protections.
