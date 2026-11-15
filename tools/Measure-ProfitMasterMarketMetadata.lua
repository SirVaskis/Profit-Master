-- Offline synthetic memory measurement; never opens or controls WoW.
local addon = {}
time = function() return 1794751200 end
issecretvalue = function() return false end
assert(loadfile('addons/ProfitMaster/History.lua'))('ProfitMaster', addon)
addon.History.Initialize(nil)
for id=1,6895 do addon.History.RecordVendor('item:'..id,'Fixture '..id,100) end
collectgarbage('collect')
local before=collectgarbage('count')
for id=1,6895 do addon.History.RecordVendor('item:'..id,'Fixture '..id,100,nil,7,5,'Trade Goods','Cloth') end
collectgarbage('collect')
print(string.format('Category metadata for 6895 existing synthetic items: %.3f MiB additional Lua heap (offline)',(collectgarbage('count')-before)/1024))
