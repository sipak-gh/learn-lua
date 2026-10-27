-- Strict mode: make undeclared globals an error. _G is a table like any other.
setmetatable(_G, {
  __newindex = function(_, name)
    error("assignment to undeclared global '" .. tostring(name) .. "'", 2)
  end,
  __index = function(_, name)
    error("undeclared global '" .. tostring(name) .. "'", 2)
  end,
})

local count = 0
print(pcall(function() count = count + 1 end))   -- a local: fine
print(pcall(function() conut = 1 end))          -- typo: caught
print(pcall(function() return coutn end))        -- typo: caught
rawset(_G, "DEBUG", false)                       -- declare a global on purpose
print(DEBUG)
