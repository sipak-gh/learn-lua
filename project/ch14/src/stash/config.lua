-- Configuration: $STASH_HOME/config.lua is a Lua file that sets variables.
--
--   list_limit = 10
--   aliases = { ls = "list", lua = "list -t lua" }
--   color = "never"
--
-- Config is code, so we run it, but in an empty environment: it cannot
-- see our globals, and its assignments land in a table we inspect.

local M = {}

-- Every known setting with its default. The type of the default is the
-- type the setting must have.
M.defaults = {
  list_limit = 20,
  aliases = {},
  color = "auto",
}

-- Settings that only accept a few values.
M.choices = {
  color = { "auto", "always", "never" },
}

local function is_one_of(value, choices)
  for _, choice in ipairs(choices) do
    if value == choice then
      return true
    end
  end
  return false
end

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
    local choices = M.choices[key]
    if choices and not is_one_of(value, choices) then
      return nil, ("%s: '%s' must be one of %s"):format(path, key, table.concat(choices, ", "))
    end
    settings[key] = value
  end
  return settings
end

return M
