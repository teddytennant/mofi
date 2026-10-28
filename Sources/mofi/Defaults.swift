// The Lua runtime that defines the public `mofi` API and every default.
// It runs before ~/.config/mofi/init.lua. Print it with `mofi -dump-defaults`.
let defaultsLua = #"""
-- mofi built-in runtime and defaults. Loaded before ~/.config/mofi/init.lua.
local N = __mofi
__mofi = nil

mofi = {
  version = N.version,
  config_dir = N.config_dir,
  data_dir = N.data_dir,
}

package.path = mofi.config_dir .. "/?.lua;" .. mofi.config_dir .. "/?/init.lua;" .. package.path

------------------------------------------------------------------------------
-- defaults
------------------------------------------------------------------------------

mofi.config = {
  modi = { "drun", "run", "clipboard", "ssh" },   -- modes for `mofi -show X`, ctrl-tab cycles
  combi_modi = { "drun", "run" },
  display = {                                     -- prompt / tab label per mode
    drun = "apps", run = "run", clipboard = "clipboard",
    ssh = "ssh", combi = "combi", dmenu = "dmenu",
  },
  matching = "fuzzy",        -- "fuzzy" | "normal" (substring) | "prefix" (word prefix)
  case_sensitive = "smart",  -- true | false | "smart" (sensitive only if the query has caps)
  sort = true,               -- rank matches by score
  cycle = true,              -- wrap around at the ends of the list
  hover_select = true,       -- mouse hover moves the selection
  auto_select = false,       -- accept as soon as one entry is left
  monitor = "mouse",         -- "mouse" (screen under the pointer) | "primary"
  path = {},                 -- extra dirs prepended to PATH for run/exec
  terminal = nil,            -- nil = autodetect; string with {cmd}, or function(cmd) -> shell command

  drun = {
    paths = {
      "/Applications", "/Applications/Utilities",
      "/System/Applications", "/System/Applications/Utilities",
      "~/Applications", "/System/Library/CoreServices/Finder.app",
    },
    exclude = {},            -- app names or bundle ids to hide
  },

  clipboard = {
    enabled = true,
    max_items = 500,
    poll_ms = 250,
    images = true,
    paste_on_select = false, -- also press cmd-v after picking (needs Accessibility)
    ignore_apps = {          -- bundle ids whose copies are never recorded
      "com.1password.1password", "com.agilebits.onepassword7",
      "com.bitwarden.desktop", "com.apple.keychainaccess", "com.apple.Passwords",
    },
  },

  keys = {
    accept        = { "return", "kp_enter" },
    accept_custom = { "ctrl-return" },             -- use the typed text, ignore the selection
    accept_alt    = { "shift-return" },            -- run: in terminal, drun: new window
    cancel        = { "escape", "ctrl-g", "ctrl-[" },
    next          = { "down", "ctrl-n", "ctrl-j", "tab" },
    prev          = { "up", "ctrl-p", "ctrl-k", "shift-tab" },
    page_next     = { "pagedown" },
    page_prev     = { "pageup" },
    first         = { "home", "cmd-up" },
    last          = { "end", "cmd-down" },
    mode_next     = { "ctrl-tab", "shift-right", "cmd-]" },
    mode_prev     = { "ctrl-shift-tab", "shift-left", "cmd-[" },
    delete_entry  = { "shift-delete", "shift-backspace" },
    backspace     = { "backspace", "ctrl-h" },
    delete_char   = { "delete", "ctrl-d" },
    delete_word   = { "ctrl-w", "alt-backspace" },
    clear_line    = { "ctrl-u", "cmd-backspace" },
    cursor_left   = { "left", "ctrl-b" },
    cursor_right  = { "right", "ctrl-f" },
    line_start    = { "ctrl-a", "cmd-left" },
    line_end      = { "ctrl-e", "cmd-right" },
    paste         = { "cmd-v" },
    custom        = {},      -- ["ctrl-y"] = function(ctx) ... end
  },

  theme = {
    font = "Iosevka Nerd Font",
    font_size = 14,
    width = "42%",           -- "NN%" of the screen or a pixel number
    location = "center",     -- "center" | "top" | "bottom"
    y_offset = 0,
    border = 2,
    radius = 10,
    padding = 16,
    lines = 10,
    fixed_height = true,     -- keep all rows reserved so the window doesn't jump
    row_spacing = 2,
    show_icons = true,
    icon_size = 26,
    show_modes = true,       -- mode tabs on the right of the input bar
    placeholder = "search…",
    input = { padding = { 10, 12 }, radius = 8, margin = 10, prompt_gap = 12 },
    element = { padding = { 10, 14 }, radius = 8, spacing = 12, selected_border = 3 },
    colors = {
      background          = "#000000",
      border              = "#33ccff",
      input_background    = "#292e42",
      prompt              = "#33ccff",
      foreground          = "#c0caf5",
      placeholder         = "#565f89",
      caret               = "#c0caf5",
      selected_background = "#292e42",
      selected_foreground = "#c0caf5",
      selected_border     = "#33ccff",
      match               = "#33ccff",
      sub                 = "#565f89",
      urgent              = "#f7768e",
      active              = "#33ccff",
      message_background  = "#292e42",
      message             = "#c0caf5",
      error               = "#f7768e",
    },
  },
}

