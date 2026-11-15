Profit Master 0.1.34 - bag advice outside the Auction House

Requires WoW Forever (Interface 16001) and Auctionator.
Auctionator is a required dependency in the TOC, not an optional integration.
Affected APIs source-checked against Forever build 1.60.1.70938 and Auctionator 346.
This version is not yet tested in-game. Auctionator integration uses internal scan events and its
full-scan controller; future Auctionator changes may require an update.

Minimap settings and idle behavior
- Click the gold-coin minimap button for all four existing settings: debug logging,
  disenchant profits, safe disenchant, and minimum profit in copper per item.
  The panel also opens the existing manual Debug report. /pmaster settings opens
  the same panel without the Auction House; /pmaster still opens the auction tab.
- Settings and auction-tab controls stay synchronized and use the same purchase/
  scan locks. Whole-copper input applies on Enter or focus loss; Escape restores.
- Drag the button to any suitable position beside a round or square minimap. Its
  offset from the minimap's top-left corner is saved in ProfitMasterDB.minimap.
  There is no circular orbit calculation, shape override or drag polling timer.
  Dragging starts only outside combat; Close dismisses the settings panel.
- Outside the Auction House, auction scans/listeners and pending auction work
  stop. Closing releases temporary candidates/caches; scan again after reopening.
  Vendor/DE bag advice stays available anywhere with Disenchant profits enabled.
  It updates on bag, material-price and relevant item-readiness events, with no
  polling or recurring timers. Safe mode also applies to these recommendations.
- The loaded addon still occupies memory: code, saved history, reusable UI and
  bounded diagnostics remain. Minimap/settings/report clicks do work on demand.
  No automatic garbage collection, recurring timers or polling are added.
- After /reload, check the icon on your square/round map, drag it, open settings
  away from the AH, and verify position/preferences after another /reload.
  At the AH compare the tab controls and purchase locks; close it during a scan
  and confirm scanning stops but bag advice remains. Native appearance/performance remain unverified.

Safe disenchant
- Safe disenchant defaults ON, including when upgrading existing DE settings.
  Disenchant profits remains a separate opt-in checkbox. Uncheck Safe disenchant
  while idle to use the previous average-value calculation.
- Safe DE values every supported outcome at its minimum possible material count,
  chooses the cheapest outcome, then deducts the existing 15% selling allowance.
  Displayed profit subtracts the purchase price and must meet Min profit. A
  break-even outcome never counts as profit. No rare-drop upside is counted.
- Safe/average changes require an idle scan and no active price check, quote,
  purchase or stock recheck. Old DE values disappear immediately; qualifying
  vendor deals remain. Run a fresh scan after changing the mode.
- The DE value header and purchase confirmation identify minimum versus average.
  Bag advice follows the selected mode but still compares against vendor value,
  not purchase cost or the intact item's auction resale price.
- SAFE refers to the minimum in our baseline model, not guaranteed gold: Forever
  yields are unverified, saved prices may be stale and materials may not sell.
  Deposits/relisting costs are excluded. Unknown yields/prices remain skipped.
- After /reload, check Safe disenchant is checked, run a fresh scan with DE
  enabled, and compare one known item's cheapest material outcome after 15%
  against the displayed value. Confirm the new checkbox/text fit your UI scale,
  then verify the setting survives /reload. In-game verification remains pending.

Shorter waits between purchases
- Every confirmed individual purchase checks cached results first, including the
  last copy in a goal. Known unpurchased auctions at the same link/price can update
  stock and prepare the next quote without an additional server refresh.
- Local cached reads do not wait for a throttled-query slot. Search/refresh/page
  requests still wait for native readiness. Grouped rows with no known replacement
  auction ID still need a server refresh; hidden IDs are never guessed/reused.
- Native Blizzard/Auctionator purchase buttons submit an already-verified offer
  without checking search-throttle readiness. Our item/commodity confirmation
  buttons now follow that behavior. Session, combat, provider, price, vendor value,
  funds and explicit-click checks remain; unresolved purchases still block a
  second transaction until confirmation/error/timeout. Commodity quotes must still
  match the exact authorized price/total/quantity before confirmation.
- This removes addon-imposed query waits and redundant refreshes. It does not
  establish a fixed live latency or skip server replies. No automatic purchases,
  retries, faster query rate or new timer/polling path is introduced.
- The report starts with Latest price check: time queued before dispatch, time
  from dispatch to first matching results, and time from those results until
  the confirmation opens. The latter includes processing/any extra pages, not
  pure CPU. It is one runtime summary retained even with logging off; recorded
  transition times are not a ticking stopwatch. New items still need a query
  response because scan summaries do not include executable auction IDs.
- Manual check after /reload: buy two inexpensive individual auctions with a
  known second auction ID, confirming each. Then finish a one-copy goal while
  another same-price ID is known and select another item. Check that the new
  item needs no background stock-refresh roundtrip. A single grouped ID may
  still wait for a fresh replacement ID. For a wait before confirmation, open
  /pmaster log as soon as the dialog appears and copy the Latest price check
  summary/report before another selection or /reload replaces it.

Earlier purchase search and readiness corrections (0.1.30)
- Purchases discovered by full scans use a fresh sell-search key with level and
  suffix cleared, as the Forever API requires. The normalized key is also used
  for result events and remaining-stock checks. Browse searches keep their exact
  variant key. Live item links, vendor values and auction IDs are still verified.
