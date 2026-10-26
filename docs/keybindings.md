# Keybindings

There are two kinds:

- **Global hotkeys** open mofi from anywhere: `mofi.bind(...)`.
- **Launcher keys** act while mofi is open: `mofi.config.keys`.

## Key syntax

Modifiers then a key, joined by `-` (or `+`, rofi-style). Case doesn't matter.

```
alt-space   ctrl-n   shift-return   cmd-shift-]   ctrl-alt-backspace   Control+Shift+Tab
```

| Modifiers | |
|---|---|
| `ctrl`, `control` | <kbd>⌃</kbd> |
| `alt`, `option`, `opt`, `meta`, `mod1` | <kbd>⌥</kbd> |
| `shift` | <kbd>⇧</kbd> |
| `cmd`, `command`, `super`, `mod4`, `win` | <kbd>⌘</kbd> |

| Keys | |
|---|---|
| Letters, digits | `a`…`z`, `0`…`9` |
| Punctuation | `-` `=` `[` `]` `;` `'` `,` `.` `/` `\` `` ` ``, or the names `minus`, `equal`, `bracketleft`, `bracketright`, `semicolon`, `apostrophe`, `comma`, `period`, `slash`, `backslash`, `grave` |
| Named | `return` (`enter`), `kp_enter`, `escape` (`esc`), `tab`, `space`, `backspace`, `delete` (forward delete), `up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown`, `f1`…`f12` |

Keys are matched by position on the ANSI layout, so `alt-]` is the key right of `P` whatever character your layout puts there.

## Global hotkeys

```lua
mofi.bind("alt-space", "drun")                            -- a mode name
mofi.bind("alt-]", "clipboard")
mofi.bind("alt-shift-space", function() mofi.show({ "run", "ssh" }) end)
mofi.bind("alt-p", function()                             -- any Lua
  mofi.menu({ "Do Not Disturb on", "off" }, { prompt = "focus" }, function(item)
    if item then mofi.exec("shortcuts run " .. mofi.quote(item.text)) end
  end)
end)
```

Pressing a hotkey while its own session is open closes it. `mofi.bind` raises an error if the combo can't be registered, which usually means another app already owns it.

Hotkeys use Carbon's `RegisterEventHotKey`, so no Accessibility permission is needed. System shortcuts still win: free <kbd>cmd</kbd>+<kbd>space</kbd> by turning Spotlight's shortcut off in System Settings → Keyboard → Keyboard Shortcuts.

Prefer your WM? Bind `mofi -show drun` there instead (see [getting started](getting-started.md#binding-from-your-window-manager-instead)).

## Launcher keys

Each action takes a list of keys. Setting an action replaces its whole list.

| Action | Default | Does |
|---|---|---|
| `accept` | `return`, `kp_enter` | Pick the selected entry |
| `accept_custom` | `ctrl-return` | Use the typed text and ignore the selection (`run`: run exactly what you typed) |
| `accept_alt` | `shift-return` | Alternate action: `run` in a terminal, `drun` new instance, clipboard flips `paste_on_select`; Lua modes get `ctx.alt = true` |
| `cancel` | `escape`, `ctrl-g`, `ctrl-[` | Close |
| `next` / `prev` | `down`, `ctrl-n`, `ctrl-j`, `tab` / `up`, `ctrl-p`, `ctrl-k`, `shift-tab` | Move the selection |
| `page_next` / `page_prev` | `pagedown` / `pageup` | Move a page |
| `first` / `last` | `home`, `cmd-up` / `end`, `cmd-down` | Jump to the ends |
| `mode_next` / `mode_prev` | `ctrl-tab`, `shift-right`, `cmd-]` / `ctrl-shift-tab`, `shift-left`, `cmd-[` | Switch mode, keeping the query |
| `delete_entry` | `shift-delete`, `shift-backspace` | Remove the entry (clipboard history; Lua modes with `on_delete`) |
| `backspace` | `backspace`, `ctrl-h` | Delete the character before the cursor |
| `delete_char` | `delete`, `ctrl-d` | Delete the character after the cursor |
| `delete_word` | `ctrl-w`, `alt-backspace` | Delete the word before the cursor |
| `clear_line` | `ctrl-u`, `cmd-backspace` | Clear the query |
| `cursor_left` / `cursor_right` | `left`, `ctrl-b` / `right`, `ctrl-f` | Move the cursor |
| `line_start` / `line_end` | `ctrl-a`, `cmd-left` / `ctrl-e`, `cmd-right` | Move the cursor to the ends |
| `paste` | `cmd-v` | Paste into the query |

```lua
mofi.setup({
  keys = {
    next = { "down", "ctrl-j" },   -- ctrl-n no longer moves down
    prev = { "up", "ctrl-k" },
    cancel = { "escape", "alt-space" },
  },
})
```

Mouse: hovering selects (`hover_select`), clicking selects, double-clicking accepts, scrolling moves the selection.

## Custom keys

`keys.custom` maps a key to a Lua function that runs while the launcher is open. It gets a context table; return `true` to close the launcher.

```lua
mofi.setup({
  keys = {
    custom = {
      -- copy the selected entry's text
      ["ctrl-y"] = function(ctx)
        mofi.clipboard.set(ctx.text or ctx.query)
        return true
      end,
      -- quick-look the selected app's folder
      ["ctrl-o"] = function(ctx)
        if ctx.mode == "drun" then mofi.exec("open -R " .. mofi.quote("/Applications/" .. ctx.text .. ".app")) end
        return true
      end,
    },
  },
})
```

| `ctx` field | |
|---|---|
| `key` | The key string you bound |
| `mode` | Current mode name |
| `text` | Selected entry text (nil if nothing matches) |
| `item` | The selected item table (for Lua modes, your original table, extra fields included) |
| `query` | The typed text |

Custom keys are checked before the actions above, so they can override defaults.
