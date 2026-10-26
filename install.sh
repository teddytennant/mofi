#!/bin/bash
# mofi installer:  curl -fsSL https://raw.githubusercontent.com/teddytennant/mofi/main/install.sh | bash
# Env: PREFIX (default ~/.local) — the binary goes to $PREFIX/bin/mofi.
set -euo pipefail

REPO=teddytennant/mofi
PREFIX=${PREFIX:-$HOME/.local}
BIN=$PREFIX/bin
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

[[ $(uname -s) == Darwin ]] || { echo "mofi is macOS only" >&2; exit 1; }

say "downloading the latest release"
if curl -fsSL "https://github.com/$REPO/releases/latest/download/mofi-macos-universal.tar.gz" -o "$tmp/mofi.tgz"; then
  tar -xzf "$tmp/mofi.tgz" -C "$tmp"
else
  say "no release found; building from source"
  command -v swift >/dev/null || { echo "needs the Xcode Command Line Tools: xcode-select --install" >&2; exit 1; }
  git clone --depth 1 "https://github.com/$REPO" "$tmp/src"
  (cd "$tmp/src" && swift build -c release)
  cp "$(cd "$tmp/src" && swift build -c release --show-bin-path)/mofi" "$tmp/mofi"
fi

mkdir -p "$BIN"
"$BIN/mofi" -quit >/dev/null 2>&1 || true
install -m 755 "$tmp/mofi" "$BIN/mofi"
say "installed $BIN/mofi"

conf=${XDG_CONFIG_HOME:-$HOME/.config}/mofi/init.lua
[[ -f $conf ]] || "$BIN/mofi" -init
"$BIN/mofi" -install-agent

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) say "add $BIN to your PATH, e.g.: echo 'export PATH=\"$BIN:\$PATH\"' >> ~/.bashrc" ;;
esac
say "done. press alt-space for apps, alt-] for clipboard history. config: $conf"