- Item and commodity quotes preserve the quantity goal until accepted, canceled
  or expired. The broader query-throttle confirmation gate from 0.1.30 is
  superseded by the purchase-context checks described above. Native events never
  submit a purchase, and an unavailable-context click cannot queue a later buy.
- Paging checks already-complete results and the native hasFullResults return.
  Complete cached data is read immediately instead of waiting for an event that
  may never arrive. Synchronous callbacks cannot apply the old request to a new
  item or replace its quote. Stock pagination retains its original deadline.
- Manual check after /reload: verify a full-scan equipment offer opens a live
  confirmation. Choose two affordable copies and confirm each separately. The
  next quote should wait through a busy channel without losing its goal. Also
  check a second item and More listings where available. Copy /pmaster log
  immediately after an error, before another scan can overwrite its events.

Memory and scan measurements
- Opening Debug log or /pmaster log manually captures the client's attributed
  Lua memory for Profit Master and Auctionator. The expensive global memory-stat
  refresh is limited to once per 15 seconds, matching the native AddonList pattern.
  The report shows the two latest fresh samples, their ages, change and refresh
  cost. It works with debug logging off. No memory refresh runs in scan callbacks.
- This is addon Lua allocation attribution, not whole WoW process RAM, native
  item-cache memory or a peak. We do not explicitly request garbage collection.
  Normal collection, report/debug allocations and shared-library attribution can
  affect deltas. The reusable report UI is created before the first capture.
- A fixed-size last-scan profile is retained for complete, partial, failed and
  cancelled work, even with debug off. It counts unique missing item IDs/exact
  references, dispatched requests, usable-vendor completions, failures, unfinished
  requests at loader exit and unsent queued IDs. Retry valuation may subsequently
  read data even without a readiness callback. No extra item/AH requests or timers
  are added.
- Vendor pending time is the union of outstanding requests, with purchase pauses
  excluded. The report separately shows the part after provider input closes,
  average/longest successful readiness, loading/retry/valuation/DE processing
  slices, and history work. Record-loaded events alone do not end vendor loading.
  Nested synchronous readiness callbacks are counted once in loading work.
- Provider and pending times overlap processing; do not add these figures into a
  fake CPU/server breakdown. Post-input elapsed includes all finalization, not
  only vendor loading. CPU labels mean instrumented elapsed slices; loading
  callbacks can still process metadata while a purchase pauses discovery.
- Measurement procedure: /reload once, open /pmaster log before scanning, then
  close it. Run one normal scan without purchases. Open /pmaster log after it
  finishes, at least 15 seconds after the first capture. If Cached is shown, wait
  the stated remaining time and open it again. Copy with Ctrl+C and send the
  report before another /reload; memory samples and the last profile are runtime
  data. Scans of different modes and first-after-reload scans are not guaranteed
  to be equivalent cold/warm-cache comparisons.

Minimum scan profit
- Min profit, to the right of Disenchant profits, is a whole-copper amount per
  item. The default is 3c. A value of 10 keeps offers at 10c or more and hides
  smaller profits. Enter applies the value; clicking away also applies it, and
  Escape restores the saved value. Invalid entries restore the previous value.
- The preference is saved account-wide in ProfitMasterDB.minimumProfit. Values
  from 0 through 999999999 are accepted. Zero still excludes losses and break-even
  offers. It controls vendor and after-fee DE scan estimates, live verification
  and final Buy checks; grouped stock never multiplies the per-item threshold.
- Raising the minimum immediately removes lower-profit candidates and governs
  later rows in an active scan. Lowering it requires a fresh scan to recover all
  previously rejected offers. The setting does not start an auction query.
- The field remains usable during scans. Finish/cancel any live price check,
  confirmation, purchase or stock recheck before changing it. Debug and DE keep
  their independent preferences; their checkboxes are closer together to fit the
  new field, and the existing progress bar is slightly narrower.
- Bag advice and the 3c DE-versus-vendor strategy comparison are separate rules.
  The minimum changes scan-offer profit, not which bag items are recommended.
- Manual check after /reload: enter 10 and press Enter, scan and verify no row has
  less than 10c profit per item. Exactly 10c remains eligible. Raise it during a
  scan and check low-profit rows stay hidden. Lower it, run a fresh scan, then
  /reload to verify the saved value. Check focus/Escape and top-row spacing.

Owned-auction total validation
- Totals sum the client's canonical owned rows once by index. Auction IDs are
  not financial inputs; zero, shared or unavailable IDs no longer reject valid
  amounts. The client does not promise a unique positive ID for every payout row.
- Known zero remaining quantities contribute zero. Excluded active bid-only
  auctions do not require a quantity. Public prices/status and quantities needed
  for priced active rows are still checked; missing money is never invented.
- Incoming remains visible when only an active listing has unusable price data.
  Total still requires complete active and incoming amounts. Unknown sold amounts
  or unknown row status still prevent complete totals.
- Enable debug and show/refresh Auctions to capture owned_totals in /pmaster log.
  It includes the failing field category and row index if money remains unavailable,
  without exposing raw restricted values. No per-frame polling or new query.

