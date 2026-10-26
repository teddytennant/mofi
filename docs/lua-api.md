# Lua API

Your `init.lua` runs inside the daemon in a full Lua 5.4 with the standard libraries (`io`, `os`, `string`, `table`, `math`, `utf8`, `coroutine`, `debug`, `package`). The global `mofi` table is the API. Most of it is written in Lua: `mofi -dump-defaults` prints the whole runtime.

All Lua runs on the main thread, so a slow `items` function or `mofi.shell` call blocks the launcher while it runs. For long jobs, use `mofi.exec` (fire and forget).

You can also run Lua in the daemon from a shell:

```sh
mofi -lua 'mofi.config.theme.lines'     # prints 10
mofi -lua '#mofi.clipboard.history()'
mofi -lua 'mofi.show("calc")'
```

## Config

### `mofi.config`
The live config table. See [configuration](configuration.md).

### `mofi.setup(opts)`
Deep-merge `opts` into `mofi.config` (lists replace, tables merge). Returns `mofi.config`.

### `mofi.version`, `mofi.config_dir`, `mofi.data_dir`
Strings: `"0.1.0"`, `~/.config/mofi`, `~/.local/share/mofi`.

## Showing things

### `mofi.show(modes, opts?)`
Open one or more modes. `modes` is a name, a comma-separated string or a list. The first one gets focus.

```lua
mofi.show("drun")
mofi.show({ "run", "ssh" })
mofi.show("drun", { filter = "term", prompt = "open", message = "pick an app", lines = 5, auto_select = true })
```

`opts`: `prompt`, `message`, `filter` (initial query), `lines`, `auto_select`, `no_custom`, `password`, `matching`, `case_sensitive`, `selected_row`.

### `mofi.menu(items, opts?, on_select?)`
A one-off list, like piping into `mofi -dmenu` but without leaving Lua.

```lua
mofi.menu({ "light", "dark" }, { prompt = "appearance" }, function(item, ctx)
  local dark = (item and item.text or ctx.query) == "dark"
  mofi.exec(([[osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to %s']]):format(dark))
end)
```

`items` and `on_select` work exactly like a mode's (below). `opts`: `prompt`, `message`, `no_custom`, `filter`, `lines`.

### `mofi.hide()`
Close the launcher.

## Custom modes

### `mofi.mode(name, spec)`

```lua
mofi.mode("bookmarks", {
  prompt = "bookmarks",            -- string or function; defaults to display[name] or name
  message = nil,                   -- string or function, shown under the input
  items = {                        -- a list, or function(query) returning one
    "plain strings work",
    { text = "mofi", sub = "github", icon = "sf:link", url = "https://github.com/teddytennant/mofi" },
    { text = "section", nonselectable = true },
  },
  on_select = function(item, ctx)  -- item is your original table (nil for custom text)
    if item then mofi.open(item.url) end
    -- return nothing  → close
    -- return a list   → stay open showing that list
  end,
  on_delete = function(item)       -- optional: shift-delete; return false to keep the list as is
  end,
  no_custom = false,               -- true: enter does nothing unless an entry is selected
  sort_by_usage = false,           -- true: frequently picked entries float up
  dynamic = false,                 -- true: items(query) runs on every keystroke and isn't fuzzy-filtered
})
```

**Item fields**: `text` (required), `sub` (dim right-aligned text), `icon` ([spec](theming.md#icons)), `urgent`, `active`, `nonselectable`. Any other fields (`url`, `path`, `cmd`, …) are kept and handed back to `on_select`.

**`ctx`** in `on_select`: `query` (typed text), `alt` (<kbd>shift</kbd>+<kbd>enter</kbd>), `custom` (`true` when there's no item), `mode`.

**Multi-step menus**: return a list from `on_select` to replace the entries and clear the query:

```lua
mofi.mode("git", {
  no_custom = true,
  items = { { text = "switch branch" }, { text = "stash" } },
  on_select = function(item)
    if item.text == "switch branch" then
      local out = {}
      for b in io.popen("git -C ~/dots branch --format='%(refname:short)'"):lines() do
        out[#out + 1] = { text = b, branch = true }
      end
      return out
    elseif item.branch then
      mofi.exec("git -C ~/dots switch " .. mofi.quote(item.text))
    else
      mofi.exec("git -C ~/dots stash")
    end
  end,
})
```

**Live results**: with `dynamic = true`, `items` gets the query on every keystroke. See `examples/calc.lua` and `examples/websearch.lua`.

Lua modes can go in `modi` like built-in ones, and can be opened with `mofi -show <name>`.

### `mofi.script_mode(name, path)`
Register a rofi-protocol script as a mode (see [modes](modes.md#rofi-script-modes)). Same as putting `"name:path"` in `modi`.

### `mofi.modes()`
The table of registered Lua modes, by name.

## Hotkeys

### `mofi.bind(key, action)`
`action` is a mode name or a function. See [keybindings](keybindings.md#global-hotkeys). Raises an error if the key can't be parsed or registered.

## Processes

### `mofi.exec(cmd)`
Run `/bin/sh -c cmd` in the background (your home directory, your login `PATH`). Returns immediately.

### `mofi.shell(cmd)` → `stdout, status`
Run and wait. Blocks the launcher while it runs, so keep it quick.

```lua
local branch = mofi.shell("git -C ~/dots branch --show-current"):gsub("%s+$", "")
```

### `mofi.terminal(cmd)`
Open `cmd` in your terminal (`config.terminal`, or autodetected). `mofi.terminal_command(cmd)` returns the shell command without running it.

### `mofi.open(target)` → `bool`
Open a file or folder path, a URL (`https://…`, `raycast://…`, any scheme), an app name (`"Safari"`) or a bundle id (`"com.apple.Notes"`).

### `mofi.quote(s)`
Shell-quote a string: `mofi.quote("it's")` → `'it'\''s'`.

## Clipboard

| Function | |
|---|---|
| `mofi.clipboard.get()` | Current clipboard text (or nil) |
| `mofi.clipboard.set(text)` | Set the clipboard; it lands in history too |
| `mofi.clipboard.history()` | List of `{ kind = "text"\|"image", text, time, image? }`, newest first. `image` is the PNG path. |
| `mofi.clipboard.delete(i)` | Remove entry `i` (1-based) |
| `mofi.clipboard.clear()` | Wipe history |

## Misc

| Function | |
|---|---|
| `mofi.apps()` | Installed apps: `{ name, path, bundle_id }` |
| `mofi.notify(title, body)` | macOS notification |
| `mofi.log(...)` | Write to `~/Library/Logs/mofi.log` |
| `mofi.reload()` | Reload the config |
| `mofi.inspect(value)` | Pretty-print a table to a string |
| `mofi.merge(dst, src)` | The deep merge `setup` uses |
| `mofi.split(s, sep?)` | Split on `sep` (default `,`), trimming spaces |
| `mofi.exists(path)` | File exists |

## Splitting your config

`package.path` includes the config dir, so:

```
~/.config/mofi/
├── init.lua         -- require("theme"); require("modes.power")
├── theme.lua        -- return { … }
└── modes/
    └── power.lua
```

The `examples/` folder in the repo has `calc.lua`, `websearch.lua`, `power.lua` (with a confirmation step), `emoji.sh` (script mode) and `clipboard-menu.sh` (dmenu + Lua from a shell).
