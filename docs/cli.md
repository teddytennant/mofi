# CLI

```
mofi -show MODE [-modi a,b,c] [options]
mofi -dmenu [options] < lines
```

Flags take one dash or two (`-show` and `--show` are the same). rofi-only flags mofi doesn't need (`-theme`, `-show-icons`, `-kb-*`, `-me-*`, `-display-*`, …) are accepted and ignored, so rofi command lines run unchanged. Anything unknown prints a warning and is skipped.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Something was picked (or the command succeeded) |
| 1 | Cancelled (<kbd>esc</kbd>, clicked outside, or the same hotkey pressed again) |
| 2 | Error (unknown mode, bad flag value, daemon couldn't start) |

## Opening modes

| Flag | |
|---|---|
| `-show MODE` | Open `MODE` (`drun`, `run`, `clipboard`, `ssh`, `combi`, a Lua mode, or `name:/path/script`) |
| `-modi a,b,c` | Modes for this session's tabs (default: `config.modi`). `-show` is added if missing. |
| `-combi-modi a,b` | Modes merged by `combi` for this call |

`-show` blocks until you pick or cancel, then exits.

## dmenu

| Flag | |
|---|---|
| `-dmenu` | Read lines from stdin, print the pick |
| `-p`, `-prompt TEXT` | Prompt (default `dmenu`) |
| `-l`, `-lines N` | Rows to show |
| `-mesg TEXT` | Message under the input |
| `-format FMT` | Output format, below |
| `-selected-row N` | Preselect line `N` (0-based) |
| `-no-custom`, `-only-match` | Typed text that matches nothing can't be returned |
| `-sep CHAR` | Input separator (default newline; `\0` for NUL) |
| `-password` | Show typed characters as dots |

`-format` replaces these characters and leaves everything else alone:

| | |
|---|---|
| `s` | Selected text (or the typed text for a custom entry) |
| `i` | 0-based index (`-1` for custom) |
| `d` | 1-based index (`0` for custom) |
| `q` | Selected text, shell-quoted |
| `f` | The typed query |
| `F` | The typed query, shell-quoted |

```sh
printf 'a\nb\nc\n' | mofi -dmenu -format 'i:s'   # → 1:b
```

## Shared options (`-show` and `-dmenu`)

| Flag | |
|---|---|
| `-filter TEXT` | Start with this query |
| `-auto-select` | Accept as soon as one entry is left |
| `-i`, `-case-insensitive` / `-case-sensitive` | Force case handling (default: smart case) |
| `-matching MODE` | `fuzzy`, `normal` or `prefix` |

## Daemon and config

| Command | |
|---|---|
| `mofi -status` | Print daemon status, or exit 2 if it isn't running |
| `mofi -reload` | Reload `init.lua`; prints the error and exits 1 if it fails |
| `mofi -quit` | Stop the daemon |
| `mofi daemon` | Run the daemon in the foreground (for debugging; logs to stderr) |
| `mofi -install-agent` / `-uninstall-agent` | Add/remove the LaunchAgent that starts the daemon at login |
| `mofi -check` | Load the config in a scratch VM and report errors. Doesn't need or touch the daemon. |
| `mofi -init` | Write a starter `~/.config/mofi/init.lua` |
| `mofi -dump-defaults` | Print the built-in Lua runtime and every default |
| `mofi -lua CODE` | Run Lua in the daemon and print what it returns |
| `mofi -e MESSAGE` | Show a message in the launcher |

## Utilities

| Command | |
|---|---|
| `mofi -filter QUERY` (no `-show`/`-dmenu`) | Rank stdin lines against `QUERY` and print the matches, best first, without a UI (like `fzf --filter`) |
| `mofi -screenshot OUT.png -show MODE` | Render the launcher offscreen onto a demo desktop. Used for the docs images. |
| `mofi -version`, `mofi -help` | |

## Examples

```sh
# launcher on a WM key
mofi -show drun

# open the app as soon as the query is unique
mofi -show drun -auto-select

# window-less fuzzy ranking in scripts
ls ~/projects | mofi -filter mofi

# pick a file and open it
f=$(fd . ~/notes | mofi -dmenu -p notes) && open "$f"

# rofi script mode without touching the config
mofi -show emoji -modi 'emoji:~/.config/mofi/emoji.sh'

# poke the running daemon
mofi -lua 'mofi.clipboard.history()[1].text'
```
