-- ~/.config/mofi/init.lua
-- Everything here is optional; defaults live in `mofi -dump-defaults`.
-- Saved changes reload automatically. Check for errors with `mofi -check`.
-- Docs: https://github.com/teddytennant/mofi/tree/main/docs

mofi.setup({
  modi = { "drun", "run", "clipboard", "ssh" },
  -- auto_select = true,          -- like rofi -auto-select
  -- terminal = "open -na Alacritty --args -e /bin/sh -c {cmd}",

  theme = {
    font = "Iosevka Nerd Font",
    font_size = 14,
    width = "42%",
    lines = 10,
    -- colors = { border = "#33ccff", selected_border = "#33ccff" },
  },

  clipboard = {
    max_items = 500,
    -- paste_on_select = true,    -- press cmd-v for you (needs Accessibility)
  },

  -- keys = {
  --   custom = {
  --     ["ctrl-y"] = function(ctx) mofi.clipboard.set(ctx.text or "") return true end,
  --   },
  -- },
})

-- Global hotkeys. cmd-space belongs to Spotlight unless you disable its
-- shortcut in System Settings > Keyboard > Keyboard Shortcuts > Spotlight.
mofi.bind("alt-space", "drun")
mofi.bind("alt-]", "clipboard")
mofi.bind("alt-shift-space", function() mofi.show({ "run", "ssh" }) end)

-- A custom mode: `mofi -show power`, or bind it.
mofi.mode("power", {
  prompt = "power",
  no_custom = true,
  items = {
    { text = "lock",     icon = "sf:lock",          cmd = "pmset displaysleepnow" },
    { text = "sleep",    icon = "sf:moon",          cmd = "pmset sleepnow" },
    { text = "restart",  icon = "sf:arrow.clockwise", cmd = [[osascript -e 'tell app "System Events" to restart']] },
    { text = "shutdown", icon = "sf:power",         cmd = [[osascript -e 'tell app "System Events" to shut down']] },
    { text = "log out",  icon = "sf:rectangle.portrait.and.arrow.right", cmd = [[osascript -e 'tell app "System Events" to log out']] },
  },
  on_select = function(item) mofi.exec(item.cmd) end,
})
mofi.bind("alt-shift-escape", "power")
