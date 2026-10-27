-- Strict mode: reading or assigning an undeclared global is an error.
-- Requiring this module once switches it on for the whole program.

setmetatable(_G, {
  __newindex = function(_, name)
    error("assignment to undeclared global '" .. tostring(name) .. "'", 2)
  end,
  __index = function(_, name)
    error("undeclared global '" .. tostring(name) .. "'", 2)
  end,
})

-- Nothing to return: require() stores `true` in package.loaded instead.