Footer startup fix
- Corrects a Baganator integration error: RequestItemButtonsRefresh requires
  refresh reasons, not an addon-name string. Widget refreshes now use its public
  ItemWidgets reason list. This error could interrupt login before the auction
  footer initialized, and also affect later price updates.
- The owned-auction display now initializes before the separate scan/bag
  integrations, so a bag startup error cannot prevent its event registration.
- After updating from 0.1.24/0.1.25, fully exit and reopen WoW once to ensure the
  new OwnedAuctions.lua manifest entry is loaded, then open the Auctions tab.

Auction payout totals
- The native Auctions tab shows Total (5% cut) and Incoming to the left of Cancel
  Auction. Total = estimated active-listing proceeds + Incoming. Both cover all
  your owned auctions, regardless of the selected item filter.
- Active proceeds multiply listed unit buyouts by remaining quantities and deduct
  a 5% selling cut per listing, rounded down to whole copper. Known expired rows
  are excluded. It assumes every priced active listing sells. Unpriced active
  bid-only auctions are excluded with a visible no bid-only qualification.
- Incoming sums each Sold row's native reported Incoming Amount once. Those
  amounts already describe the whole sale: quantity and fees are not applied
  again. This follows the game's incoming display; it is not a mail-inbox total.
- The user selected the standard faction-house 5% cut. The current client does
  not expose the auctioneer's rate, so the percentage stays visible. This is
  not the 15% rate for a neutral auction house. Revisit the assumption there.
- This is estimated sale revenue after commission, not net economic profit.
  Acquisition/crafting costs are unavailable. Active estimates do not add deposit
  refunds; Incoming preserves the amount reported by the game without assuming
  which deposit components it contains. The display is not an exact mail total.
- Updates use the native owned-auction events and cached data. Loading, partial,
  unavailable or restricted data never appears as an authoritative zero. No new
  auction query, scan, timer, item load or SavedVariables are needed.
- The text follows Cancel Auction's visibility, so it hides on Bids and other AH
  tabs. The display accepts no mouse input and leaves cancel/refresh behavior alone.
- Manual check after /reload (or the first full restart): open Auctions. Incoming should match the sum of
  the native Sold amounts; Total minus Incoming should match active buyouts x
  quantities x 95% (rounded per listing). Switch filters, post/cancel an inexpensive
  listing and check the update. Sold rows must be counted once without multiplying
  their quantities. Bids and Profit Master must hide the footer. Check normal
  gold/cancel controls, long amounts and UI scaling.

Bag vendor/disenchant advice
- With Disenchant profits enabled, supported bag gear anywhere gets one small top-right
  icon: the Disenchant spell icon when estimated after-fee materials beat vendor
  value by at least 3c, or WoW's vendor-sale coin icon when vendor value wins by
  at least 3c. There are no SELL/DE text labels on bag slots. AH row DE text remains.
- Both sides must be known. Missing material/item data, unsupported yields and
  close ties produce no recommendation; they never default to selling. This
  does not mark every consumable/non-disenchantable item as something to vendor.
- The comparison uses expected baseline yields and saved material prices, with
  the existing 15% sale-fee allowance. It does not compare intact-item AH resale
  value, decide whether gear is useful to you, or mark anything as native junk.
- Applies to all qualifying inventory, not just Profit Master purchases. The same
  region changes icons as prices/items change, with normal bag/price/readiness
  events and combat recovery. No input capture, automatic sale or disenchanting.
  Unknown spell textures are retried on later refreshes rather than staying blank.
- Supported in standard Blizzard bags and the existing Baganator corner widget;
  existing widget ID/position preferences are retained. Disabling the checkbox
  hides both kinds of advice.

Saved database
- ProfitMasterDB is an account-wide WoW SavedVariables table. WoW writes it on
  normal logout or /reload; the addon does not write files or run a background service.
- It learns item IDs from observed buyout quotes and stores verified vendor values
  when the client returns them. A vendor value includes its exact item link, name
  and observation time. It is the latest observation for that ID, not a guaranteed
  sell value for every variant. A known zero is stored; missing values stay missing.
- Auction quotes are normalized to copper per item and summarized by UTC day:
  lowest, highest, latest observed quote, sample count and latest observation time.
  Samples are listing/summary observations, not sales or unique transactions.
- Complete replicate snapshots also calculate a unit-weighted trimmed mean per
  item ID: remove exactly 10% of units at each price tail, average the middle 80%.
  Stacks count by their units, with fractional weight at a trim boundary; copper
  precision is retained. Bid-only auctions have no buyout price and are excluded.
  These are asking prices, not completed sales. No missing history is backfilled.
- Each complete scan contributes one mean with equal weight. Daily per-item sums
  and counts preserve a future average of those means, plus the latest mean and
  its unit counts. This avoids storing every snapshot's full item table for 30
  days. Compute the later average as total mean sums / total scan counts; do not
  weight scans by stock size or give quiet and busy days equal weight by mistake.
- The raw native snapshot is read in bounded local batches, including price rows
  Auctionator omitted while item descriptions were unavailable. No extra server
  queries are sent. Missing/restricted numeric data or a replaced native snapshot
  prevents persistence of its means; partial work is discarded on AH close.
  Browse minima cannot supply this calculation and stay explicitly separate.
