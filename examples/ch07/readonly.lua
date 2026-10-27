-- A read-only view: an empty proxy whose metatable reads from the real table
-- and refuses writes.
local function readonly(t)
  return setmetatable({}, {
    __index = t,
    __newindex = function(_, key)
      error("attempt to change read-only key '" .. tostring(key) .. "'", 2)
    end,
    __metatable = false,          -- getmetatable() returns false; setmetatable() fails
  })
end

local DAYS = readonly({ "Mon", "Tue", "Wed" })
print(DAYS[2])
print(pcall(function() DAYS[4] = "Thu" end))
print(pcall(setmetatable, DAYS, nil))
print(getmetatable(DAYS))

-- The catch: the proxy itself is empty.
print(#DAYS, next(DAYS))
