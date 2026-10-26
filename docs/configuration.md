# Configuration

mofi reads one Lua file: `~/.config/mofi/init.lua` (or `$XDG_CONFIG_HOME/mofi/init.lua`). Create a starter with `mofi -init`.

It's plain Lua 5.4, so you can use variables, functions, `require`, `os.getenv`, `io.popen` and so on. Modules next to it can be `require`d: `require("theme")` loads `~/.config/mofi/theme.lua`.

## Reloading

Saving any `.lua` file in the config directory reloads the config. The daemon watches the folder, which also works when `~/.config/mofi` is a symlink into your dotfiles. You can also reload manually:

```sh
mofi -reload   # prints the error and exits 1 if the config is broken
mofi -check    # validate without touching the running daemon
```

A broken config doesn't take the launcher down. mofi keeps the defaults plus everything that ran before the error, and shows the error in red the next time it opens.

## `mofi.setup`

`mofi.setup(table)` deep-merges your table into `mofi.config`:

- tables (like `theme.colors`) merge key by key,
- lists (like `modi` or `keys.accept`) are replaced whole.

```lua
mofi.setup({
  theme = { colors = { border = "#ff9e64" } },  -- only the border changes
  modi = { "drun", "clipboard" },               -- replaces the whole list
})
```

To append to a list, edit `mofi.config` directly:

```lua
table.insert(mofi.config.clipboard.ignore_apps, "com.example.secrets")
```

`mofi -dump-defaults` prints every default as Lua. `mofi -lua 'mofi.config.theme'` prints the live values.

## Options

### Behavior

| Option | Default | Description |
|---|---|---|
| `modi` | `{ "drun", "run", "clipboard", "ssh" }` | Modes available in a `-show` session. <kbd>ctrl</kbd>+<kbd>tab</kbd> cycles them. Entries can be built-in modes, Lua modes, or `name:/path/to/script` rofi script modes. |
| `combi_modi` | `{ "drun", "run" }` | Modes merged by the `combi` mode. |
| `display` | `{ drun = "apps", … }` | Prompt / tab label per mode name. |
| `matching` | `"fuzzy"` | `"fuzzy"` (fzf-like subsequence), `"normal"` (substring), or `"prefix"` (start of a word). |
| `case_sensitive` | `"smart"` | `true`, `false`, or `"smart"` (case-sensitive only when the query has a capital). |
| `sort` | `true` | Rank matches by score. With `false`, matches keep the list order. |
| `cycle` | `true` | Moving past the last entry wraps to the first. |
| `hover_select` | `true` | Moving the mouse over a row selects it. Clicking selects, double-clicking accepts. |
| `auto_select` | `false` | Accept immediately when the query leaves exactly one entry. |
| `monitor` | `"mouse"` | Which screen to open on: `"mouse"` (under the pointer) or `"primary"`. |
| `path` | `{}` | Extra directories prepended to `PATH` for `run`, `mofi.exec` and `mofi.shell`. `PATH` itself comes from your login shell. |
| `terminal` | `nil` | How to open a terminal for `run` (<kbd>shift</kbd>+<kbd>enter</kbd>), `ssh` and `mofi.terminal`. `nil` autodetects Alacritty, Ghostty, kitty, WezTerm, iTerm, then Terminal. A string is a shell command where `{cmd}` is replaced by the quoted command; a function gets the command and returns a shell command. |

```lua
mofi.setup({ terminal = "open -na kitty --args /bin/sh -c {cmd}" })
-- or
mofi.setup({ terminal = function(cmd) return "wezterm start -- /bin/sh -c " .. mofi.quote(cmd) end })
```

### `drun`

| Option | Default | Description |
|---|---|---|
| `drun.paths` | `/Applications`, `/Applications/Utilities`, `/System/Applications`, `/System/Applications/Utilities`, `~/Applications`, Finder | Folders scanned for `.app` bundles (two levels deep), or a direct path to an `.app`. When names repeat, the first path wins. |
| `drun.exclude` | `{}` | App names or bundle ids to hide, e.g. `{ "Tips", "com.apple.Chess" }`. |

The app list refreshes in the background, so newly installed apps show up within a few seconds.

### `clipboard`

| Option | Default | Description |
|---|---|---|
| `clipboard.enabled` | `true` | Record clipboard history. |
| `clipboard.max_items` | `500` | Oldest entries are dropped past this. |
| `clipboard.poll_ms` | `250` | How often to check the pasteboard (one integer read; costs nothing measurable). |
| `clipboard.images` | `true` | Also keep copied images (stored as PNG). |
| `clipboard.paste_on_select` | `false` | Press <kbd>cmd</kbd>+<kbd>v</kbd> after picking. Needs Accessibility. <kbd>shift</kbd>+<kbd>enter</kbd> does the opposite for one pick. |
| `clipboard.ignore_apps` | 1Password, Bitwarden, Keychain Access, Passwords | Bundle ids whose copies are never recorded. |

Copies that apps mark as concealed or transient ([nspasteboard.org](http://nspasteboard.org) types, which most password managers set) are always skipped. History is stored in `~/.local/share/mofi/clipboard.json`, readable only by you.

### `keys`, `theme`

See [keybindings](keybindings.md) and [theming](theming.md).

## A full example

```lua
-- ~/.config/mofi/init.lua
mofi.setup({
  modi = { "drun", "run", "clipboard", "ssh", "calc" },
  auto_select = false,
  matching = "fuzzy",
  terminal = nil,
  drun = { exclude = { "Tips", "Chess" } },
  clipboard = { max_items = 1000, paste_on_select = true },
  keys = {
    next = { "down", "ctrl-n", "ctrl-j", "tab" },
    custom = {
      ["ctrl-o"] = function(ctx)  -- reveal the selected app in Finder
        if ctx.mode == "drun" and ctx.text then mofi.exec("open -R /Applications/" .. mofi.quote(ctx.text .. ".app")) end
        return true
      end,
    },
  },
  theme = require("theme"),  -- theme.lua returns a table
})

require("calc")  -- ~/.config/mofi/calc.lua, see examples/
mofi.bind("alt-space", "drun")
mofi.bind("alt-]", "clipboard")
mofi.bind("alt-=", "calc")
```

## Files

| Path | What |
|---|---|
| `~/.config/mofi/init.lua` | Your config |
| `~/.local/share/mofi/history.json` | Launch counts (frequent apps float up) |
| `~/.local/share/mofi/clipboard.json`, `clipboard-images/` | Clipboard history |
| `~/Library/Caches/mofi/mofi.sock` | Client ↔ daemon socket |
| `~/Library/Logs/mofi.log` | Daemon log |
| `~/Library/LaunchAgents/io.github.teddytennant.mofi.plist` | Login item (`mofi -install-agent`) |
