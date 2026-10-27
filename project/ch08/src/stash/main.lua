-- Entry point: load the settings, pick the command, run it.

local cli = require("stash.cli")
local commands = require("stash.commands")
local config = require("stash.config")
local util = require("stash.util")
local MemoryStore = require("stash.memstore")
local sample = require("stash.sample")

local M = {}

local function fail(fmt, ...)
  print("stash: " .. fmt:format(...))
end

-- The data directory: $STASH_HOME, or ~/.local/share/stash.
-- (os.getenv reads an environment variable; more in Chapter 12.)
function M.home()
  return os.getenv("STASH_HOME") or (os.getenv("HOME") .. "/.local/share/stash")
end

-- Replaces an alias in args[1] by its words: with aliases = { ll = "list
-- --limit 5" }, `stash ll -t lua` becomes `stash list --limit 5 -t lua`.
local function expand_alias(args, aliases)
  local alias = args[1] and aliases[args[1]]
  if alias == nil then
    return args
  end
  local expanded = util.split(alias, " ")
  for i = 2, #args do
    expanded[#expanded + 1] = args[i]
  end
  return expanded
end

function M.run(args)
  local settings, err = config.load(M.home() .. "/config.lua")
  if settings == nil then
    return fail("%s", err)
  end

  args = expand_alias(args, settings.aliases)
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
  local opts, perr = cli.parse(args, 2, command.options)
  if opts == nil then
    return fail("%s: %s", name, perr)
  end

  local ctx = {
    store = MemoryStore.new(sample),
    config = settings,
    out = print,
  }
  command.run(ctx, opts)
end

return M