------------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------------

local function is_list(t)
  return type(t) == "table" and (next(t) == nil or t[1] ~= nil)
end

-- Deep-merge `src` into `dst`. Lists are replaced, not merged.
local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" and not is_list(v) and not is_list(dst[k]) then
      merge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end
mofi.merge = merge

local function split(s, sep)
  local out = {}
  for part in tostring(s):gmatch("[^" .. (sep or ",") .. "]+") do
    out[#out + 1] = part:match("^%s*(.-)%s*$")
  end
  return out
end
mofi.split = split

local function value(v, ...)
  if type(v) == "function" then return v(...) end
  return v
end

function mofi.setup(opts)
  merge(mofi.config, opts or {})
  return mofi.config
end

function mofi.quote(s)
  return "'" .. tostring(s):gsub("'", [['\'']]) .. "'"
end

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end
mofi.exists = exists

------------------------------------------------------------------------------
-- natives
------------------------------------------------------------------------------

mofi.exec = N.exec
mofi.shell = N.shell
mofi.open = N.open
mofi.notify = N.notify
mofi.hide = N.hide
mofi.reload = N.reload
mofi.apps = N.apps

function mofi.log(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  N.log(table.concat(parts, " "))
end

mofi.clipboard = {
  get = N.clip_get,
  set = N.clip_set,
  history = N.clip_history,
  delete = N.clip_delete,
  clear = N.clip_clear,
}

------------------------------------------------------------------------------
-- terminal
------------------------------------------------------------------------------

local function applescript_string(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

-- Shell command that opens `cmd` in a terminal window.
function mofi.terminal_command(cmd)
  local t = mofi.config.terminal
  local q = mofi.quote(cmd)
  if type(t) == "function" then return t(cmd) end
  if type(t) == "string" then
    if t:find("{cmd}", 1, true) then return (t:gsub("{cmd}", function() return q end)) end
    return t .. " -e /bin/sh -c " .. q
  end
  if exists("/Applications/Alacritty.app") then
    local bin = "/Applications/Alacritty.app/Contents/MacOS/alacritty"
    return bin .. " msg create-window -e /bin/sh -c " .. q .. " 2>/dev/null || open -na Alacritty --args -e /bin/sh -c " .. q
  elseif exists("/Applications/Ghostty.app") then
    return "open -na Ghostty --args -e /bin/sh -c " .. q
  elseif exists("/Applications/kitty.app") then
    return "open -na kitty --args /bin/sh -c " .. q
  elseif exists("/Applications/WezTerm.app") then
    return "open -na WezTerm --args start -- /bin/sh -c " .. q
  elseif exists("/Applications/iTerm.app") then
    return "osascript -e " .. mofi.quote('tell application "iTerm" to create window with default profile command ' ..
      applescript_string("/bin/sh -c " .. q))
  end
  return "osascript -e " .. mofi.quote('tell application "Terminal" to do script ' .. applescript_string(cmd)) ..
    " -e " .. mofi.quote('tell application "Terminal" to activate')
end

function mofi.terminal(cmd)
  mofi.exec(mofi.terminal_command(cmd))
end

------------------------------------------------------------------------------
-- hotkeys
------------------------------------------------------------------------------

local binds = {}

-- mofi.bind("alt-space", "drun") or mofi.bind("alt-v", function() ... end)
function mofi.bind(key, action)
  local fn = action
  if type(action) == "string" then
    fn = function() mofi.show(action) end
  end
  assert(type(fn) == "function", "mofi.bind: action must be a mode name or a function")
  local id, err = N.bind(key)
  if not id then error("mofi.bind: " .. err, 2) end
  binds[id] = fn
end

function mofi._hotkey(id)
  local fn = binds[id]
  if fn then fn() end
end

------------------------------------------------------------------------------
-- showing
------------------------------------------------------------------------------

-- mofi.show("drun") / mofi.show({ "drun", "run" }) / mofi.show("drun,run", { filter = "fi" })
function mofi.show(modes, opts)
  if type(modes) == "string" then modes = split(modes, ",") end
  N.show(modes or mofi.config.modi, opts or {})
end

------------------------------------------------------------------------------
-- modes
------------------------------------------------------------------------------

local modes = {}
local last = {}

-- spec = {
--   items = table | function(query) -> list,  -- strings or { text, sub, icon, urgent, active, nonselectable, ... }
--   on_select = function(item, ctx) -> nil (close) | list (stay open with these items),
--   on_delete = function(item) -> bool,        -- shift-delete; true reloads
--   prompt, message = string | function,
--   no_custom, sort_by_usage, dynamic = bool,  -- dynamic: items(query) recomputed per keystroke
-- }
function mofi.mode(name, spec)
  assert(type(name) == "string", "mofi.mode: name must be a string")
  assert(type(spec) == "table", "mofi.mode: spec must be a table")
  modes[name] = spec
  return spec
end

function mofi.modes() return modes end

local function resolve(name)
  if modes[name] then return modes[name] end
  local short, path = name:match("^([^:]+):(.+)$")
  if short then
    local m = mofi.script_mode(nil, path)
    m.prompt = m.prompt or short
    modes[name] = m
    return m
  end
end

function mofi._has_mode(name)
  return resolve(name) ~= nil
end

local function norm(list)
  local out = {}
  for i, it in ipairs(list or {}) do
    if type(it) ~= "table" then it = { text = tostring(it) } end
    out[i] = it
  end
  return out
end

local function present(name, m, items)
  items = norm(items)
  last[name] = items
  local view = {}
  for i, it in ipairs(items) do
    view[i] = {
      text = tostring(it.text or ""),
      sub = it.sub ~= nil and tostring(it.sub) or nil,
      icon = it.icon,
      urgent = it.urgent, active = it.active, nonselectable = it.nonselectable,
    }
  end
  return view, {
    prompt = value(m.prompt) or mofi.config.display[name] or name,
    message = value(m.message),
    no_custom = m.no_custom or false,
    sort_by_usage = m.sort_by_usage or false,
    dynamic = m.dynamic or false,
  }
end

function mofi._items(name, query)
  local m = resolve(name)
  if not m then error("unknown mode " .. name) end
  return present(name, m, value(m.items, query))
end

function mofi._select(name, idx, query, alt)
  local m = resolve(name)
  local item = idx and last[name] and last[name][idx] or nil
  if not m.on_select then return nil end
  local r = m.on_select(item, { query = query, alt = alt, custom = item == nil, mode = name })
  if type(r) == "table" then return present(name, m, r) end
  return nil
end

function mofi._delete(name, idx)
  local m = resolve(name)
  if not (m and m.on_delete) then return false end
  return m.on_delete(last[name] and last[name][idx]) ~= false
end

function mofi._key(key, mode, text, query, idx)
  local fn = mofi.config.keys.custom[key]
  if not fn then return false end
  local item = idx and last[mode] and last[mode][idx] or (text and { text = text }) or nil
  return fn({ key = key, mode = mode, item = item, text = text, query = query }) == true
end

-- Open a one-off list from Lua, like piping into `mofi -dmenu`.
-- mofi.menu({ "a", "b" }, { prompt = "pick" }, function(item, ctx) ... end)
function mofi.menu(items, opts, on_select)
  if type(opts) == "function" then opts, on_select = {}, opts end
  opts = opts or {}
  mofi.mode("__menu", {
    prompt = opts.prompt or "menu",
    message = opts.message,
    no_custom = opts.no_custom,
    items = items,
    on_select = function(item, ctx)
      if on_select then return on_select(item, ctx) end
    end,
  })
  mofi.show("__menu", { filter = opts.filter, lines = opts.lines })
end

------------------------------------------------------------------------------
-- rofi script modes (https://davatorium.github.io/rofi/current/rofi-script.5/)
------------------------------------------------------------------------------

local function parse_script_output(out, m)
  local items = {}
  for line in (out .. "\n"):gmatch("(.-)\r?\n") do
    local text, opts = line:match("^(.-)\0(.*)$")
    text = text or line
    local kv = {}
    if opts then
      local parts = {}
      for p in (opts .. "\31"):gmatch("(.-)\31") do parts[#parts + 1] = p end
      for i = 1, #parts - 1, 2 do kv[parts[i]] = parts[i + 1] end
    end
    if text == "" and opts then
      -- mode option line: "\0prompt\x1fvalue"
      if kv.prompt then m.prompt = kv.prompt end
      if kv.message then m.message = kv.message end
      if kv["no-custom"] then m.no_custom = kv["no-custom"] == "true" end
    elseif text ~= "" then
      local icon = kv.icon
      if icon and not icon:find("^[/~]") and not icon:find(":") then icon = nil end
      items[#items + 1] = {
        text = text, icon = icon, info = kv.info,
        nonselectable = kv.nonselectable == "true",
        urgent = kv.urgent == "true", active = kv.active == "true",
      }
    end
  end
  return items
end

local function run_script(path, retv, arg, info)
  local cmd = "ROFI_RETV=" .. retv
  if info then cmd = cmd .. " ROFI_INFO=" .. mofi.quote(info) end
  cmd = cmd .. " " .. mofi.quote(path)
  if arg then cmd = cmd .. " " .. mofi.quote(arg) end
  local out = mofi.shell(cmd)
  return out
end

-- mofi.script_mode("emoji", "~/bin/emoji.sh"), or put "emoji:~/bin/emoji.sh" in modi.
function mofi.script_mode(name, path)
  path = path:gsub("^~", os.getenv("HOME"))
  local m = {}
  m.items = function()
    return parse_script_output(run_script(path, 0), m)
  end
  m.on_select = function(item, ctx)
    local out = item and run_script(path, 1, item.text, item.info) or run_script(path, 2, ctx.query)
    local items = parse_script_output(out, m)
    if #items > 0 then return items end
  end
  if name then mofi.mode(name, m) end
  return m
end

------------------------------------------------------------------------------
-- built-in Lua modes
------------------------------------------------------------------------------

mofi.mode("ssh", {
  sort_by_usage = true,
  items = function()
    local hosts, seen = {}, {}
    local home = os.getenv("HOME")
    local function add(h)
      if h and h ~= "" and not seen[h] and not h:find("[%*%?!]") then
        seen[h] = true
        hosts[#hosts + 1] = { text = h, icon = "sf:network" }
      end
    end
    local function parse(path, depth)
      local f = io.open(path)
      if not f or depth > 4 then return end
      for line in f:lines() do
        local key, rest = line:match("^%s*(%a+)%s*=?%s*(.-)%s*$")
        key = key and key:lower()
        if key == "host" then
          for h in rest:gmatch("%S+") do add(h) end
        elseif key == "include" then
          for inc in rest:gmatch("%S+") do
            inc = inc:gsub("^~", home)
            if not inc:find("^/") then inc = home .. "/.ssh/" .. inc end
            if inc:find("[%*%?]") then
              local p = io.popen("ls -1d " .. inc .. " 2>/dev/null")
              if p then
                for g in p:lines() do parse(g, depth + 1) end
                p:close()
              end
            else
              parse(inc, depth + 1)
            end
          end
        end
      end
      f:close()
    end
    parse(home .. "/.ssh/config", 0)
    local kh = io.open(home .. "/.ssh/known_hosts")
    if kh then
      for line in kh:lines() do
        local first = line:match("^(%S+)")
        if first and not first:find("^|") and not first:find("^@") then
          for h in first:gmatch("[^,]+") do
            if not h:find("^%[") then add(h) end
          end
        end
      end
      kh:close()
    end
    return hosts
  end,
  on_select = function(item, ctx)
    local host = item and item.text or ctx.query
    if host ~= "" then mofi.terminal("ssh " .. mofi.quote(host)) end
  end,
})

------------------------------------------------------------------------------
-- internals for `mofi -lua`
------------------------------------------------------------------------------

function mofi._eval(code)
  local f, err = load("return " .. code, "=mofi -lua")
  if not f then f, err = load(code, "=mofi -lua") end
  if not f then error(err, 0) end
  local r = table.pack(f())
  for i = 1, r.n do
    local v = r[i]
    r[i] = type(v) == "table" and mofi.inspect(v) or tostring(v)
  end
  return table.concat(r, "\t", 1, r.n)
end

function mofi.inspect(v, indent, seen)
  indent, seen = indent or "", seen or {}
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  if seen[v] then return "<cycle>" end
  seen[v] = true
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  if #keys == 0 then return "{}" end
  local lines = {}
  for _, k in ipairs(keys) do
    local ks = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or "[" .. mofi.inspect(k) .. "]"
    lines[#lines + 1] = indent .. "  " .. ks .. " = " .. mofi.inspect(v[k], indent .. "  ", seen)
  end
  return "{\n" .. table.concat(lines, ",\n") .. "\n" .. indent .. "}"
end
"""#
