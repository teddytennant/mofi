# Getting started

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/teddytennant/mofi/main/install.sh | bash
```

The installer:

1. downloads the latest universal binary (Apple Silicon + Intel) to `~/.local/bin/mofi`, or builds from source if no release is available (that path needs `xcode-select --install`),
2. writes a starter config to `~/.config/mofi/init.lua` if you don't have one yet,
3. installs a LaunchAgent so the daemon starts at login, and starts it.

Set `PREFIX` to install somewhere else, e.g. `curl … | PREFIX=/opt/homebrew bash` puts it in `/opt/homebrew/bin`.

If `~/.local/bin` isn't on your `PATH`, add it:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc   # or ~/.zshrc
```

## How it runs

mofi is two things in one binary:

- **The daemon** (`mofi daemon`) stays in the background with no Dock icon. It holds the window, the Lua VM, the app index and the clipboard watcher, so showing the launcher costs one redraw.
- **The client** (`mofi -show drun`, `mofi -dmenu`, …) sends one request over a Unix socket and prints the answer. If no daemon is running, the client starts one.

```sh
mofi -status     # is it running?
mofi -reload     # reload init.lua (also happens automatically when you save it)
mofi -quit       # stop it (the LaunchAgent restarts it at next login)
```

Logs go to `~/Library/Logs/mofi.log`.

## First hotkeys

The starter config binds:

| Key | Opens |
|---|---|
| <kbd>alt</kbd>+<kbd>space</kbd> | apps (`drun`) |
| <kbd>alt</kbd>+<kbd>]</kbd> | clipboard history |
| <kbd>alt</kbd>+<kbd>shift</kbd>+<kbd>space</kbd> | run + ssh |
| <kbd>alt</kbd>+<kbd>shift</kbd>+<kbd>escape</kbd> | power menu |

Change them in `~/.config/mofi/init.lua`:

```lua
mofi.bind("cmd-space", "drun")
```

To use <kbd>cmd</kbd>+<kbd>space</kbd>, first turn off Spotlight's shortcut in **System Settings → Keyboard → Keyboard Shortcuts → Spotlight**. Otherwise Spotlight keeps it.

Inside the launcher: type to filter. <kbd>enter</kbd> picks, <kbd>esc</kbd> closes, <kbd>ctrl</kbd>+<kbd>tab</kbd> switches modes, <kbd>shift</kbd>+<kbd>enter</kbd> is the alternate action (run in terminal, new app instance). See [keybindings](keybindings.md).

## Binding from your window manager instead

Since the client returns as soon as you pick something, you can bind keys in your WM like you did on Linux.

**AeroSpace** (`~/.aerospace.toml`):

```toml
[mode.main.binding]
alt-space = 'exec-and-forget mofi -show drun'
alt-rightSquareBracket = 'exec-and-forget mofi -show clipboard'
```

**skhd** (yabai):

```
alt - space : mofi -show drun
```

Pressing the same binding again while mofi is open closes it.

The launcher is a floating panel that never activates the mofi process, so tiling WMs leave it alone and focus goes back to the previous app when it closes.

## Permissions

None are needed for normal use. Hotkeys use the Carbon hotkey API, and clipboard history reads the pasteboard.

The one exception: `clipboard.paste_on_select = true` makes mofi press <kbd>cmd</kbd>+<kbd>v</kbd> for you after you pick an entry. That needs **Accessibility** (System Settings → Privacy & Security → Accessibility → add `~/.local/bin/mofi`). macOS prompts the first time.

## Uninstall

```sh
mofi -uninstall-agent
rm ~/.local/bin/mofi
rm -rf ~/.config/mofi ~/.local/share/mofi ~/Library/Caches/mofi ~/Library/Logs/mofi.log
```

## Troubleshooting

- **Nothing happens on the hotkey.** Run `mofi -status`. If the daemon isn't running, check `~/Library/Logs/mofi.log`. If it is running, another app may own that key combo: try another key, or bind it from your WM.
- **Config error banner.** The launcher shows the Lua error in red. Run `mofi -check` for the full traceback.
- **Apps missing.** mofi scans `/Applications`, `/System/Applications`, `~/Applications` and their `Utilities` folders, two levels deep. Add more under `drun.paths`.
- **`run` can't find a command.** mofi copies `PATH` from your login shell (`$SHELL -l`). Add directories with `path = { "~/bin" }`.
