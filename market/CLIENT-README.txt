Profit Market Windows client 0.1.0 (Windows x64)

1. Copy client-config.example.json to client-config.json.
2. Add the HTTPS receiver URL and private upload token from the server operator.
3. Check game_root, or replace it with saved_files containing absolute paths.
   Both ProfitMaster.lua (schema 1) and ProfitTop.lua (schema 3, addon 0.1.13)
   are supported. No addon changes are needed.
4. In PowerShell, from this folder:

   .\ProfitMarketClient.exe --config .\client-config.json sync
   .\ProfitMarketClient.exe --config .\client-config.json watch

The first command uploads once; the second continues until Ctrl+C.
You must /reload or log out of WoW yourself to save a newly completed scan.
The client never controls the game or writes its SavedVariables.

Check the queue with:
   .\ProfitMarketClient.exe status

Validate a save without uploading with:
   .\ProfitMarketClient.exe inspect "C:\path\to\ProfitMaster.lua"

Default state: %LOCALAPPDATA%\ProfitMarket\collector.sqlite
Keep this state across upgrades and run only one collector using it.
Failed uploads remain queued for retry. Protect the config and state; do not
share them publicly. Do not include account/debug/purchase logs in reports.

This first build is an unsigned console application. It needs neither Python
nor Docker installed. Remote uploads require HTTPS; loopback HTTP is permitted
for local testing. The server uses PostgreSQL and a Grafana dashboard.

Prices represent auction asks, not completed sales. ProfitTop floor/VWAP and
Profit Master daily quotes remain separately labeled. Trimmed scan averages
are shown only when the addon actually saved valid trimmed measurements.

Full source and server handoff: https://github.com/SirVaskis/Profit-Master
See market/README.md in the source/server package for deployment and checks.
