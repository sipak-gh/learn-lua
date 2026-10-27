-- The commands. Each one gets a context table `ctx` (the store, the
-- settings, an `out` function for output, a `paint` function for color,
-- the terminal `width` and the loaded `plugins`) plus the parsed options.
-- Problems are raised with the helpers in stash.errors; main turns them
-- into messages and exit codes.

local compress = require("stash.compress")
local Db = require("stash.db")
local Entry = require("stash.entry")
local errors = require("stash.errors")
local fetch = require("stash.fetch")
local fs = require("stash.fs")
local html = require("stash.html")
local json = require("stash.json")
local util = require("stash.util")

local VERSION = "1.0.0"

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

-- Tags are lowercase words; duplicates are dropped.
local function clean_tags(list)
  local tags, seen = {}, {}
  for _, tag in ipairs(list) do
    tag = tostring(tag):lower()
    if not tag:find("^[%w_-]+$") then
      errors.usage("bad tag '%s' (use letters, digits, - and _)", tag)
    end
    if not seen[tag] then
      seen[tag] = true
      tags[#tags + 1] = tag
    end
  end
  return tags
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

-- One line of `list` output. The title gets whatever the other columns
-- leave of the terminal width, but never less than 20 characters.
-- Pads first, then paints: escape codes have no width on screen, but
-- string.format would count them.
local function format_row(ctx, entry)
  local paint = ctx.paint
  local title_width = math.max(20, ctx.width - 44)
  return ("%s  %s  %s  %s"):format(
    paint(("%3d"):format(entry.id), "id"),
    ("%-" .. title_width .. "s"):format(util.truncate(entry.title, title_width)),
    paint(("%-16s"):format(util.truncate(entry:tag_string(), 16)), "tag"),
    paint(util.date(entry.created), "dim"))
end

command "add" {
  usage = "add URL [-t TAGS] [-n NOTE] [--no-fetch]",
  help = "save a bookmark",
  options = { ["-t"] = { "tags", "list" }, ["-n"] = { "note", "value" },
              ["--no-fetch"] = { "no_fetch", "flag" } },
  run = function(ctx, opts)
    local url = opts[1]
    if url == nil then
      errors.usage("missing URL")
    end
    if not url:find("^%a[%w+.-]*://") then
      errors.usage("'%s' does not look like a URL", url)
    end
    local tags = clean_tags(opts.tags or {})
    -- Download the page for its title and the search index.
    local title, text, page
    if not opts.no_fetch then
      local body, info = fetch.get(url, { user_agent = ctx.config.user_agent,
                                          timeout = ctx.config.timeout })
      if body == nil then
        errors.fail("cannot fetch %s: %s", url, info)
      end
      -- file:// URLs have no content type; trust them to be HTML.
      if info.content_type == nil or info.content_type:find("html") then
        title, text, page = html.title(body), html.text(body), body
      end
    end
    -- Plugins may change the title, note and tags before we save. They
    -- get a plain table: our Entry objects stay out of their reach.
    local fields = { url = url, title = title, note = opts.note or "", tags = tags, text = text }
    ctx.plugins:emit("add", fields)
    local entry = ctx.store:add(Entry.new({ url = url, title = fields.title, note = fields.note,
                                            tags = clean_tags(fields.tags), created = util.now() }),
                                text, page)
    ctx.out("added " .. tostring(entry))
  end,
}

command "list" {
  usage = "list [-t TAG] [-m PATTERN] [--limit N]",
  help = "list bookmarks",
  options = { ["-t"] = { "tag", "value" }, ["-m"] = { "match", "value" },
              ["--limit"] = { "limit", "number" } },
  run = function(ctx, opts)
    -- Check the pattern here, where a mistake is a usage error.
    local valid, err = pcall(string.find, "", opts.match or "")
    if not valid then
      errors.usage("bad pattern '%s': %s", opts.match, err)
    end
    local limit = opts.limit or ctx.config.list_limit
    local filter = { tag = opts.tag, match = opts.match, limit = limit }
    for _, entry in ipairs(ctx.store:list(filter)) do
      ctx.out(format_row(ctx, entry))
    end
  end,
}

command "search" {
  usage = "search WORDS...",
  help = "full-text search, best matches first",
  run = function(ctx, opts)
    local words = table.concat(opts, " ")
    if words == "" then
      errors.usage("missing WORDS")
    end
    local found = ctx.store:search(words)
    for _, entry in ipairs(found) do
      ctx.out(format_row(ctx, entry))
      ctx.out("     " .. entry.snippet)
    end
    if #found == 0 then
      errors.not_found("nothing matches '%s'", words)
    end
  end,
}

command "show" {
  usage = "show ID [--body]",
  help = "show one bookmark, or its saved page",
  options = { ["--body"] = { "body", "flag" } },
  run = function(ctx, opts)
    local id = need_id(opts)
    local entry = ctx.store:get(id) or errors.not_found("no entry with id %d", id)
    if opts.body then
      local page = ctx.store:page(id) or errors.not_found("no saved page for #%d", id)
      ctx.out((page:gsub("\n$", "")))        -- out adds the final newline
      return
    end
    ctx.out(("%-6s %d"):format("id:", entry.id))
    ctx.out(("%-6s %s"):format("title:", entry.title))
    ctx.out(("%-6s %s"):format("url:", entry.url))
    ctx.out(("%-6s %s"):format("tags:", entry:tag_string(", ")))
    ctx.out(("%-6s %s"):format("added:", util.datetime(entry.created)))
    local size, stored = ctx.store:page_size(id)
    if size then
      ctx.out(("%-6s %d bytes, %d compressed"):format("page:", size, stored))
    end
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
      ctx.out(("%4d  %s"):format(row.count, ctx.paint(row.tag, "tag")))
    end
  end,
}

command "export" {
  usage = "export [FILE]",
  help = "write all bookmarks as JSON",
  run = function(ctx, opts)
    -- A pipeline: entries -> plain records -> JSON lines -> output.
    local records = coroutine.wrap(function()
      for entry in ctx.store:entries() do
        coroutine.yield(entry:record())
      end
    end)
    local path = opts[1]
    if path == nil or path == "-" then
      json.write_array(records, ctx.out)
      return
    end
    local ok, result = fs.with_file(path, "w", function(file)
      return json.write_array(records, function(line) file:write(line, "\n") end)
    end)
    if not ok then
      errors.fail("cannot export: %s", result)
    end
    ctx.out(("exported %d entries to %s"):format(result, path))
  end,
}

command "stats" {
  usage = "stats",
  help = "count entries and the space pages take",
  run = function(ctx)
    local s = ctx.store:stats()
    ctx.out(("entries  %d"):format(s.entries))
    ctx.out(("tags     %d"):format(s.tags))
    ctx.out(("pages    %d"):format(s.pages))
    ctx.out(("size     %d bytes"):format(s.size))
    if s.size > 0 then
      ctx.out(("stored   %d bytes (%d%%)"):format(s.stored,
                         math.floor(s.stored / s.size * 100 + 0.5)))
    end
  end,
}

command "plugins" {
  usage = "plugins",
  help = "list the loaded plugins",
  run = function(ctx)
    local loaded = ctx.plugins.loaded
    for _, p in ipairs(loaded) do
      local provides = {}
      if #p.commands > 0 then
        provides[#provides + 1] = "commands: " .. table.concat(p.commands, ", ")
      end
      if #p.events > 0 then
        provides[#provides + 1] = "events: " .. table.concat(p.events, ", ")
      end
      ctx.out(("%-12s %s%s"):format(p.name, table.concat(provides, "; "),
                                    p.trusted and "  (trusted)" or ""))
    end
    if #loaded == 0 then
      ctx.out("no plugins loaded (see 'plugins' in config.lua)")
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
    local width = 0                          -- of the longest usage line
    for _, name in ipairs(order) do
      width = math.max(width, #commands[name].usage)
    end
    local plugins = ctx.plugins
    for _, name in ipairs(plugins.order) do
      width = math.max(width, #plugins.commands[name].usage)
    end
    local function show(c)
      ctx.out(("  %-" .. width .. "s  %s"):format(c.usage, c.help))
    end
    for _, name in ipairs(order) do
      show(commands[name])
    end
    if #plugins.order > 0 then
      ctx.out("")
      ctx.out("plugin commands:")
      for _, name in ipairs(plugins.order) do
        show(plugins.commands[name])
      end
    end
  end,
}

command "version" {
  usage = "version [-v]",
  help = "print the version (-v: and the libraries' versions)",
  options = { ["-v"] = { "verbose", "flag" } },
  run = function(ctx, opts)
    ctx.out("stash " .. VERSION)
    if opts.verbose then
      ctx.out(jit.version)
      ctx.out("SQLite " .. Db.version())
      ctx.out("zlib " .. compress.version())
      ctx.out(fetch.version())
    end
  end,
}

return commands
