#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 5: tables everywhere. The commands live in a table, parsed
-- options come back as a table, and the bookmarks are a table of tables.

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

local function fail(message)
  print("stash: " .. message)
end

-- Parses args[first], args[first+1], ... using a spec that maps each flag
-- to { field, kind }. Kinds: "flag" (no value), "value", "number", "list"
-- (may repeat). Returns an options table: named fields for flags, and the
-- remaining (positional) arguments at 1, 2, 3...
-- On a bad argument it returns nil plus a message.
local function parse_args(args, first, spec)
  local opts = {}
  local i = first
  while i <= #args do
    local a = args[i]
    local option = spec[a]
    if option == nil then
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
          table.insert(opts[field], value)
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
local order = { "add", "list", "show", "rm", "tags", "help", "version" }

commands.add = {
  usage = "add URL [-t TAG]... [-n NOTE]   save a bookmark",
  options = { ["-t"] = { "tags", "list" }, ["-n"] = { "note", "value" } },
  run = function(opts)
    local url = opts[1]
    if url == nil then
      return fail("add: missing URL")
    end
    local tags = opts.tags or {}
    table.sort(tags)
    local entry = { id = next_id, url = url, title = url, tags = tags, note = opts.note or "" }
    next_id = next_id + 1
    entries[#entries + 1] = entry
    print("added " .. entry.id .. ": " .. entry.title)
  end,
}

commands.list = {
  usage = "list [-t TAG] [--limit N]       list bookmarks",
  options = { ["-t"] = { "tag", "value" }, ["--limit"] = { "limit", "number" } },
  run = function(opts)
    local shown = 0
    for _, entry in ipairs(entries) do
      if opts.limit and shown >= opts.limit then
        break
      end
      if opts.tag == nil or has_tag(entry, opts.tag) then
        print(entry.id .. "  " .. entry.title .. "  [" .. table.concat(entry.tags, ",") .. "]")
        shown = shown + 1
      end
    end
  end,
}

commands.show = {
  usage = "show ID                         show one bookmark",
  options = {},
  run = function(opts)
    local id = tonumber(opts[1])
    if id == nil then
      return fail("show: missing or bad ID")
    end
    local entry = find_entry(id)
    if entry == nil then
      return fail("no entry with id " .. id)
    end
    print("id:    " .. entry.id)
    print("title: " .. entry.title)
    print("url:   " .. entry.url)
    print("tags:  " .. table.concat(entry.tags, ", "))
    if entry.note ~= "" then
      print("note:  " .. entry.note)
    end
  end,
}

commands.rm = {
  usage = "rm ID                           delete a bookmark",
  options = {},
  run = function(opts)
    local id = tonumber(opts[1])
    if id == nil then
      return fail("rm: missing or bad ID")
    end
    local entry, index = find_entry(id)
    if entry == nil then
      return fail("no entry with id " .. id)
    end
    table.remove(entries, index)
    print("removed " .. id .. ": " .. entry.title)
  end,
}

commands.tags = {
  usage = "tags                            count bookmarks per tag",
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
      print(row.tag .. " (" .. row.count .. ")")
    end
  end,
}

commands.help = {
  usage = "help                            show this help",
  options = {},
  run = function()
    print("usage: stash <command> [arguments]")
    print()
    print("commands:")
    for _, name in ipairs(order) do
      print("  " .. commands[name].usage)
    end
  end,
}

commands.version = {
  usage = "version                         print the version",
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
    return fail("unknown command '" .. name .. "' (try 'stash help')")
  end
  local opts, err = parse_args(args, 2, command.options)
  if opts == nil then
    return fail(name .. ": " .. err)
  end
  command.run(opts)
end

main(arg)