- Records are separated using Auctionator's connected-realm/regional-ruleset
  market grouping. Browse history also separates item level, suffix and pet species.
  Replicate history lacks those AH keys and is explicitly stored in a broader,
  separate per-item series; do not compare it as an exact variant history.
- Retains today and the preceding 29 UTC dates. Expired auction buckets are removed
  on login and the next scan after a UTC date change. Item/vendor records persist.
  Repeated scans update a daily summary rather than adding a new record per listing.
- Collection starts with this update. Missing days are not filled or backdated.
  Only observed data is recorded; no history is invented or imported.
- Auction quote history can grow while vendor data is incomplete. It does not
  establish that the vendor scan is working. The coverage message stays explicit.
- The Database line shows collected item/vendor/day counts for the current market.
  No history-based underpricing detection, alerts, or buying logic is added.
- Saved history is not used as a substitute for fresh Buy-time validation.

Buying while scanning
- Profit Master's Scan Auction House button owns a paced native browse scan when
  browse mode is selected. Buy is clickable as soon as its candidate appears.
  Selecting Buy pauses new discovery requests and gives the read-only item check
  the next available server slot; an in-flight page can still arrive. The exact
  quote still requires your normal confirmation click. Discovery resumes after
  the purchase/check/cancellation, including unavailable or unaffordable offers.
- The shared native AH throttle still applies. A queued read-only check has a
  30-second bound; its existing 15-second verification timer starts only when sent.
  Empty partial searches offer More listings for 15 seconds, then release discovery.
  No buy is submitted by a readiness event, scan callback or timer.
- Replicate processing uses a separate native result store and can overlap item
  checks. Externally started Auctionator browse scans remain supported, but their
  controller has no public pause API: clicking Buy queues its read-only check until
  that controller releases browsing. Use Profit Master's Scan button for paced
  browse discovery that can be interrupted by Buy. Auctionator remains required
  for pricing and external-scan compatibility; its settings are not overwritten.
- Leaving the Profit Master tab stops its owned discovery and marks captured
  results partial so another AH screen can use browsing safely. Pending committed
  purchases still receive their existing response handling. AH close cancels work.
- Both AH and bag indicators ask the client for spell 13262's actual Disenchant
  texture. There is no fixed generic Enchant icon.
- With Disenchant profits enabled, all eligible bag items are re-evaluated on bag
  opening/moves, filtered item-data readiness, and Auctionator DB updates, even if
  never purchased here and no Profit Master scan runs. The verdict compares saved
  expected material proceeds after the fee allowance with NPC vendor value.
  Updates are event-driven; there is no background polling or automatic disenchant.

Performance
- The first candidate still appears immediately. Further scan-only list updates
  coalesce for up to 250ms rather than 50ms, reducing repeated full-list sorting.
  Final results, Buy actions and purchase controls still refresh immediately.
  An unchanged final result is not sorted twice. Individual large sorts are still
  synchronous; coalescing reduces their frequency, not the cost of one sort.
- Unchanged visible row text, money values and enabled states are reused rather
  than repeatedly formatted and sent to the UI. Ineligible DE items skip detailed
  level lookups; missing material values are cached only for the current pricing
  generation and reconsidered when prices refresh. Missing item data stays retryable.
- Disabled bag markers do no bag-slot valuation. Native bag events no longer
  broadcast redundant Baganator refreshes or invalidate an active scan's prices.
  Option/value changes and combat recovery still refresh recommendations.
- Debug scan summaries include scan_ms (total elapsed client time), provider_ms
  (elapsed until Auctionator's completion callback) and batch_ms (sum of processing
  slice durations, including publication within those slices). Waiting, loading
  callbacks and purchase pauses are not all part of batch_ms. These are approximate
  client timings, not isolated server or native CPU measurements.
- history_rows, history_means and history_ms report raw financial rows read,
  per-item means saved and CPU slice time for price statistics. history_ms is
  included in batch_ms and excludes time paused for purchasing.
- Source-level reductions and synthetic benchmarks do not establish game FPS or
  faster server responses. The shared server throttle and scan cooldown remain.
- Processing/load dispatch/stock slices use the exact client's GetTimePreciseSec
  clock for the approximate 4ms budget and processing measurements. A single
  native call or full result sort cannot be preempted by this Lua budget.

Disenchant profits (optional)
- The Disenchant profits checkbox is beside Enable debug. It defaults off and is
  saved separately in ProfitMasterDisenchantDB. Debug and DE are independent.
  DE can be switched off during an automatic or manual scan while debug stays on.
  Vendor-profitable offers are retained at vendor value; DE-only offers and bag
  advice disappear, and later scan updates cannot restore the old DE estimates.
  The scan continues vendor-only. Enabling DE again waits for idle and needs a
  fresh scan. Finish/cancel any active price check, quote, purchase or stock check
  before changing the mode. Vendor offers remain available alongside DE offers.
- DE rows have the disenchant icon and a DE label. Their value column shows
  minimum (Safe ON) or average (Safe OFF) material-sale proceeds after a 15% allowance;
  profit subtracts the auction purchase price. The actual vendor price is retained
  separately and never multiplied by grouped stock. DE is chosen only when the
  selected DE net exceeds vendor value by at least 3c. Offer profit must also meet
  the configured minimum profit per item.
