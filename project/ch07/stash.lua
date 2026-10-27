#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 7: metatables. Entries become objects of an Entry class, the
-- bookmarks live in a MemoryStore object, and strict mode catches typos
-- in global names.

-- Strict mode: reading or assigning an undeclared global is an error.
-- Without this, a typo such as `entires` silently reads nil.
setmetatable(_G, {
  __newindex = function(_, name)
    error("assignment to undeclared global '" .. tostring(name) .. "'", 2)
  end,
  __index = function(_, name)
    error("undeclared global '" .. tostring(name) .. "'", 2)
  end,
})

local VERSION = "0.1.0"

---------------------------------------------------------------------------
-- String helpers
---------------------------------------------------------------------------

-- Splits "a, b,,c" into { "a", "b", "c" }: pieces are trimmed, empty ones dropped.
local function split(s, sep)
  local parts = {}
  for piece in s:gmatch("[^" .. sep .. "]+") do
    piece = piece:match("^%s*(.-)%s*$")      -- trim: `.-` is the lazy `.*`
    if piece ~= "" then
      parts[#parts + 1] = piece
    end
  end
  return parts
end

-- Shortens s to at most `width` characters, marking the cut with "...".
local function truncate(s, width)
  if #s <= width then
    return s
  end
  return s:sub(1, width - 3) .. "..."
end

-- "https://www.lua.org/pil/?x=1" -> "www.lua.org/pil"
local function title_from_url(url)
  local rest = url:match("^%a[%w+.-]*://([^?#]*)") or url
  return (rest:gsub("/+$", ""))
end

---------------------------------------------------------------------------
-- Entry: one bookmark. The class table doubles as the metatable of its
-- instances; __index = Entry makes instances find their methods there.
---------------------------------------------------------------------------

local Entry = {}
Entry.__index = Entry

function Entry.new(fields)
  local self = setmetatable({}, Entry)
  self.id = fields.id                        -- nil until a store assigns one
  self.url = fields.url
  self.title = fields.title or title_from_url(fields.url)
  self.note = fields.note or ""
  self.tags = {}
  for i, tag in ipairs(fields.tags or {}) do
    self.tags[i] = tag                       -- copy: never share the caller's table
  end
  table.sort(self.tags)
  return self
end

function Entry:has_tag(tag)
  for _, t in ipairs(self.tags) do
    if t == tag then
      return true
    end
  end
  return false
end

-- Case-insensitive substring search over the text fields.
function Entry:matches(term)
  term = term:lower()
  for _, field in ipairs({ self.title, self.url, self.note, self:tag_string(" ") }) do
    if field:lower():find(term, 1, true) then
      return true
    end
  end
  return false
end

function Entry:tag_string(sep)
  return table.concat(self.tags, sep or ",")
end

-- tostring(entry) and print(entry) use this.
function Entry.__tostring(self)
  return ("#%d %s"):format(self.id or 0, self.title)
end

-- `a < b` on entries compares ids, so table.sort(list) needs no comparator.
function Entry.__lt(a, b)
  return a.id < b.id
end

---------------------------------------------------------------------------
-- MemoryStore: keeps entries in a table. Every store we write implements
-- the same methods, so the commands do not care where entries live:
--   add(entry) -> entry      get(id) -> entry|nil     remove(id) -> entry|nil
--   list{tag=, limit=} -> array     search(term) -> array     tags() -> array
---------------------------------------------------------------------------

local MemoryStore = {}
MemoryStore.__index = MemoryStore

function MemoryStore.new(initial)
  local self = setmetatable({ by_id = {}, next_id = 1 }, MemoryStore)
  for _, fields in ipairs(initial or {}) do
    self:add(Entry.new(fields))
  end
  return self
end

function MemoryStore:add(entry)
  entry.id = self.next_id
  self.next_id = self.next_id + 1
  self.by_id[entry.id] = entry             -- keyed by id: get() is one lookup
  return entry
end

function MemoryStore:get(id)
  return self.by_id[id]
end

function MemoryStore:remove(id)
  local entry = self.by_id[id]
  self.by_id[id] = nil
  return entry
end

-- All entries sorted by id. (pairs() visits keys in no particular order.)
function MemoryStore:sorted()
  local list = {}
  for _, entry in pairs(self.by_id) do
    list[#list + 1] = entry
  end
  table.sort(list)                           -- uses Entry.__lt
  return list
end

function MemoryStore:list(filter)
  local result = {}
  for _, entry in ipairs(self:sorted()) do
    if filter.limit and #result >= filter.limit then
      break
    end
    if filter.tag == nil or entry:has_tag(filter.tag) then
      result[#result + 1] = entry
    end
  end
  return result
end

function MemoryStore:search(term)
  local result = {}
  for _, entry in ipairs(self:sorted()) do
    if entry:matches(term) then
      result[#result + 1] = entry
    end
  end
  return result
end

-- Returns { {tag=, count=}, ... }: most used first, then by name.
function MemoryStore:tags()
  local counts = {}
  for _, entry in pairs(self.by_id) do
    for _, tag in ipairs(entry.tags) do
      counts[tag] = (counts[tag] or 0) + 1
    end
  end
  local rows = {}
  for tag, count in pairs(counts) do
    rows[#rows + 1] = { tag = tag, count = count }
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.tag < b.tag
  end)
  return rows
end

-- Nothing is saved yet (files arrive in Chapter 12), so every run starts
-- from these sample entries.
local store = MemoryStore.new({
  { url = "https://www.lua.org/", title = "The Programming Language Lua",
    tags = { "lua", "lang" }, note = "official site" },
  { url = "https://luajit.org/", title = "LuaJIT", tags = { "lua", "jit" } },
  { url = "https://sqlite.org/fts5.html", title = "SQLite FTS5 Extension",
    tags = { "db", "search" }, note = "full-text search" },
})

---------------------------------------------------------------------------
-- Argument parsing
---------------------------------------------------------------------------

local function fail(fmt, ...)
  print("stash: " .. fmt:format(...))
end

-- Parses args[first], args[first+1], ... using a spec that maps each flag
-- to { field, kind }. Kinds: "flag" (no value), "value", "number", "list"
-- (may repeat, values may be comma-separated). Returns an options table:
-- named fields for flags, and the remaining (positional) arguments at 1, 2, 3...
-- On a bad argument it returns nil plus a message.
local function parse_args(args, first, spec)
  local opts = {}
  local i = first
  while i <= #args do
    local a = args[i]
    local option = spec[a]
    if option == nil then
      if a:sub(1, 1) == "-" and a ~= "-" then
        return nil, "unknown option " .. a
      end
      opts[#opts + 1] = a
    else
      local field, kind = option[1], option[2]
      if kind == "flag" then
        opts[field] = true
      else
        i = i + 1
        local value = args[i]
        if value == nil then
          return nil, a .. " needs a value"
        end
        if kind == "number" then
          value = tonumber(value)
          if value == nil then
            return nil, a .. " needs a number"
          end
        end
        if kind == "list" then
          opts[field] = opts[field] or {}
          for _, item in ipairs(split(value, ",")) do
            table.insert(opts[field], item)
          end
        else
          opts[field] = value
        end
      end
    end
    i = i + 1
  end
  return opts
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

local commands = {}
local order = { "add", "list", "search", "show", "rm", "tags", "help", "version" }

local function format_row(entry)
  return ("%3d  %-36s  %s"):format(entry.id, truncate(entry.title, 36), entry:tag_string())
end

commands.add = {
  usage = "add URL [-t TAGS] [-n NOTE]",
  help = "save a bookmark",
  options = { ["-t"] = { "tags", "list" }, ["-n"] = { "note", "value" } },
  run = function(opts)
    local url = opts[1]
    if url == nil then
      return fail("add: missing URL")
    end
    if not url:find("^%a[%w+.-]*://") then
      return fail("add: '%s' does not look like a URL", url)
    end
    local tags = {}
    for i, tag in ipairs(opts.tags or {}) do
      tag = tag:lower()
      if not tag:find("^[%w_-]+$") then
        return fail("add: bad tag '%s' (use letters, digits, - and _)", tag)
      end
      tags[i] = tag
    end
    local entry = store:add(Entry.new({ url = url, tags = tags, note = opts.note }))
    print("added " .. tostring(entry))
  end,
}

commands.list = {
  usage = "list [-t TAG] [--limit N]",
  help = "list bookmarks",
  options = { ["-t"] = { "tag", "value" }, ["--limit"] = { "limit", "number" } },
  run = function(opts)
    for _, entry in ipairs(store:list({ tag = opts.tag, limit = opts.limit })) do
      print(format_row(entry))
    end
  end,
}

commands.search = {
  usage = "search TERM",
  help = "find bookmarks containing TERM",
  options = {},
  run = function(opts)
    local term = opts[1]
    if term == nil then
      return fail("search: missing TERM")
    end
    local found = store:search(term)
    for _, entry in ipairs(found) do
      print(format_row(entry))
    end
    if #found == 0 then
      fail("nothing matches '%s'", term)
    end
  end,
}

commands.show = {
  usage = "show ID",
  help = "show one bookmark",
  options = {},
  run = function(opts)
    local id = tonumber(opts[1])
    if id == nil then
      return fail("show: missing or bad ID")
    end
    local entry = store:get(id)
    if entry == nil then
      return fail("no entry with id %d", id)
    end
    print(("%-6s %d"):format("id:", entry.id))
    print(("%-6s %s"):format("title:", entry.title))
    print(("%-6s %s"):format("url:", entry.url))
    print(("%-6s %s"):format("tags:", entry:tag_string(", ")))
    if entry.note ~= "" then
      print(("%-6s %s"):format("note:", entry.note))
    end
  end,
}

commands.rm = {
  usage = "rm ID",
  help = "delete a bookmark",
  options = {},
  run = function(opts)
    local id = tonumber(opts[1])
    if id == nil then
      return fail("rm: missing or bad ID")
    end
    local entry = store:remove(id)
    if entry == nil then
      return fail("no entry with id %d", id)
    end
    print("removed " .. tostring(entry))
  end,
}

commands.tags = {
  usage = "tags",
  help = "count bookmarks per tag",
  options = {},
  run = function()
    for _, row in ipairs(store:tags()) do
      print(("%4d  %s"):format(row.count, row.tag))
    end
  end,
}

commands.help = {
  usage = "help",
  help = "show this help",
  options = {},
  run = function()
    print("usage: stash <command> [arguments]")
    print()
    print("commands:")
    for _, name in ipairs(order) do
      local command = commands[name]
      print(("  %-28s  %s"):format(command.usage, command.help))
    end
  end,
}

commands.version = {
  usage = "version",
  help = "print the version",
  options = {},
  run = function()
    print("stash " .. VERSION)
  end,
}

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------

local function main(args)
  local name = args[1]
  if name == nil or name == "-h" or name == "--help" then
    name = "help"
  elseif name == "--version" then
    name = "version"
  end

  local command = commands[name]
  if command == nil then
    return fail("unknown command '%s' (try 'stash help')", name)
  end
  local opts, err = parse_args(args, 2, command.options)
  if opts == nil then
    return fail("%s: %s", name, err)
  end
  command.run(opts)
end

main(arg)
