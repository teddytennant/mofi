-- Search engines with a prefix: "g rust lifetimes", "gh mofi", "yt lofi".
local engines = {
  { key = "g", name = "Google", url = "https://www.google.com/search?q=%s" },
  { key = "ddg", name = "DuckDuckGo", url = "https://duckduckgo.com/?q=%s" },
  { key = "gh", name = "GitHub", url = "https://github.com/search?q=%s" },
  { key = "yt", name = "YouTube", url = "https://www.youtube.com/results?search_query=%s" },
  { key = "w", name = "Wikipedia", url = "https://en.wikipedia.org/w/index.php?search=%s" },
}

local function urlencode(s)
  return (s:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

mofi.mode("web", {
  prompt = "web",
  dynamic = true,
  items = function(query)
    local key, rest = query:match("^(%S+)%s+(.+)$")
    local out = {}
    for _, e in ipairs(engines) do
      if key == e.key then
        table.insert(out, 1, { text = rest, sub = e.name, icon = "sf:magnifyingglass", url = e.url:format(urlencode(rest)) })
      elseif query ~= "" then
        out[#out + 1] = { text = query, sub = e.name .. " (" .. e.key .. ")", icon = "sf:globe", url = e.url:format(urlencode(query)) }
      end
    end
    return out
  end,
  on_select = function(item)
    if item then mofi.open(item.url) end
  end,
})