- Confirmation explicitly says DISENCHANT, with selected gross materials, estimated
  net/profit and model/price warnings. Material values are rechecked at
  Buy time. Every item still requires its existing authorized Buy click. There is
  no automatic disenchant, vendor sale, material posting, purchase or retry.
- Uses independently encoded original-era baseline yields/minima and saved
  Auctionator material prices. Every possible material must have a known positive
  price. Saved prices may be stale; sale prices, sales and random outcomes are not
  guaranteed. The 15% allowance is a reserve, not a query of the current AH fee.
  Deposits/relisting losses and profession/perk bonuses are excluded.
- Supported estimates cover original items with IDs below 200000, base item level
  up to 65 and known original-expansion metadata. Unknown/unsupported cases stay
  unmarked: new Forever items, rare gear below ilvl 21, green weapons ilvl 21-30
  with known changed Forever results, nondisenchantable crafted wands, shirts,
  tabards, bags, quivers, ammo, and missing/restricted item/material data.
  These baseline yields have not been validated by our own live disenchants.
- During scanning, DE estimates stream alongside vendor results. A bounded final
  pass reconciles material prices learned by that same scan, without duplicating
  history. Public item metadata is retained through native cache eviction; live
  purchase/stock updates take precedence over snapshot reconciliation.
- While enabled, ALL qualifying bag items receive a disenchant recommendation,
  including items not bought through Profit Master. Bag qualification compares
  selected DE net materials with vendor value, not purchase cost, intact-item AH
  resale value, equipment usefulness or whether your character has Enchanting.
  It is a recommendation, not a command to destroy gear you want to keep.
- Standard Blizzard bags get a single top-right recommendation icon. Installed
  Baganator gets the icon through its optional public corner-widget API, with a
  top-right default. Its normal initial widget insertion applies; later user
  repositioning/removal is respected. No Baganator code or direct settings writes.
  Other replacement bag UIs are not supported. Updates defer in combat; normal
  clicks, dragging and targeting stay unchanged. Disabling the checkbox hides
  recommendations and removes current DE offers; fresh scans can rediscover them.
- Manual check after /reload: enable the checkbox, scan, verify DE labels and the
  explicit purchase confirmation, open bags in Baganator/default bags, then turn
  the mode off and verify icons disappear. Check clicks/dragging and combat exit.
  Copy a debug report after a scan/buy if values or markers look incorrect.

Usage
1. Open an Auction House and select the Profit Master tab along the bottom.
   /profitmaster (/pmaster also works) selects the same tab while the AH is open.
2. Click Scan Auction House, or use Auctionator's Scan button. Profit Master now
   accepts its own paced browse scan plus Auctionator's browse and replicate scans.
   It prefers full replicate snapshots for history, using paced browse when the
   shared 15-minute replicate cooldown prevents another full snapshot.
   No cooldown is bypassed and Auctionator's configuration is not changed.
   Owned browsing shows received row counts; external scans show Auctionator's
   reported percentage while waiting for results/database completion. Then a vendor
   check count and reaches Scan complete only when candidate items are ready.
   Missing item data is requested once per unique ID, at most 32 requests per
   dispatch and 32 in flight. Loading item data shows progress; affected rows are
   rechecked when loading finishes, with a 60-second active loading budget.
   Time spent in a purchase flow preserves that budget while loading is paused.
   A successful basic item-record event does not finish a load unless the client
   actually returns name/vendor-price fields. GET_ITEM_INFO_RECEIVED is also
   listened to while loading. Both listeners stop on completion/timeout/AH close.
   Verified name/price fields are retained immediately in the current scan's
   cache, rather than looked up again after loading thousands of other items.
   This protects against native cache eviction. Exact-link variants stay separate.
   Incomplete data means some items could not be valued; zero candidates in that
   state is not proof that the Auction House contains no below-vendor deals.
   Browse percentages are Auctionator's estimate, not an exact server item count.
   The scan button reads Scanning... while work is active. Unavailable, failure,
   and stopped states are reported without invented progress or polling.
   Profit Master compares incoming browse batches and prepared replicate rows,
   publishing candidates as they arrive. External scans reuse Auctionator's row
   buffers; owned browsing sends one native page at a time and pauses for Buy.
   The completed payload reconciles remaining rows without repeating valuation
   or price-history observations already processed. Missing browse vendor data
   loads as incoming valuation drains between pages; ready rows appear as prices
   arrive. The same queue spans all pages, with no repeat request per item ID.
   Exact-link replicate loading still starts after the incoming queue closes.
   The final 60-second vendor-loading budget starts after incoming valuation ends.
   Buy is available immediately on visible candidates. A Buy pauses local valuation,
   which resumes afterward. The completion payload can arrive during that pause.
   This overlaps cooperative Lua work; it does not use multiple CPU cores or
   bypass the shared AH message throttle. Actual game speed remains unmeasured.
