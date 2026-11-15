# Profit Master disenchant source check (2026-11-13)

Target: Forever 1.60.1.70888 / interface 16001. No game input or in-game
disenchant observation was performed during this check.

## Exact client eligibility, not a loot distribution

The client's ItemDisenchantLoot table was read through
https://wago.tools/db2/ItemDisenchantLoot/csv?build=1.60.1.70888 and cached at
`scratch/disenchant-research/ItemDisenchantLoot-1.60.1.70888.csv`.

It has 54 rows: weapons/armor, uncommon item levels 5-99, rare 5-99 and epic
40-99. Every row has SkillRequired 0 and ExpansionID -2. Rare level 5-15
and 16-20 use new buckets 335-338. These rows match the older 70374 table,
but do not contain materials, quantities or probabilities: those are server loot.
Eligibility does not establish every item can be disenchanted; item exceptions
and flags also exist.

No disenchant-yield function was found in pinned Blizzard ItemDocumentation.lua
at UI mirror commit 4cd0ab752a77164f654ccbca9d0c1fe8dafceebe.

## Auctionator 346

The installed public API is
`Auctionator.API.v1.GetDisenchantPriceByItemID(callerID, itemID)` (or
`GetDisenchantPriceByItemLink(callerID, itemLink)`). It returns gross expected
copper or nil, without an auction cut. However, Forever uses its mainline
load route; Source_Mainline/Enchant/Main.lua uses a DE_TABLE containing
Warlords and newer expansion data, not original-era Forever gear. This API
therefore cannot provide the needed baseline value on this client.

The separate installed Source_Classic/Enchant/DisenchantingProbabilities.lua
contains Classic baseline facts, but is not the loaded Camelot implementation.
Its weapon level 51-65 entries total 102 percent (22 dust, 75 essence, 5 shard),
so should not be copied unquestioningly. Other independently inspected sources
use 22/75/3 there. Functions should not be copied; independently encode only
needed factual materials/probabilities with clear baseline-estimate labeling.

Public material pricing is usable:
`Auctionator.API.v1.GetAuctionPriceByItemID("ProfitMaster", materialID)` returns
the database price in copper or nil. GetAuctionAgeByItemID returns whole days
since observation, or nil for missing/older-than-retention data. No auction-cut
query exists in the pinned AuctionHouseDocumentation.lua; an assumed cut must
be described as an assumption and deposits/relisting are separate costs.

## Known Forever mismatch and conservative scope

Primary player observations, beta build 70374:
https://github.com/ClassicWoWCommunity/forever-bugs/issues/351

Twenty-two disenchants across twelve green weapon IDs at item levels 21-30
produced Greater Magic Essence instead of the expected Astral essences. That
does not establish exact live probabilities, and the level 26-30 dust/shard
distribution is unresolved by the observations. Exclude this range rather than
silently substituting an essence in an otherwise unverified table.

For an initial baseline estimate, exclude new item IDs >=200000, low-level
rare items below item level 21, unsupported levels above 65, and nondisenchantable
crafted wands 11287-11290. Shirts, tabards, bags, quivers and ammo should not
qualify as equipment to disenchant. Standard original-item probabilities remain
estimates, not exact live-server validation.

## Other addons inspected read-only

Installed Disenchantry 1.2.4 (MIT, copyright 2026 x_Raven_x and Rakuga) has its
own expected-yield module. It handles the weapon discrepancy, explicit new
craft estimates and empirical observations. Its ForecastPolicy deliberately
marks some new rares unverified and uses opted-in approximations, so those
estimates are not safe to advertise as verified facts. It exposes no stable
public valuation API and adding it as a dependency was not requested.

https://github.com/ForeverArtisan/ForeverArtisan/blob/main/ForeverArtisan_Core/Disenchant.lua
was read as corroborating primary addon source and cached outside shipped
addons at `scratch/disenchant-research/ForeverArtisan-Disenchant.lua`. It labels
the feature beta and the rules Classic tables, applies a 5% AH-cut assumption,
and records observations to compare with the estimates. It is all rights
reserved: do not copy implementation code. Its existence is not live validation
of the table for Profit Master.

No source/addon files in the installed game tree were changed.

## Minimum-outcome valuation follow-up (2026-11-14)

Read installed Auctionator 346 Source_Classic/Enchant/DisenchantingProbabilities.lua
without executing or changing it. Its explicit outcome counts establish the
following Classic baseline minima within our existing supported brackets:

- Green dust: 1 at ilvl5-15, 2 at16-20, 4 at21-25, 1 at26-30,
  then 2/1 alternating over31-35 through56-60, and 2 at61-65.
- Green essence: 1 through60 and 2 at61-65. A possible shard always yields1.
  Armor and weapons share these minima; changed green weapons21-30 stay excluded.
- Supported rare outputs are one shard or, where present, one crystal. Even a
  half-percent crystal outcome can be cheaper than the ordinary shard and must
  participate in the minimum. No probability weighting belongs in this mode.
- Epic40-55 has minimum2 shards,56-60 minimum1 crystal,61-65 minimum1 crystal.

Safe gross is the cheapest possible outcome at those minimum quantities, using
all required known positive material quotes. The existing 15% sale allowance is
applied afterward. These are independently encoded factual quantity minima, not
copied addon functions and not newly verified Forever server distributions.
No new API/eligibility assumptions or unsupported yield brackets were added.
