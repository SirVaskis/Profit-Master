# Profit Master improvement review — 2026-11-13

Reviewed source/installed build 0.1.21 while the user is away and cannot reload.
This is an evaluation, not a new release. No addon source, live settings or game
input was changed. Findings below separate reproduced code paths from suggestions
and in-game behavior that remains unobserved.

Follow-up: recommendations 1 and 2 were corrected in 0.1.30, alongside normalized
sell-search keys. The former race audit now runs the positive purchase-flow
regressions. See [the current implementation record](profit-master.md); the
reproductions below describe the earlier code, not the corrected build.

## Recommended next order

| Order | Improvement | Evidence and benefit | Size |
|---|---|---|---|
| 1 | Handle paging that is already complete | Reproduced needless 15-second stock wait and retaining an exhausted offer | Small |
| 2 | Keep a quote open while waiting for native readiness | Reproduced a fast confirmation canceling the quote; saved previews also show throttle not ready | Small |
| 3 | Show/cap material-price age | Current estimator accepts positive saved prices without an age check | Small–medium |
| 4 | Explain bag recommendations in the existing tooltip | Current icon compares DE with vendor value, not intact-item resale or personal gear usefulness | Small–medium |
| 5 | Offer a separate DE risk margin | Three copper expected gain is accepted despite random outputs and saved prices | Small |

The first two improve transaction flow without more scanning, dependencies or
automatic purchases. The last three improve decision quality rather than raw
scan speed. Leave the accepted 3c vendor threshold unchanged.

## 1. Paging can finish without another event

**Confirmed production-code behavior, reproduced offline.**

`ProfitMaster.lua:TryRecheck` ignores the boolean returned by
`RequestMoreItemSearchResults` and `RequestMoreCommoditySearchResults`; the manual
More listings handler also discards it. Pinned client documentation calls this
return `hasFullResults`. Blizzard's own item-buy caller handles it at
`scratch/profit-master-source/Blizzard_AuctionHouseItemBuyFrame.lua:105`.

Reproduction: a stock read sees partial data and queues a page request. Coverage
becomes complete before that deferred request executes. The request returns true
and emits no additional event. Profit Master waits for its 15-second deadline,
then keeps an exhausted candidate as unverified instead of using the already
complete empty result set.

Smallest change: when coverage is already complete, or the request returns public
true, reread that same result set immediately. Guard the original request/state
identity because native calls may also deliver synchronous events. Apply the same
handling to item and commodity paths. Do not retry purchases.

The exact event ordering has not been observed in the user's game, so the offline
reproduction establishes the code consequence, not its live frequency.

## 2. A quote can be clickable before the AH is ready

**Confirmed production-code behavior; the precursor also appears in saved logs.**

`ShowQuote` reports Buy 1 ready and opens the normal confirmation, but does not
keep its confirm button synchronized with native throttle readiness. `Buy` checks
`Ready()` and cancels the whole quote when the AH is still busy.

The saved 0.1.20 report includes previews #2287 and #2308 with
`throttle_ready=false`, followed by the Buy 1 ready status. The isolated audit
opens a quote in that state, clicks confirmation, and verifies that no bid is
submitted and the quote closes with the busy message. The user's actual clicks
in those saved examples were not shown to fail for this reason.

Smallest improvement: keep the confirmation open, temporarily disable only its
confirm button and display Waiting for AH, then enable it on native readiness.
Retain cancellation, expiry, final price/funds checks and the hardware-click rule.
No callback or timer may submit the purchase after the user has clicked early.

## 3. Include material-price freshness

**Known limitation, not a newly broken contract.**

`Disenchant.lua:Price` checks positivity but never asks how old a material quote is.
`ResetCache` rereads the saved value; it does not make an old quote fresh. Current
UI/docs already call these saved-price estimates, but no age is visible.

The installed public API
`Auctionator.API.v1.GetAuctionAgeByItemID("ProfitMaster", materialID)` is available
and returns coarse scan-day age. It is not an exact last-24-hours timestamp.