3. Both scan modes show estimated buyout, vendor value and profit per item.
   Replicate totals are normalized by their count. The Avail. column populates
   observed quantity: browse scans report total availability across prices, while
   replicate estimates retain their source row's count. This is not a promise that
   every copy is available at the displayed estimate, or a quantity bought at once.
   Browse vendor estimates read the base item ID's fresh sell price directly.
   Display/appearance links and a second link lookup are not required. This estimate
   can differ from a suffix/level variant; its exact live link is still rechecked
   before purchase. No saved or base-ID value can authorize an exact-link Buy.
   Both lists sort by their displayed per-item profit.
   Results below the configured minimum profit are hidden; the exact minimum
   remains eligible. The default is 3 copper per item.
   The same minimum applies to each live auction quote and its Buy-time check.
4. Click Buy beside an individual-auction candidate, or Buy qty for a commodity.
   Individual auctions are checked by auction ID, with a confirmation for the most
   profitable affordable auction. Commodities use a live commodity search and
   select the cheapest eligible price tier; higher tiers do not inflate its stock.
   Browse candidates use their exact item-level/suffix key, avoiding a broad
   search across all variants. There is no separate Check button or live-list view.
   The candidate list stays visible while waiting for a purchase response.
   A failed submitted buy removes only that item's row from the current scan.
5. For individual auctions, review the exact item link, auction ID, buyout, vendor
   value and profit. Non-commodity search quantity is grouped availability, not the
   number bought by PlaceBid. A confirmation buys one auction ID / one item;
   vendor value is never multiplied by the grouped count. For example, 139 pouches
   available at 3s each cannot beat a pouch's 2s50c vendor value and are excluded.
   Vendor quantity goals default to all verified stock affordable at this exact
   link and price. DE goals retain the half-stock default, capped by available
   gold. Editing a goal immediately updates its total cost/value/profit and the
   Buy 1 of N caption. The goal must be a whole number within
   current same-price availability and your gold budget. Every click submits only
   one exact-price auction. After success, another same-price copy opens the next
   confirmation with the remaining goal. Each copy still needs your Buy 1
   click; the search callback never purchases. The exact listing and vendor value
   are rechecked on every click. You may adjust the remaining goal in that popup.
   Cancel, Escape or the 30-second confirmation expiry keeps the result list.
   If no profitable affordable auction is returned, read the status message. Click
   More listings if additional search results are available, or Buy to check again.
   For commodities, the separate confirmation shows Quantity to buy, unit values
   and quantity totals. It defaults to all verified stock at the cheapest price,
   capped by your gold. Editing the quantity updates the Buy N caption, total cost,
   vendor value and potential profit. Click Buy N once
   to request that whole quantity. Only a server quote with exactly that unit price
   and total is confirmed; changed, unavailable or expired server quotes cancel
   and remove that stale offer from the current scan so the next item moves up.
   There is no per-item click, automatic retry, extra quantity or higher-price
   fallback. The quote confirmation completes the one purchase you requested.
   A pending quote is canceled if you leave the Profit Master tab or close the AH.
6. After every confirmed individual purchase, Profit Master checks the client's
   current results for another unpurchased auction ID at the same link and price.
   If found, the next quote or completed-goal stock update needs no extra refresh
   request. If only a purchased group ID remains, it refreshes for the next ID;
   quantity alone cannot supply it. Cached reads need no throttled query slot.
   Server refreshes/pages wait for the AH throttle and use the same link and price
   just paid. If eligible copies remain, it keeps the row and updates Avail.,
   unit prices and profit from those results. Otherwise it removes only that row.
   Confirmed auction IDs are excluded, and duplicate IDs are not counted twice.
   Rechecking inspects only the purchased item/price in bounded batches. Known
   matching stock can finish the check before every page is fetched; Avail. then
   shows >= followed by the observed count. Full results give an exact known count.
   Other rows and paging remain usable during the background check. Buying a
   different row cancels that check and keeps its unverified item. Stock checks
   never buy; only an active individual-auction goal opens the next confirmation.
   A successful commodity purchase also refreshes only its own item and keeps the
   row only when eligible stock remains at the purchased price. It does not start
   another quantity transaction. Missing metadata keeps an explicitly unverified row.
   Collect purchased items from your mail and sell them to a vendor yourself.

Debug logging
- Enable debug at the top of the Profit Master tab. It defaults off and remembers
  your choice. This is diagnostic logging, separate from 30-day price history.
- With debug enabled, reproduce the problem, then click Debug log or use
  /pmaster log. The selected text can be copied with Ctrl+C and pasted into chat
  here. Escape or Close dismisses the panel. No clipboard API is called.
- Captures searches, returned stock/coverage, preview prices, requested quantities,
  server unit/total quotes, confirmation calls, success/failure/error events,
  current gold/throttle/combat state, approximate client timing and row-removal
  decisions. Scan/batch/vendor-loading summaries are also included.
- The newest 1000 events are retained in a fixed-size ring, at most 1024 bytes
  per record. Restricted values are redacted, and raw objects are not serialized.
  There is no chat spam, idle polling, full per-row scan dump or automatic upload.
- ProfitMasterDebugDB holds the enabled setting and events; WoW saves it on normal
  logout or /reload. Logging off stops new records and preserves those collected.
  /pmaster debug on and /pmaster debug off provide the same control without the AH.
- The report is a snapshot. Reopen it after reproducing another problem. Debug
  logging adds diagnostic work while enabled; leave it off outside investigation.

