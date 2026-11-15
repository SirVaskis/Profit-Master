# Market pipeline and trend view — 2026-11-15

The Windows console collector reads either Profit Master schema 1 or the supplied
ProfitTop 0.1.13 schema 3, stages a durable SQLite outbox and sends authenticated
gzip parts to a PostgreSQL receiver. Grafana's datasource uses a restricted reader.
The server handoff is Docker Compose; the local proof ran native PostgreSQL 18.7
and Grafana 13.3.1 because this PC has no Docker or WSL.

The public view now concentrates on average-price trends: AH categories with
Trade Goods selected by default, subclass/item filters, up to twelve individual
line charts per page, a grouped-material comparison and 24H/7D/30D shortcuts.
Operational counts and raw data tables were removed. Chart legends show the
latest average and period change; the comparison also shows period lows/highs.
Visual inspiration: [WoW Price Hub's token view](https://wowpricehub.com/token/us).
Its content/assets were not copied and no token, alert or forecast features were added.

Real native data imported successfully: 109,091 daily quote slots. A later sync
cleared 55 acknowledged parts without creating duplicate price slots. These
quotes are archived but are not averages. The average views use valid trimmed
mean sum/count rollups or separately selected ProfitTop sampled VWAPs. The real
save still contains no valid trimmed averages. Local visual QA uses explicitly
named fixtures with fake item IDs, never substituted into the real market.

Profit Master 0.2.2 adds four category fields to already cached item metadata and
retains successful full-distribution scan timestamps once per day bucket. There
are no additional item-info calls, item loads, timers or AH queries. Category
fields reuse GetItemInfo returns 6/7/12/13. Numeric and string fields are checked
for secret values before use. Existing category information survives missing or
restricted later returns. Category metadata can classify either addon's item IDs
on the receiver; a ProfitTop-only server remains unclassified until a catalog is
received. No name-based guesses are used.

The synthetic Lua 5.1 measurement for adding these fields to 6,895 existing item
records was **0.768 MiB** of additional heap. This is an offline measurement,
not a measured in-game total. Reproduce it with `tools/Run-LuaChecks.py`, an
existing Lua 5.1 DLL and `tools/Measure-ProfitMasterMarketMetadata.lua`.

API evidence: Forever [version 1.60.1.70938](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/version.txt),
[C_Item generated documentation](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua),
and [item class enums](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemConstantsDocumentation.lua).
The installed Auctionator Forever class list and BagCache caller also use these
class/subclass results. This is source verification, not a new in-game API test.

UTC source observation timestamps, native file revision and server receipt stay
separate. `market.scan_times` de-duplicates explicit successful full-scan markers
and ProfitTop's market snapshot times. Historical PM daily rollups cannot recover
old individual scan timestamps/prices. New markers do not imply that the daily
average chart contains every individual scan price.

Validation: 24 pipeline unit/integration tests plus 31 existing parser/SQL tests.
Real HTTP/PG tests cover duplicate acknowledgments, conflicts, stale revisions,
rollback, gzip/auth rejection, restart/offline recovery, read-only access, actual
source timestamps, daily sum/count averages and the shared category catalog.
Lua 5.1 checks cover the changed history and vendor paths; manifest checks passed.
Browser QA confirmed separate item charts, grouped charts, the Cloth filter,
preserved filter navigation and period links. Compose configuration validates;
Docker container build/start is still untested here. The Windows EXE, ZIP entry
lists and credential exclusion are checked separately during packaging.

When ready: `/reload` to load 0.2.2, run a full-distribution scan when available,
then `/reload` or logout to save the results. Verify that new category metadata
and full-scan times export; a rejected/incomplete distribution must never become
an average. No game input or reload was performed by the development tools.
