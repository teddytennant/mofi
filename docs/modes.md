# Modes

A mode is a list of entries plus what happens when you pick one. Open one with `mofi -show <mode>` or `mofi.show("<mode>")`. In a session opened with `-show`, every mode in `modi` is a tab; <kbd>ctrl</kbd>+<kbd>tab</kbd> cycles them.

| Mode | Lists | <kbd>enter</kbd> | <kbd>shift</kbd>+<kbd>enter</kbd> |
|---|---|---|---|
| `drun` | Installed apps | Launch / focus | Open a new window |
| `run` | Executables on `PATH` | Run (typed text works too) | Run in a terminal |
| `clipboard` | Clipboard history | Copy back to the clipboard | Copy + paste (or the reverse of `paste_on_select`) |
| `ssh` | Hosts from `~/.ssh/config` and `known_hosts` | `ssh host` in a terminal | — |
| `combi` | `combi_modi` merged into one list | Whatever the source mode does | Same |
| `dmenu` | Lines from stdin | Print the selection | — |
| Lua modes | Whatever you return | Your `on_select` | Your `on_select` with `ctx.alt` |
| Script modes | Output of a rofi-protocol script | The script decides | — |

## drun

Apps from `drun.paths`, with their Finder icons. Entries you launch often move to the top: with an empty query the list is ordered by launch count, and launch count breaks ties between equal matches.

```sh
mofi -show drun
mofi -show drun -auto-select   # launches as soon as one app is left
```

## run

Every executable on your `PATH` (taken from your login shell, plus `path` from the config). Pick one, or type a full command line and press <kbd>enter</kbd> (or <kbd>ctrl</kbd>+<kbd>enter</kbd> to ignore the selection). Commands run through `/bin/sh -c` in your home directory.

## clipboard

Text and images you copy, newest first, with how long ago. Multi-line text shows on one line with `⏎`. Picking an entry puts it back on the clipboard and moves it to the top. <kbd>shift</kbd>+<kbd>delete</kbd> removes it from history.

```sh
mofi -show clipboard
mofi -lua 'mofi.clipboard.clear()'   # wipe history
```

See [configuration](configuration.md#clipboard) for limits, ignored apps and `paste_on_select`.

## ssh

`Host` entries from `~/.ssh/config` (following `Include`, skipping wildcards) and hosts from `~/.ssh/known_hosts` (skipping hashed ones). Picking a host opens `ssh <host>` with your `terminal`. Typing a host that isn't listed works too.

This mode is written in Lua (`mofi -dump-defaults` shows it), so replacing it is a good first custom mode:

```lua
mofi.mode("ssh", {
  items = { "nixos-server", "homelab", { text = "pi", sub = "192.168.1.20" } },
  on_select = function(item, ctx)
    mofi.terminal("ssh " .. mofi.quote(item and item.text or ctx.query))
  end,
})
```

## combi

```lua
mofi.setup({ combi_modi = { "drun", "run", "ssh" } })
```

```sh
mofi -show combi
mofi -show combi -combi-modi drun,ssh
```

Each entry shows its source mode on the right.

## dmenu

Reads lines from stdin, prints the pick to stdout. Exit code 0 means a pick, 1 means cancelled. This is the rofi/dmenu contract, so existing scripts work:

```sh
choice=$(printf 'lock\nsleep\nrestart\n' | mofi -dmenu -p power) || exit
git checkout "$(git branch --format='%(refname:short)' | mofi -dmenu -p branch)"
ls ~/wallpapers | mofi -dmenu -p wallpaper -l 15
```

Typed text that matches nothing is returned as-is (disable with `-no-custom`). Common flags: `-p` prompt, `-l` rows, `-mesg` message, `-format` output, `-selected-row`, `-filter` initial query, `-auto-select`, `-password`. See [CLI](cli.md#dmenu).

Rows can carry rofi row options after a NUL byte:

```sh
printf 'Safari\0icon\x1fapp:Safari\nNotes\0icon\x1fsf:note.text\nheader\0nonselectable\x1ftrue\n' | mofi -dmenu
```

Supported: `icon`, `nonselectable`, `urgent`, `active`, plus `info`/`meta`, which are accepted and ignored.

## Lua modes

The most flexible kind. They're covered in the [Lua API](lua-api.md#custom-modes). The short version:

```lua
mofi.mode("projects", {
  items = function()
    local out = {}
    for dir in io.popen("ls -d ~/projects/*/"):lines() do
      out[#out + 1] = { text = dir:match("([^/]+)/$"), path = dir, icon = dir }
    end
    return out
  end,
  on_select = function(item) if item then mofi.exec("code " .. mofi.quote(item.path)) end end,
})
```

## rofi script modes

Any script written for rofi's [script mode](https://davatorium.github.io/rofi/current/rofi-script.5/) works:

```lua
mofi.setup({ modi = { "drun", "emoji:~/.config/mofi/emoji.sh" } })
-- or
mofi.script_mode("emoji", "~/.config/mofi/emoji.sh")
```

```sh
mofi -show emoji -modi 'drun,emoji:~/.config/mofi/emoji.sh'
```

The protocol: mofi runs the script with `ROFI_RETV=0` and lists its output lines. When you pick an entry, it runs the script again with the entry as `$1` and `ROFI_RETV=1` (`2` for custom text, with `ROFI_INFO` set from the row's `info`). If that prints lines, they become the new list; if it prints nothing, the launcher closes. Mode option lines `\0prompt\x1f…`, `\0message\x1f…` and `\0no-custom\x1ftrue` are honored.

See `examples/emoji.sh`.
