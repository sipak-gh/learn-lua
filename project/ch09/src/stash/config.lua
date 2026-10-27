-- Configuration: $STASH_HOME/config.lua is a Lua file that sets variables.
--
--   list_limit = 10
--   aliases = { ls = "list", lua = "list -t lua" }
--
-- Config is code, so we run it, but in an empty environment: it cannot
-- see our globals, and its assignments land in a table we inspect.

local M = {}

-- Every known setting with its default. The type of the default is the
-- type the setting must have.
M.defaults = {
  list_limit = 20,
  aliases = {},
}

-- Returns the settings table, or nil and an error message.
function M.load(path)
  local settings = {}
  for key, value in pairs(M.defaults) do
    settings[key] = value
  end

  -- A missing config file is fine: use the defaults. (io.open is covered
  -- in Chapter 12; here it only checks that the file exists.)
  local file = io.open(path)
  if file == nil then
    return settings
  end
  file:close()

  local chunk, err = loadfile(path)
  if chunk == nil then
    return nil, err                          -- syntax error, with file:line
  end
  local env = {}
  setfenv(chunk, env)                        -- globals of the chunk now live in env
  local ok, run_err = pcall(chunk)           -- a runtime error in the file is not our bug
  if not ok then
    return nil, run_err
  end

  for key, value in pairs(env) do
    local default = M.defaults[key]
    if default == nil then
      return nil, path .. ": unknown setting '" .. key .. "'"
    end
    if type(value) ~= type(default) then
      return nil, ("%s: '%s' must be a %s"):format(path, key, type(default))
    end
    settings[key] = value
  end
  return settings
end

return M
