#!/bin/bash
# Regenerate docs/screenshots/*.png. Everything renders offscreen with demo
# data in a temp dir: no window opens and your own config/history is untouched.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release >/dev/null
BIN=$PWD/.build/release/mofi
OUT=$PWD/docs/screenshots
mkdir -p "$OUT"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_CONFIG_HOME=$tmp/config XDG_DATA_HOME=$tmp/data
mkdir -p "$XDG_CONFIG_HOME/mofi" "$XDG_DATA_HOME/mofi"

cat > "$XDG_CONFIG_HOME/mofi/init.lua" <<'LUA'
mofi.mode("ssh", {
  items = {
    { text = "nixos-server", icon = "sf:server.rack" },
    { text = "homelab", icon = "sf:server.rack" },
    { text = "pi.local", icon = "sf:cpu" },
    { text = "github.com", icon = "sf:network" },
    { text = "vps-fra1", icon = "sf:globe.europe.africa" },
  },
})
LUA

now=$(date +%s)
python3 - "$XDG_DATA_HOME/mofi" "$now" <<'PY'
import json, sys
d, now = sys.argv[1], int(sys.argv[2])
clips = [
  ("git push -u origin feat/lua-modes", 20),
  ("https://github.com/teddytennant/mofi", 95),
  ("mofi.bind(\"alt-space\", \"drun\")", 260),
  ("ssh nixos-server 'sudo nixos-rebuild switch --flake .#server'", 900),
  ("#33ccff", 1800),
  ("brew install --cask nikitabobko/tap/aerospace", 4000),
  ("SELECT name, launches FROM apps ORDER BY launches DESC LIMIT 10;", 7200),
  ("defaults write -g ApplePressAndHoldEnabled -bool false", 20000),
  ("The quick brown fox jumps over the lazy dog", 90000),
  ("~/.config/mofi/init.lua", 200000),
]
json.dump([{"kind": "text", "text": t, "time": now - a} for t, a in clips], open(d + "/clipboard.json", "w"))
hist = {"drun\x1f" + n: c for n, c in [("Alacritty", 90), ("Brave Browser", 80), ("Obsidian", 60), ("Zed", 50), ("Cursor", 40),
        ("Visual Studio Code", 30), ("System Settings", 20), ("Finder", 15), ("Activity Monitor", 10), ("Music", 5)]}
json.dump(hist, open(d + "/history.json", "w"))
PY

"$BIN" -screenshot "$OUT/drun.png" -show drun
"$BIN" -screenshot "$OUT/fuzzy.png" -show drun -filter "st"
"$BIN" -screenshot "$OUT/clipboard.png" -show clipboard -modi drun,run,clipboard,ssh
"$BIN" -screenshot "$OUT/ssh.png" -show ssh -modi drun,run,clipboard,ssh
printf '󰌾  lock\n󰤄  sleep\n󰜉  restart\n󰐥  shutdown\n󰍃  log out\n' |
  "$BIN" -screenshot "$OUT/dmenu.png" -dmenu -p power -mesg "printf … | mofi -dmenu -p power" -l 5
