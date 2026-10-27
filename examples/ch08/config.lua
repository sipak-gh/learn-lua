-- Load a config file as data: run it in an empty environment, then read
-- the variables it set.
local function load_config(path)
  local chunk, err = loadfile(path)
  if chunk == nil then
    return nil, err
  end
  local env = {}
  setfenv(chunk, env)
  chunk()
  return env
end

local cfg = assert(load_config("examples/ch08/settings.lua"))
print(cfg.name, cfg.width, table.concat(cfg.tags, ","))
print(load_config("examples/ch08/nosuch.lua"))
