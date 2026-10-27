-- autotag: tags new bookmarks by what they are about.
--
-- The rules are data. WORDS: a Lua pattern, matched against the
-- lowercased title and page text, and the tag it earns (%f[%w] and
-- %f[%W] are frontiers: the start and end of a word). HOSTS: tags for
-- the sites the URLs point to.

local WORDS = {
  { "%f[%w]luajit%f[%W]", "jit" },
  { "%f[%w]lua%f[%W]", "lua" },
  { "%f[%w]sqlite%f[%W]", "db" },
  { "%f[%w]sql%f[%W]", "db" },
}

local HOSTS = {
  ["github.com"] = "code",
  ["gitlab.com"] = "code",
  ["www.lua.org"] = "lua",
}

stash.on("add", function(entry)
  local text = ((entry.title or "") .. " " .. (entry.text or "")):lower()
  for _, rule in ipairs(WORDS) do
    local pattern, tag = rule[1], rule[2]
    if text:find(pattern) then
      entry.tags[#entry.tags + 1] = tag      -- stash drops duplicates
    end
  end
  local host = entry.url:match("^%a[%w+.-]*://([^/:]+)")
  if host and HOSTS[host:lower()] then
    entry.tags[#entry.tags + 1] = HOSTS[host:lower()]
  end
end)
