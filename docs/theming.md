# Theming

Everything visual lives in `mofi.config.theme`. The default is a Tokyo Night look on pure black, ported from a rofi `geohot.rasi` theme.

```
┌ window ─────────────────────────────── border, radius, padding ┐
│ ┌ input ──────────────────────────────────────────────────────┐ │
│ │ prompt  query▏                          apps  run  clipboard │ │  ← show_modes
│ └─────────────────────────────────────────────────────────────┘ │
│ ┌ message (only when there is one) ───────────────────────────┐ │
│ └─────────────────────────────────────────────────────────────┘ │
│ ▌[icon]  Selected entry                                   sub   │  ← element
│  [icon]  Entry                                            sub   │
└─────────────────────────────────────────────────────────────────┘
```

## Layout

```lua
mofi.setup({
  theme = {
    font = "Iosevka Nerd Font",  -- family name; falls back to the system font
    font_size = 14,
    width = "42%",               -- percent of the screen, or pixels: width = 640
    location = "center",         -- "center" | "top" | "bottom"
    y_offset = 0,                -- push down (center/top) or up (bottom), in px
    border = 2,
    radius = 10,
    padding = 16,                -- inside the window border
    lines = 10,                  -- rows shown
    fixed_height = true,         -- false: shrink to the number of matches
    row_spacing = 2,
    show_icons = true,
    icon_size = 26,
    show_modes = true,           -- mode tabs on the right of the input bar
    placeholder = "search…",
    input = {
      padding = { 10, 12 },      -- { vertical, horizontal } or one number
      radius = 8,
      margin = 10,               -- gap below the input bar
      prompt_gap = 12,           -- between prompt and query
    },
    element = {
      padding = { 10, 14 },
      radius = 8,
      spacing = 12,              -- icon ↔ text and text ↔ sub
      selected_border = 3,       -- accent bar on the left of the selection; 0 to hide
    },
  },
})
```

Icons only take space when the current list has any, so plain `dmenu` lists stay compact.

## Colors

Colors are `"#rgb"`, `"#rrggbb"`, `"#rrggbbaa"` (with alpha) or `"transparent"`.

| Key | Default | Used for |
|---|---|---|
| `background` | `#000000` | Window |
| `border` | `#33ccff` | Window border |
| `input_background` | `#292e42` | Input bar |
| `prompt` | `#33ccff` | Prompt text, active mode tab |
| `foreground` | `#c0caf5` | Query and entries |
| `placeholder` | `#565f89` | Placeholder, inactive mode tabs |
| `caret` | `#c0caf5` | Text cursor |
| `selected_background` | `#292e42` | Selected row |
| `selected_foreground` | `#c0caf5` | Selected row text |
| `selected_border` | `#33ccff` | Accent bar on the selected row |
| `match` | `#33ccff` | Matched characters (also drawn bold) |
| `sub` | `#565f89` | Right-aligned secondary text (clipboard age, mode name in combi) |
| `urgent` | `#f7768e` | Entries with `urgent = true` |
| `active` | `#33ccff` | Entries with `active = true` |
| `message_background` | `#292e42` | Message box |
| `message` | `#c0caf5` | Message text |
| `error` | `#f7768e` | Errors in the message box |

## Example themes

Keep a theme in its own file and `require` it:

```lua
-- ~/.config/mofi/theme.lua
return {
  font = "JetBrainsMono Nerd Font", font_size = 13,
  radius = 14, border = 1, width = 560, lines = 8,
  colors = {
    background = "#1e1e2ef2",          -- slight transparency
    border = "#cba6f7",
    input_background = "#313244",
    prompt = "#cba6f7", match = "#f5c2e7",
    foreground = "#cdd6f4", placeholder = "#6c7086", sub = "#6c7086",
    selected_background = "#45475a", selected_foreground = "#cdd6f4", selected_border = "#cba6f7",
    message_background = "#313244",
  },
}
```

```lua
-- init.lua
mofi.setup({ theme = require("theme") })
```

**Spotlight-ish** (no border, big, top of the screen):

```lua
mofi.setup({ theme = {
  font = "SF Pro Text", font_size = 18, width = 680, location = "top", y_offset = 180,
  border = 0, radius = 16, lines = 8, fixed_height = false, show_modes = false,
  element = { selected_border = 0, radius = 10 },
  colors = { background = "#1c1c1ef0", input_background = "transparent", selected_background = "#0a84ff",
             selected_foreground = "#ffffff", match = "#ffffff", prompt = "#8e8e93" },
} })
```

**Gruvbox, square corners**:

```lua
mofi.setup({ theme = {
  radius = 0, border = 2,
  input = { radius = 0 }, element = { radius = 0 },
  colors = { background = "#282828", border = "#d79921", input_background = "#3c3836", prompt = "#d79921",
             foreground = "#ebdbb2", placeholder = "#928374", selected_background = "#504945",
             selected_foreground = "#fbf1c7", selected_border = "#d79921", match = "#fabd2f", sub = "#928374" },
} })
```

## Icons

Built-in modes set icons automatically: app icons, clipboard image thumbnails, a network symbol for ssh. In Lua modes and `dmenu` rows, an icon is one of:

| Spec | Meaning |
|---|---|
| `"sf:bolt.fill"` | An [SF Symbol](https://developer.apple.com/sf-symbols/), tinted with `foreground` |
| `"app:Safari"` | An installed app's icon, by name or bundle id |
| `"/path/to/file"` or `"~/…"` | Finder's icon for that file/folder/app, or the image itself for `.png` / `.jpg` / `.icns` / … |
| any other name | `NSImage(named:)`, e.g. `"NSFolder"` |

Nerd Font glyphs in the text itself work too, as long as `theme.font` is a Nerd Font.

## Screenshots

The images in the README are rendered offscreen from the real drawing code with `scripts/screenshots.sh`. Run it after changing your theme to preview it without opening a window: `mofi -screenshot out.png -show drun`.
