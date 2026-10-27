-- Entry point: load the settings, pick the command, run it, and turn any
-- error into a message on stderr plus an exit code.

local cli = require("stash.cli")
local commands = require("stash.commands")
local config = require("stash.config")
local errors = require("stash.errors")
local term = require("stash.term")
local util = require("stash.util")
local FileStore = require("stash.filestore")

local M = {}

-- The data directory: $STASH_HOME, or ~/.local/share/stash.
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

-- Messages go to stderr so they never mix with real output.
local function report(line)
  io.stderr:write(line, "\n")
end

-- Does the work. Raises errors instead of returning them; `state` records
-- the command being run, for the error report.
local function execute(args, state)
  local settings, err = config.load(M.home() .. "/config.lua")
  if settings == nil then
    errors.fail("%s", err)
  end

  args = expand_alias(args, settings.aliases)
  local name = args[1]
  if name == nil or name == "-h" or name == "--help" then
    name = "help"
  elseif name == "--version" then
    name = "version"
  end

  local command = commands[name] or errors.usage("unknown command '%s'", name)
  state.command = command
  local opts, perr = cli.parse(args, 2, command.options)
  if opts == nil then
    errors.usage("%s", perr)
  end

  local store, serr = FileStore.open(M.home() .. "/entries.lua")
  if store == nil then
    errors.fail("%s", serr)
  end
  local ctx = {
    store = store,
    config = settings,
    out = print,
    paint = term.painter(term.use_color(settings.color)),
    width = term.width(),
  }
  command.run(ctx, opts)
end

-- Runs stash with the given arguments and returns the exit code:
-- 0 success, 1 not found, 2 usage error or failure.
function M.run(args)
  local state = {}
  -- The handler runs where the error happened, before the stack unwinds,
  -- so it is the last chance to capture a traceback.
  local ok, err = xpcall(function() execute(args, state) end, function(e)
    if errors.is_error(e) then
      return e
    end
    return { kind = "bug", message = tostring(e), traceback = debug.traceback(tostring(e), 2) }
  end)
  if ok then
    return 0
  end

  local command = state.command
  if err.kind == "usage" and command then
    report(("stash %s: %s"):format(command.name, err.message))
    report("usage: stash " .. command.usage)
  elseif err.kind == "usage" then
    report("stash: " .. err.message .. " (try 'stash help')")
  elseif err.kind == "bug" then
    report("stash: internal error: " .. err.message)
    if os.getenv("STASH_DEBUG") then
      report(err.traceback)
    end
  else
    report("stash: " .. err.message)
  end
  return errors.EXIT[err.kind]
end

return M
