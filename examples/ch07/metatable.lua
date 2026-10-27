-- A metatable changes how a table behaves. Here: missing keys get defaults.
local defaults = { color = "auto", width = 80 }
local settings = { width = 120 }

print(settings.color)                      -- nil: no metatable yet
setmetatable(settings, { __index = defaults })
print(settings.color, settings.width)      -- auto 120
print(rawget(settings, "color"))           -- nil: the table itself has no color
print(getmetatable(settings).__index == defaults)
print(getmetatable({}))                    -- a plain table has no metatable
