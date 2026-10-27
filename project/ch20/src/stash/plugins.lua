-- Plugins: Lua files in $STASH_HOME/plugins that add commands and react
-- to events. config.lua says which ones to load:
--
--   plugins = { "autotag", "wordcount", "checksum" }
--   trusted_plugins = { "checksum" }
--
-- A plugin is a chunk run in its own environment. All it can see is a
-- few safe globals and the `stash` table: the plugin API.
--
--   stash.command(name, { usage =, help =, options =, run = function(opts) })
--   stash.on("add", function(fields) ... end)   -- before an entry is saved
--   stash.entries()   stash.get(id)   stash.page(id)   stash.text(html)
--   stash.print(...)  stash.paint(text, style)
--   stash.fail(fmt, ...)   stash.not_found(fmt, ...)
--
-- Entries reach plugins as plain records (copies), never as our own
-- objects: whatever a plugin can reach, it can change.
--
-- The sandbox keeps honest plugins from breaking stash by accident; it
-- is not a security boundary. A plugin can still loop forever or eat all
-- memory. And a *trusted* plugin gets `require`, and with it the FFI:
-- with the FFI, Lua code can read and write any memory. No sandbox
-- survives that, so only trust plugins you would run as a program.

local errors = require("stash.errors")
local html = require("stash.html")

local Plugins = {}
Plugins.__index = Plugins

local EVENTS = { add = true }

-- Globals every plugin gets. string, table and math are copied, so a
-- plugin that replaces string.format replaces it only for itself.
local SAFE = { "assert", "error", "ipairs", "next", "pairs", "pcall", "select",
               "tonumber", "tostring", "type", "unpack", "xpcall" }
local LIBRARIES = { "string", "table", "math" }

local function copy(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = v
  end
  return c
end

-- builtin: the built-in commands, which plugins may not replace.
function Plugins.new(builtin)
  return setmetatable({
    builtin = builtin or {},
    loaded = {},                             -- { name =, trusted =, commands =, events = }
    commands = {},                           -- name -> command record, like stash.commands
    order = {},                              -- command names, in the order registered
    hooks = { add = {} },                    -- event -> list of functions
    ctx = nil,                               -- set by main once the store is open
  }, Plugins)
end

-- Calls fn(...) on behalf of a plugin. A stash error (stash.fail and
-- friends) passes through; any other error becomes a failure that names
-- the plugin, instead of an "internal error" of stash.
local function call(plugin, fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then
    return
  end
  if errors.is_error(err) then
    error(err, 0)
  end
  errors.fail("plugin %s: %s", plugin.name, tostring(err))
end

-- The `stash` table for one plugin. Its functions close over `self`
-- (the registry) and `plugin` (the record of the plugin being loaded).
function Plugins:api(plugin)
  local function ctx()
    return self.ctx or error("stash API used while loading", 3)
  end
  local api = { name = plugin.name }

  function api.command(name, def)
    if type(name) ~= "string" or type(def) ~= "table" or type(def.run) ~= "function" then
      error("usage: stash.command(name, { usage =, help =, run = function })", 2)
    end
    if self.builtin[name] or self.commands[name] then
      error(("command '%s' already exists"):format(name), 2)
    end
    self.commands[name] = {
      name = name,
      usage = def.usage or name,
      help = def.help or "",
      options = def.options or {},
      plugin = plugin.name,
      run = function(_, opts) call(plugin, def.run, opts) end,
    }
    self.order[#self.order + 1] = name
    plugin.commands[#plugin.commands + 1] = name
  end

  function api.on(event, fn)
    if not EVENTS[event] then
      error(("unknown event '%s'"):format(tostring(event)), 2)
    end
    table.insert(self.hooks[event], function(...) return call(plugin, fn, ...) end)
    plugin.events[#plugin.events + 1] = event
  end

  function api.get(id)
    local entry = ctx().store:get(id)
    return entry and entry:record()
  end

  function api.entries()
    local entries = ctx().store:entries()
    return function()
      local entry = entries()
      return entry and entry:record()
    end
  end

  function api.page(id)
    return ctx().store:page(id)
  end

  api.text = html.text

  function api.print(...)
    local parts = { ... }
    for i = 1, select("#", ...) do
      parts[i] = tostring(parts[i])
    end
    ctx().out(table.concat(parts, "\t"))
  end

  function api.paint(text, style)
    return ctx().paint(text, style)
  end

  api.fail = errors.fail
  api.not_found = errors.not_found
  return api
end

-- The global environment of one plugin.
local function environment(api, trusted)
  local env = {}
  for _, name in ipairs(SAFE) do
    env[name] = _G[name]
  end
  for _, name in ipairs(LIBRARIES) do
    env[name] = copy(_G[name])
  end
  env.os = { time = os.time, date = os.date, clock = os.clock }
  env.print = api.print
  env.stash = api
  if trusted then
    env.require, env.io, env.os = require, io, os
  end
  return env
end

-- Loads the plugin `name` from the file `path`.
function Plugins:load(name, path, trusted)
  -- Mode "t": text only. Lua bytecode is never verified, and broken
  -- bytecode can crash the VM -- or worse.
  local chunk, err = loadfile(path, "t")
  if chunk == nil then
    errors.fail("plugin %s: %s", name, err)
  end
  local plugin = { name = name, trusted = trusted, commands = {}, events = {} }
  setfenv(chunk, environment(self:api(plugin), trusted))
  call(plugin, chunk)
  self.loaded[#self.loaded + 1] = plugin
end

-- Runs the hooks for an event, in the order the plugins were loaded.
function Plugins:emit(event, ...)
  for _, hook in ipairs(self.hooks[event]) do
    hook(...)
  end
end

return Plugins