Suggested change: collect the oldest material age alongside each estimate, show
it on hover/confirmation and offer a freshness limit. Unknown age remains unknown.
A cap should use explicitly described scan days, not falsely promise hourly
freshness. This needs no extra AH requests.

## 4. Explain the bag verdict and absence of an icon

**Design improvement consistent with the user's all-bag-items choice.**

`Disenchant.ShouldMark` compares estimated after-allowance DE proceeds with NPC
vendor value. An illustrative item with vendor value 1g, DE estimate 1.5g and
intact-item AH estimate 10g still qualifies. That is the current documented policy,
not a classification bug, but a plain icon does not explain the distinction.

Suggested tooltip lines: estimated DE proceeds, NPC value, difference, price age,
baseline/random-output status, and Intact-item resale not compared. No icon may
mean missing prices/unsupported yields, not that an item is safe to vendor.

An optional intact-item resale comparison can follow, but must remain approximate:
Auctionator's item-link DB-key path, including its exactness helper, can fall back
to a base ID. Do not automatically suppress all markers based on a supposedly
exact resale value. A manual keep-item exclusion is another optional later feature,
not a default restriction on the all-items policy.

The tooltip integration API must be checked on the exact client and active bag UI
before implementation. It must not replace item clicks, dragging or item-use input.

## 5. Separate deterministic vendor gains from DE risk

**Optional feature, not a change to the accepted vendor minimum.**

`Deals.lua:Calculate` and the bag predicate allow 3c estimated gain for DE just as
for vendor comparisons. DE has random outputs, sale uncertainty and saved market
prices, so a tiny positive mean need not be a worthwhile purchase.

Suggested change: an independent DE minimum expected gain or percentage buffer,
clearly labeled. Preserve the 3c vendor floor. Choose a default with the user;
there is no source-based universal profitable risk threshold.

## Additional small reliability fix

Update: the 0.1.22 vendor-icon work addresses this item through its required
style/texture refresh path. The transaction and pricing proposals above remain
review recommendations, not implemented by that change.

Bag icons assign their texture only at creation. `Disenchant.Icon()` can retry
after an initially unavailable spell texture, but existing native and Baganator
regions never update their texture afterward. An isolated nil-to-valid-texture
probe reproduced the blank existing icon; whether the real client hits that
loading order remains untested. Update an existing texture only when the resolved
spell icon changes, without rebuilding the frame or adding a timer.

## Lower priority performance investigation

- `ReadLive` still processes and sorts the full initial item result book in one
  turn, unlike the bounded stock/commodity paths. A large-result test would tell
  whether a bounded scan that selects the best affordable row is worth doing.
  Current live records generally contain few eligible rows, so no user freeze is
  claimed from this code inspection alone.
- Native-pager diagnostics could separate request/response time, throttle wait,
  intentional purchase pauses and CPU work. The current provider_ms aggregate
  combines several of these; calling all of it server latency is too strong.
- A small retained transaction journal could preserve confirmed and uncertain
  purchases when the 1,000-event debug ring wraps. Expected profit must remain
  distinct from actual material/vendor revenue. This is a new feature, not a
  prerequisite for the current scan or a reason to add automatic mail handling.

Do not increase request rates, bypass cooldowns, add Lua coroutine machinery or
rewrite the valuation layer without new evidence. The actual earlier 0.1.20 scan
spent 15.251s in the provider window and 0.434s in measured processing slices;
0.1.21's in-scan Buy behavior still needs the user's next reload/test.

## Checks performed

- Read-only review of current production source and exact pinned client API/UI
  callers; no game control, network scan or probe was executed.
- `tools/Audit-ProfitMasterPurchaseRaces.lua` runs the existing 1,031-assertion
  integration harness unchanged, then reproduces both the ignored paging return
  and the early confirmation cancellation against production code. The audit
  intentionally asserts the current fault and must become a normal regression
  test or be updated when the fixes land.
- Compatible existing Lua 5.1 runtime; no packages installed. These are offline
  findings, not native-client security, rendering or performance verification.
- Installed 0.1.21 is left unchanged so the pending reload remains a clean test.