Limits
- The snapshot is an estimate, not proof that an auction is still available.
- Live ID, item link, availability, price, vendor value, ownership and funds are
  checked before purchase. Other copies selling does not change the quantity of
  this one auction. A server-side race may still reject the buyout.
- A submitted buy that is rejected or blocked removes that item's row, retaining
  other results. An unconfirmed purchase timeout also removes the attempted item;
  it does not establish success or failure. Check mail/gold before buying again.
  Requests are never automatically retried. A fresh scan can rediscover the item.
- Internal auction errors also remove the attempted item when reported through
  UI_ERROR_MESSAGE with the localized ERR_AUCTION_DATABASE_ERROR text, or the
  DatabaseError auction event. For individual auctions, the outcome stays uncertain
  until a matching completion or the original 15-second purchase deadline. Other
  buys remain locked during that wait. A matching completion reports success;
  without it, check mail/gold before buying again. A gold change is not confirmation.
  The quantity goal stops, the removed offer stays excluded, and no retry is sent.
  Commodity errors continue to use the commodity transaction's completion events.
- A quantity goal ends on cancellation/expiry, error, insufficient gold or loss of
  eligible stock at the same exact link/price. It never moves to a higher price.
- Canceling/expiring the confirmation window or temporary busy/gold/combat states
  keep the item. Changed/disappeared individual listings, invalid commodity vendor
  data at Buy, rejected/changed/expired server quotes and complete live searches
  without a purchasable offer remove it. Partial/unknown data during a post-buy
  stock check still reports incomplete verification. Failure removal and confirmed
  exhaustion after buying affect only current candidates, not saved history.
- The post-purchase stock check has one overall 15-second deadline, including
  throttle waits and extra pages. Missing data, errors or timeout are reported as
  unable to verify; the row stays rather than claiming no stock. Closing the AH
  cancels the check. Switching tabs alone lets it finish. No full rescan is started.
- If the client blocks an action, the status reports the addon/function supplied
  by its blocked/forbidden event. /reload before another attempt. The exact cause
  of the user's original blocked-action warning has not yet been established;
  offline tests cannot verify that the client permits a purchase.
- Commodity purchase is one bounded request for the selected whole quantity.
  Own quantities are subtracted; rows containing account-owned items are skipped
  conservatively because the API does not provide their separate quantity.
  Server quote checks require both the displayed unit price and exact total cost.
  They reject price increases, decreases and mixed-tier totals that differ from
  the selected price times quantity. The configured minimum applies per item,
  not per batch.
- No verified bulk-quantity call exists for the individual-auction rows supported
  here. PlaceBid takes one auction ID and amount; a grouped quantity can expose
  only one ID. Those rows keep Buy 1; only true commodities use the quantity API.
  No automatic bid loop or protected-action workaround is added.
- Uses Auctionator's full-scan progress buffers and final browse/replicate payloads,
  not unrelated partial sale scans or old saved price databases. Candidates are reused during the session and their
  age is shown when reopened; they do not persist through /reload or client restart.
- Missing item data is loaded and retried once. Items still unavailable after
  loading/failure/timeout are explicitly counted. Pets, items with no sell value,
  and bid-only auctions remain excluded.
- The coverage report separates total rows, priced rows, unavailable rows,
  unsupported/pet rows, no vendor value, and prices not below vendor value.
  Below profit minimum counts valued results rejected at the minimum in effect
  when checked; a threshold changed during scanning can produce mixed decisions.
  Optional AH key metadata is not required just to evaluate a vendor price.
  A transmog appearance link is not treated as a vendor-price item link.
  It reports basic Item records OK separately from vendor data actually ready.
  A load notification alone is never counted as a verified sell price.
- Expected profit assumes client-reported vendor values minus the purchase cost.
  Commodity totals multiply those per-item amounts by the selected quantity.
  It is not realized profit tracking or a guarantee of completed vendor revenue.
- No unattended scanning/buying, mail collection, vendoring, or game input. A
  commodity quote is confirmed only for the exact transaction requested by Buy quantity.
- Processing uses one shared, bounded timer in batches of at most 1000, yielding
  after about 4ms of row processing if reached sooner. Stock checks cap batches
  at 200 with the same time budget and skip vendor lookups for other items/prices.
  Candidate redraws are coalesced. Purchases pause local scan work; metadata that
  arrives while paused is captured so native cache eviction cannot lose its price.
  It stops on AH close. Vendor values are retained in the current
  scan's cache through its loading/retry phases. Buy uses a fresh exact-link value.
  Switching tabs preserves a pending purchase response/timeout and its stock check.
- Reuses the LibAHTab library already provided by Auctionator. No additional
  library installation is needed. Normal AH tabs hide Profit Master's content.

Installation
Use the workspace tools/Install-Addon.ps1 -Name ProfitMaster helper, or copy this
ProfitMaster folder into the Forever client's Interface/AddOns folder.
If installed while the game is running, fully restart the client for addon discovery.
Only /reload is needed for later file updates to an already discovered addon.

Manual test checklist
- Confirm Auctionator still opens, scans and buys normally.
- Confirm exactly one Profit Master tab appears inside the Auction House. Switch
  between it, Buy/Sell/Auctions, and Auctionator tabs; content must not overlap.
