# mofi docs

| Page | What's in it |
|---|---|
| [Getting started](getting-started.md) | Installing, the daemon, first hotkeys, permissions, AeroSpace/yabai, uninstalling |
| [Configuration](configuration.md) | `init.lua`, `mofi.setup`, every option and its default, reloading |
| [Theming](theming.md) | Fonts, sizes, layout, every color, example themes |
| [Keybindings](keybindings.md) | Key syntax, launcher actions, custom keys, global hotkeys |
| [Modes](modes.md) | `drun`, `run`, `clipboard`, `ssh`, `combi`, `dmenu`, script modes |
| [Lua API](lua-api.md) | The full `mofi.*` reference, custom modes, menus |
| [CLI](cli.md) | Every flag, exit codes, examples |
| [Coming from rofi](migrating-from-rofi.md) | rofi option/flag mapping, porting a `.rasi` theme |

Quick reference:

```sh
mofi -show drun                         # app launcher
mofi -show clipboard                    # clipboard history
printf 'a\nb\n' | mofi -dmenu -p pick   # dmenu
mofi -check                             # validate ~/.config/mofi/init.lua
mofi -dump-defaults                     # every default, as Lua
```
