-- The former race reproductions now run as positive purchase-flow regressions.
-- No game interaction, installation or SavedVariables file writes.
assert(loadfile("tools/Test-ProfitMasterPurchaseFlow.lua"))()
