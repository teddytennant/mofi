#!/bin/sh
# The rofi + cliphist pattern, mofi-style. mofi already ships a clipboard
# mode (`mofi -show clipboard`); this shows the same flow as a dmenu pipe.
mofi -lua 'local t = {} for _, c in ipairs(mofi.clipboard.history()) do t[#t+1] = c.kind == "text" and (c.text:gsub("\n", " ")) or "[" .. c.text .. "]" end return table.concat(t, "\n")' |
  mofi -dmenu -p clipboard -format i |
  { read -r i && [ -n "$i" ] && mofi -lua "local h = mofi.clipboard.history() mofi.clipboard.set(h[$i + 1].text)"; }
