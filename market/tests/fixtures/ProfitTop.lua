-- Synthetic compatibility fixture in ProfitTop 0.1.13's saved schema.
-- This is not a real player scan; its market name makes that explicit.
ProfitTopDB = {
  version = 3,
  markets = {
    ["CompatibilityFixture-Alliance"] = {
      items = {
        ["6040:0:0:0"] = {
          s = {
            {1794664800, 4500, "b"},
            {1794751200, 4700, "l", "sample-id", 5, false},
            {1794751210, 4300, "p", "personal-purchase", 1}
          },
          l = {}, f = {}
        }
      }
    }
  },
  paid = { [6040] = { { ts = 1794751210, qty = 1, unit = 4300 } } }
}
