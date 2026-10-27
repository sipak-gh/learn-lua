#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 6: strings. Tags are split on commas, titles come from URLs,
-- `search` matches text, and output is lined up in columns.

local VERSION = "0.1.0"

---------------------------------------------------------------------------
-- The store: an array of entries, each entry a record-like table.
-- Nothing is saved yet (files arrive in Chapter 12), so every run starts
-- from these sample entries.
---------------------------------------------------------------------------

local entries = {
  { id = 1, url = "https://www.lua.org/", title = "The Programming Language Lua",
    tags = { "lang", "lua" }, note = "official site" },
  { id = 2, url = "https://luajit.org/", title = "LuaJIT",
    tags = { "jit", "lua" }, note = "" },
  { id = 3, url = "https://sqlite.org/fts5.html", title = "SQLite FTS5 Extension",
    tags = { "db", "search" }, note = "full-text search" },
}
local next_id = #entries + 1

-- Returns the entry with this id and its position in `entries`, or nil.
local function find_entry(id)
  for i, entry in ipairs(entries) do
    if entry.id == id then
      return entry, i
    end
  end
  return nil
end

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
-- (Counts bytes: fine for ASCII, see the UTF-8 notes in this chapter.)
local function truncate(s, width)
  if #s <= width then
    return s
  end
  return s:sub(1, width - 3) .. "..."
end

-- "https://www.lua.org/pil/?x=1" -> "www.lua.org/pil": the best title we
-- can make without downloading the page.
local function title_from_url(url)
  local rest = url:match("^%a[%w+.-]*://([^?#]*)") or url
  return (rest:gsub("/+$", ""))              -- parentheses: keep only the string
end

local function has_tag(entry, tag)
  for _, t in ipairs(entry.tags) do
    if t == tag then
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Argument parsing
---------------------------------------------------------------------------

-- string.format works like C's printf.
local function fail(fmt, ...)
  print("stash: " .. fmt:format(...))
end

-- Parses args[first], args[first+1], ... using a spec that maps each flag
-- to { field, kind }. Kinds: "flag" (no value), "value", "number", "list"
-- (may repeat, values may be comma-separated). Returns an options table: named fields for flags, and the
-- remaining (positional) arguments at 1, 2, 3...
-- On a bad argument it returns nil plus a message.
local function parse_args(args, first, spec)
  local opts = {}
  local i = first
  while i <= #args do
    local a = args[i]
    local option = spec[a]
    if option == nil then
      -- "-" alone usually means stdin, so it counts as a positional argument.
      if a:sub(1, 1) == "-" and a ~= "-" then
        return nil, "unknown option " .. a
      end
      opts[#opts + 1] = a                    -- positional argument
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
-- Commands: a dispatch table from name to a record describing the command.
---------------------------------------------------------------------------

local commands = {}

-- Help lists the commands in this order (pairs() would give no fixed order).
local order = { "add", "list", "search", "show", "rm", "tags", "help", "version" }

commands.add = {
  usage = "add URL [-t TAGS] [-n NOTE]",
  help = "save a bookmark",
  options = { ["-t"] = { "tags", "list" }, ["-n"] = { "note", "value" } },
  run = function(opts)
    local url = opts[1]
    if url == nil then
      return fail("add: missing URL")
    end
    -- A scheme like "https:" or "file:", then "//".
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
    table.sort(tags)
    local entry = { id = next_id, url = url, title = title_from_url(url), tags = tags,
                    note = opts.note or "" }
    next_id = next_id + 1
    entries[#entries + 1] = entry
    print(("added %d: %s"):format(entry.id, entry.title))
  end,
}

-- One line per entry: id right-aligned, title padded to a fixed width.
local function format_row(entry)
  return ("%3d  %-36s  %s"):format(entry.id, truncate(entry.title, 36),
                                   table.concat(entry.tags, ","))
end

commands.list = {
  usage = "list [-t TAG] [--limit N]",
  help = "list bookmarks",
  options = { ["-t"] = { "tag", "value" }, ["--limit"] = { "limit", "number" } },
  run = function(opts)
    local shown = 0
    for _, entry in ipairs(entries) do
      if opts.limit and shown >= opts.limit then
        break
      end
      if opts.tag == nil or has_tag(entry, opts.tag) then
        print(format_row(entry))
        shown = shown + 1
      end
    end
  end,
}

-- Case-insensitive substring search. The `true` argument to find()
-- turns off patterns, so "c++" or "50%" are searched literally.
local function matches(entry, term)
  term = term:lower()
  local fields = { entry.title, entry.url, entry.note, table.concat(entry.tags, " ") }
  for _, field in ipairs(fields) do
    if field:lower():find(term, 1, true) then
      return true
    end
  end
  return false
end

commands.search = {
  usage = "search TERM",
  help = "find bookmarks containing TERM",
  options = {},
  run = function(opts)
    local term = opts[1]
    if term == nil then
      return fail("search: missing TERM")
    end
    local found = 0
    for _, entry in ipairs(entries) do
      if matches(entry, term) then
        print(format_row(entry))
        found = found + 1
      end
    end
    if found == 0 then
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
    local entry = find_entry(id)
    if entry == nil then
      return fail("no entry with id %d", id)
    end
    print(("%-6s %d"):format("id:", entry.id))
    print(("%-6s %s"):format("title:", entry.title))
    print(("%-6s %s"):format("url:", entry.url))
    print(("%-6s %s"):format("tags:", table.concat(entry.tags, ", ")))
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
    local entry, index = find_entry(id)
    if entry == nil then
      return fail("no entry with id %d", id)
    end
    table.remove(entries, index)
    print(("removed %d: %s"):format(id, entry.title))
  end,
}

commands.tags = {
  usage = "tags",
  help = "count bookmarks per tag",
  options = {},
  run = function()
    -- A dictionary from tag to count...
    local counts = {}
    for _, entry in ipairs(entries) do
      for _, tag in ipairs(entry.tags) do
        counts[tag] = (counts[tag] or 0) + 1
      end
    end
    -- ...turned into an array so it can be sorted: most used first, then by name.
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
    for _, row in ipairs(rows) do
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
