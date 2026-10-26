# Coming from rofi

mofi keeps rofi's model (modes, `-show`, `-dmenu`, script modes), so most of a rofi setup carries over. The differences: the config is Lua instead of `config.rasi`, and there's no `window` mode. Window switching on macOS belongs to your WM (AeroSpace, yabai) or <kbd>cmd</kbd>+<kbd>tab</kbd>.

## Commands

| rofi | mofi |
|---|---|
| `rofi -show drun` | `mofi -show drun` |
| `rofi -show run` | `mofi -show run` |
| `rofi -show ssh` | `mofi -show ssh` |
| `rofi -show combi -combi-modi drun,run` | same |
| `rofi -show window` | not supported (use your WM) |
| `cliphist list \| rofi -dmenu \| cliphist decode \| wl-copy` | `mofi -show clipboard` (built in) |
| `greenclip print \| rofi -dmenu` | `mofi -show clipboard` |
| `rofi -dmenu -p x -format s` | same |
| `rofi -show drun -auto-select` | same |
| `rofi -e "message"` | same |
| `rofi -modi 'emoji:~/bin/emoji.sh' -show emoji` | same |
| `rofi -dump-config` | `mofi -dump-defaults` |

rofi-only flags (`-theme`, `-theme-str`, `-show-icons`, `-kb-*`, `-me-*`, `-display-*`, `-font`, …) are accepted and ignored, so scripts that pass them still run.

## `configuration { }` → `mofi.setup`

| rofi | mofi |
|---|---|
| `modi: "drun,run,window";` | `modi = { "drun", "run" }` |
| `combi-modi: "drun,run";` | `combi_modi = { "drun", "run" }` |
| `display-drun: "apps";` | `display = { drun = "apps" }` |
| `show-icons: true;` | `theme = { show_icons = true }` |
| `matching: "fuzzy";` | `matching = "fuzzy"` |
| `case-sensitive: false;` | `case_sensitive = false` |
| `sort: true;` | `sort = true` |
| `cycle: true;` | `cycle = true` |
| `hover-select: true;` | `hover_select = true` |
| `auto-select: true;` | `auto_select = true` |
| `terminal: "alacritty";` | `terminal = "alacritty -e /bin/sh -c {cmd}"` |
| `kb-row-down: "Down,Control+n";` | `keys = { next = { "down", "ctrl-n" } }` |
| `kb-accept-entry: "Return";` | `keys = { accept = { "return" } }` |
| `kb-mode-next: "Shift+Right";` | `keys = { mode_next = { "shift-right" } }` |
| `kb-remove-to-eol` and similar | see the [action list](keybindings.md#launcher-keys) |
| `me-select-entry: "MousePrimary"; me-accept-entry: "MouseDPrimary";` | built in: click selects, double-click accepts |

Key names in rofi syntax (`Control+Shift+Tab`) parse as-is.

## Porting a `.rasi` theme

The rasi widget tree maps onto `theme`:

| rasi | mofi `theme` |
|---|---|
| `* { font: "JetBrainsMono Nerd Font 11"; }` | `font = "JetBrainsMono Nerd Font", font_size = 14` (macOS points render smaller; ~1.3× your rofi size) |
| `window { width: 42%; border: 2px; border-radius: 10px; border-color: …; background-color: …; }` | `width = "42%", border = 2, radius = 10, colors = { border = …, background = … }` |
| `window { location: north; y-offset: 100px; }` | `location = "top", y_offset = 100` |
| `mainbox { padding: 16px; }` | `padding = 16` |
| `inputbar { padding: 10px 12px; border-radius: 8px; margin: 0 0 10px 0; background-color: …; }` | `input = { padding = { 10, 12 }, radius = 8, margin = 10 }, colors = { input_background = … }` |
| `prompt { text-color: …; }` | `colors = { prompt = … }` |
| `entry { placeholder: "search…"; placeholder-color: …; }` | `placeholder = "search…", colors = { placeholder = … }` |
| `listview { lines: 10; fixed-height: true; spacing: 2px; }` | `lines = 10, fixed_height = true, row_spacing = 2` |
| `element { padding: 10px 14px; spacing: 12px; border-radius: 8px; }` | `element = { padding = { 10, 14 }, spacing = 12, radius = 8 }` |
| `element selected.normal { background-color: …; border: 0 0 0 3px; border-color: …; }` | `element = { selected_border = 3 }, colors = { selected_background = …, selected_border = … }` |
| `element normal.urgent { text-color: …; }` | `colors = { urgent = … }` |
| `element normal.active { text-color: …; }` | `colors = { active = … }` |
| `element-icon { size: 26px; }` | `icon_size = 26` |
| `message { background-color: …; }` | `colors = { message_background = … }` |

The default mofi theme is this exact port of a rofi config:

```lua
-- from geohot.rasi: bg #000000, bg-light #292e42, border #33ccff, fg #c0caf5, grey #565f89, red #f7768e
mofi.setup({
  theme = {
    font = "Iosevka Nerd Font", font_size = 14,
    width = "42%", border = 2, radius = 10, padding = 16,
    lines = 10, fixed_height = true, row_spacing = 2, icon_size = 26,
    placeholder = "search…",
    input = { padding = { 10, 12 }, radius = 8, margin = 10 },
    element = { padding = { 10, 14 }, radius = 8, spacing = 12, selected_border = 3 },
    colors = {
      background = "#000000", border = "#33ccff",
      input_background = "#292e42", prompt = "#33ccff",
      foreground = "#c0caf5", placeholder = "#565f89",
      selected_background = "#292e42", selected_border = "#33ccff",
      urgent = "#f7768e", active = "#33ccff",
      message_background = "#292e42",
    },
  },
})
```

## Scripts

- **dmenu scripts** work unchanged once you swap `rofi` for `mofi`. A common trick is a picker that uses fzf in a terminal and the launcher otherwise:

  ```sh
  pick() { if [ -t 2 ]; then fzf --prompt="$1: "; else mofi -dmenu -p "$1"; fi; }
  ```

- **Script modes** (`ROFI_RETV`, `ROFI_INFO`, `\0prompt\x1f…`, `\0icon\x1f…`) work unchanged. mofi sets the same environment variables.
- **Linux-only bits** need macOS equivalents: `wl-copy`/`xclip` → `pbcopy`, `notify-send` → `mofi.notify` or `osascript -e 'display notification …'`, `systemctl suspend` → `pmset sleepnow`, `loginctl lock-session` → `pmset displaysleepnow`.

Since mofi has Lua built in, small menus that used to be shell scripts can live in `init.lua` as [modes](lua-api.md#custom-modes). See `examples/power.lua`.
