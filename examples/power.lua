-- macOS power menu with a confirmation step. Shows how on_select can
-- return a new list to keep the launcher open.
local actions = {
  lock = "pmset displaysleepnow",
  sleep = "pmset sleepnow",
  restart = [[osascript -e 'tell app "System Events" to restart']],
  shutdown = [[osascript -e 'tell app "System Events" to shut down']],
  ["log out"] = [[osascript -e 'tell app "System Events" to log out']],
  ["low power on"] = "sudo -n pmset -a lowpowermode 1",
  ["low power off"] = "sudo -n pmset -a lowpowermode 0",
}
local icons = { lock = "sf:lock", sleep = "sf:moon", restart = "sf:arrow.clockwise", shutdown = "sf:power",
  ["log out"] = "sf:rectangle.portrait.and.arrow.right", ["low power on"] = "sf:battery.25", ["low power off"] = "sf:battery.100" }
local order = { "lock", "sleep", "restart", "shutdown", "log out", "low power on", "low power off" }
local confirm = { restart = true, shutdown = true, ["log out"] = true }

local function main()
  local items = {}
  for _, name in ipairs(order) do items[#items + 1] = { text = name, icon = icons[name], action = name } end
  return items
end

mofi.mode("power", {
  prompt = "power",
  no_custom = true,
  items = main,
  on_select = function(item)
    if item.confirmed or not confirm[item.action] then
      if item.action ~= "cancel" then mofi.exec(actions[item.action]) end
      return
    end
    return {
      { text = "yes, " .. item.action, icon = "sf:checkmark", action = item.action, confirmed = true, urgent = true },
      { text = "cancel", icon = "sf:xmark", action = "cancel", confirmed = true },
    }
  end,
})