- Open Profit Master and run one full scan. Confirm candidates are profit-sorted.
- Confirm immediate waiting/progress feedback, vendor-check counts, and a final
  Scan complete message. Switch away and back; the current progress must remain.
- With replicate on cooldown, confirm Profit Master starts the browse scan instead.
- Scan from Auctionator itself; confirm Profit Master gets the results without
  needing a second scan. Both modes must show / item columns and populated Avail.
  Buy must confirm one auction with its single-item vendor value.
- Compare scan/listing wait before and after, noting whether the progress text says
  waiting for server, finishing scan, or checking vendor prices. Server waits and
  throttles remain outside Profit Master's control; no in-game speedup is verified.
- On a cold item cache, confirm Loading item data appears and rows are rechecked.
  If the result is zero, read the priced/unavailable/unsupported counts; report
  those counts so missing coverage is not mistaken for an absence of bargains.
- For 0.1.6, compare priced/unavailable counts against the previous build. Read
  Item records OK and vendor data ready separately. If exact live vendor metadata
  is missing, the listing message must say so rather than report no profitable deals.
- For 0.1.7, confirm vendor data ready no longer collapses to a handful of priced
  rows during rechecking. The Database vendor-price count should grow as verified
  values are captured. Live confirmation is still required; no game test was run.
- Verify the Database counts increase after a scan. Use /reload yourself, reopen
  the tab and confirm saved counts remain. After a UTC date change, a new day's
  bucket is created on observation; there should be no fabricated past history.
- For 0.1.17, use /reload before testing to discard the previous UI execution state.
  Scan again; 1c and 2c profit rows must be absent, while 3c remains eligible.
  Confirm every candidate has Buy, with no Check step. Click Buy and compare the
  confirmation's auction ID, x1 quantity and price with the normal AH UI. A pouch
  at 3s with vendor value 2s50c must not be offered, regardless of availability.
- Cancel a confirmation; verify the original results remain and no gold is spent.
- Confirm Buy on one inexpensive profitable auction; verify gold and mail delivery.
  Success must show a stock recheck. With more copies at the purchased price, the
  row stays and Avail. shows that eligible count; with none left, only that row goes.
  Prices and vendor values must remain per item regardless of availability.
  A stock-check error/timeout must say unable to verify and keep the row. Other
  rows should stay usable while the purchased row says Wait....
  A rejected/blocked or unconfirmed submitted buy must remove only the attempted
  item. Other rows and
  paging remain usable, including when the failed item was alone on the last page.
  A fresh scan may list the item again; canceled confirmations keep it immediately.
  If blocked, report the exact addon/function now shown in the status message.
- On a cheap vendor item with multiple copies at one price, confirm that the goal
  starts at all verified same-price stock, capped by affordable gold. Edit to 2
  and check Buy 1 of 2 and total values immediately update. Confirm one auction,
  wait for the next popup and confirm another. With another
  returned auction ID, it should skip an extra refresh; grouped rows exposing only
  one ID still need a server refresh. The remaining goal must count down rather
  than halve again. The completed goal must finish with a stock refresh.
  There must be no second purchase without the second click. Cancel instead on
  another attempt and confirm the goal stops. An internal auction error must
  remove only that item, clear its goal and never retry it.
- On a cheap commodity, click Buy qty; check the maximum affordable default. Set
  quantity 2 and check Buy 2, unit values, total cost and profit, then click once.
  Verify the gold change and
  both items in the mail, with no second Buy click. Same-price stock should remain
  on the list afterward; an exhausted tier should disappear. A changed server
  quote must cancel and remove that stale row, never accept a higher total. Canceling before Buy, leaving the
  tab while quoting or closing the AH must prevent confirmation. Individual-auction
  rows must still use their original Buy 1 flow. Actual game behavior is unverified.
- After a full snapshot, check that the completion status reports trimmed means
  saved. A cooldown browse scan must instead say full data is needed for means.
  Buy during processing and cancel/complete the quote: history should resume with
  discovery. Close the AH during statistics and verify no partial mean is saved.
  /reload manually to persist history and include history_means in a debug report.
- Enable debug, reproduce a no-buy/stale-offer case, and open Debug log. The failed
  offer should disappear and the next row move up. Copy the report with Ctrl+C;
  check that it includes expected/received prices and removed=true for that item.
  /reload should preserve the debug preference and captured records. Turn debug
  off afterward and confirm old entries remain available with no new logging.
- During valuation/loading, confirm candidates appear before the final completion
  message. Buy an early result; other valuation must resume after its purchase
  flow, keeping removed items out and preserving the saved observation counts.
  Note actual game responsiveness; offline budgets are not an in-game FPS test.
- During a browse scan, confirm rows can appear while Auctionator is still
  receiving results. With a replicate scan, confirm prepared rows appear during
  its processing rather than only after the final database completion. Rows stay
  unavailable to buy while the provider owns the active scan. Once released, Buy
  may be used while the database finishes; final completion must preserve its
  confirmation. Compare time to the first visible and first buyable candidate.
  A failed scan must stop background valuation; closing the AH must stop all work.
- Sell that item manually; compare actual vendor revenue with the displayed value.
- Verify switching away and back during a request causes no duplicate buy.
- Close the AH while checking a listing; confirm no error or continuing work.
- Report exact errors and client/Auctionator versions. This build has only offline QA.
