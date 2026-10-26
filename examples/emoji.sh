#!/bin/sh
# A rofi-protocol script mode (works unchanged with rofi):
#   modi = { "drun", "emoji:~/.config/mofi/emoji.sh" }
# First call (ROFI_RETV=0) prints rows; picking one calls us again with it.
if [ "${ROFI_RETV:-0}" = 0 ]; then
  printf '\0prompt\037emoji\n'
  printf '%s\n' "😀 grinning" "😂 joy" "🥲 smiling tear" "😎 cool" "🤔 thinking" "🔥 fire" \
    "✨ sparkles" "👍 thumbs up" "🙏 pray" "🚀 rocket" "✅ check" "❤️ heart" "👀 eyes" "💀 skull"
else
  printf '%s' "${1%% *}" | pbcopy
fi
