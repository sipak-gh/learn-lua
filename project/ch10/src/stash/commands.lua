-- The commands. Each one gets a context table `ctx` (the store, the
-- settings, and an `out` function for output) plus the parsed options.
-- Problems are raised with the helpers in stash.errors; main turns them
-- into messages and exit codes.

local Entry = require("stash.entry")
local errors = require("stash.errors")
local util = require("stash.util")

local VERSION = "0.1.0"

local commands = {}                          -- name -> command record
local order = {}                             -- names in the order help shows them

-- Parses the ID argument of show and rm.
local function need_id(opts)
  local id = tonumber(opts[1])
  if id == nil then
    errors.usage(opts[1] and "bad ID '%s'" or "missing ID", opts[1])
  end
  return id
end

-- A tiny DSL: `command "add" { ... }` calls command("add"), which returns
-- a function that receives the table. Both calls need no parentheses.
local function command(name)
  return function(def)
    def.name = name
    def.options = def.options or {}
    commands[name] = def
    order[#order + 1] = name
  end
end

local function format_row(entry)
  return ("%3d  %-36s  %s"):format(entry.id, util.truncate(entry.title, 36), entry:tag_string())
end

command "add" {
  usage = "add URL [-t TAGS] [-n NOTE]",
  help = "save a bookmark",
  options = { ["-t"] = { "tags", "list" }, ["-n"] = { "note", "value" } },
  run = function(ctx, opts)
    local url = opts[1]
    if url == nil then
      errors.usage("missing URL")
    end
    if not url:find("^%a[%w+.-]*://") then
      errors.usage("'%s' does not look like a URL", url)
    end
    local tags = {}
    for i, tag in ipairs(opts.tags or {}) do
      tag = tag:lower()
      if not tag:find("^[%w_-]+$") then
        errors.usage("bad tag '%s' (use letters, digits, - and _)", tag)
      end
      tags[i] = tag
    end
    local entry = ctx.store:add(Entry.new({ url = url, tags = tags, note = opts.note }))
    ctx.out("added " .. tostring(entry))
  end,
}

command "list" {
  usage = "list [-t TAG] [--limit N]",
  help = "list bookmarks",
  options = { ["-t"] = { "tag", "value" }, ["--limit"] = { "limit", "number" } },
  run = function(ctx, opts)
    local limit = opts.limit or ctx.config.list_limit
    for _, entry in ipairs(ctx.store:list({ tag = opts.tag, limit = limit })) do
      ctx.out(format_row(entry))
    end
  end,
}

command "search" {
  usage = "search TERM",
  help = "find bookmarks containing TERM",
  run = function(ctx, opts)
    local term = opts[1]
    if term == nil then
      errors.usage("missing TERM")
    end
    local found = ctx.store:search(term)
    for _, entry in ipairs(found) do
      ctx.out(format_row(entry))
    end
    if #found == 0 then
      errors.not_found("nothing matches '%s'", term)
    end
  end,
}

command "show" {
  usage = "show ID",
  help = "show one bookmark",
  run = function(ctx, opts)
    local id = need_id(opts)
    local entry = ctx.store:get(id) or errors.not_found("no entry with id %d", id)
    ctx.out(("%-6s %d"):format("id:", entry.id))
    ctx.out(("%-6s %s"):format("title:", entry.title))
    ctx.out(("%-6s %s"):format("url:", entry.url))
    ctx.out(("%-6s %s"):format("tags:", entry:tag_string(", ")))
    if entry.note ~= "" then
      ctx.out(("%-6s %s"):format("note:", entry.note))
    end
  end,
}

command "rm" {
  usage = "rm ID",
  help = "delete a bookmark",
  run = function(ctx, opts)
    local id = need_id(opts)
    local entry = ctx.store:remove(id) or errors.not_found("no entry with id %d", id)
    ctx.out("removed " .. tostring(entry))
  end,
}

command "tags" {
  usage = "tags",
  help = "count bookmarks per tag",
  run = function(ctx)
    for _, row in ipairs(ctx.store:tags()) do
      ctx.out(("%4d  %s"):format(row.count, row.tag))
    end
  end,
}

command "help" {
  usage = "help",
  help = "show this help",
  run = function(ctx)
    ctx.out("usage: stash <command> [arguments]")
    ctx.out("")
    ctx.out("commands:")
    for _, name in ipairs(order) do
      local c = commands[name]
      ctx.out(("  %-28s  %s"):format(c.usage, c.help))
    end
  end,
}

command "version" {
  usage = "version",
  help = "print the version",
  run = function(ctx)
    ctx.out("stash " .. VERSION)
  end,
}

return commands
