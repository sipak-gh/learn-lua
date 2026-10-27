-- A small DSL: rules for tagging bookmarks, written as Lua.
-- `tag "lua" { ... }` is two calls without parentheses:
-- tag("lua") returns a function, which gets the table.

local rules_text = [[
tag "lua" {
  words = { "lua", "luajit" },
  hosts = { "www.lua.org" },
}
tag "db" { words = { "sqlite", "sql" } }

-- Rules are code, so they can loop, call functions, and so on.
for _, host in ipairs({ "go.dev", "pkg.go.dev" }) do
  tag "code" { hosts = { host } }
end
]]

-- The DSL's vocabulary: the only globals the rules file sees.
local function load_rules(text)
  local rules = {}
  local env = { ipairs = ipairs }
  function env.tag(name)
    return function(spec)
      rules[#rules + 1] = { tag = name, words = spec.words or {}, hosts = spec.hosts or {} }
    end
  end
  local chunk = assert(load(text, "=rules", "t"))
  setfenv(chunk, env)
  chunk()
  return rules
end

local function tags_for(rules, url, title)
  local host = url:match("^%a+://([^/]+)")
  local text = title:lower()
  local tags = {}
  for _, rule in ipairs(rules) do
    for _, word in ipairs(rule.words) do
      if text:find("%f[%w]" .. word .. "%f[%W]") then tags[rule.tag] = true end
    end
    for _, h in ipairs(rule.hosts) do
      if h == host then tags[rule.tag] = true end
    end
  end
  local list = {}
  for tag in pairs(tags) do list[#list + 1] = tag end
  table.sort(list)
  return table.concat(list, ",")
end

local rules = load_rules(rules_text)
print(#rules .. " rules")
print(tags_for(rules, "https://www.lua.org/manual/", "Lua 5.1 Reference Manual"))
print(tags_for(rules, "https://sqlite.org/fts5.html", "SQLite FTS5 Extension"))
print(tags_for(rules, "https://go.dev/doc/", "Documentation"))
print(tags_for(rules, "https://example.com/", "Nothing here"))
