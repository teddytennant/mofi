-- Live calculator: type `2^10 / 3`, enter copies the result.
-- require("calc") from init.lua, then `mofi -show calc` or bind it.
local env = setmetatable({}, { __index = math })

mofi.mode("calc", {
  prompt = "calc",
  dynamic = true, -- items(query) runs on every keystroke; no fuzzy filtering
  items = function(query)
    if query == "" then return { { text = "type an expression", nonselectable = true } } end
    local f = load("return " .. query, "=calc", "t", env)
    local ok, v = pcall(f or error)
    if not ok or v == nil then return { { text = "…", nonselectable = true } } end
    return { { text = tostring(v), sub = "enter to copy", icon = "sf:equal.circle" } }
  end,
  on_select = function(item)
    if item then mofi.clipboard.set(item.text) end
  end,
})
