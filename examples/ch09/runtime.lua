-- Runtime errors are raised by Lua itself. pcall catches them the same way.
local t = nil
print(pcall(function() return t.name end))
print(pcall(function() return undefined_function() end))
print(pcall(function() return "abc" + 1 end))
print(pcall(function() return #42 end))

-- pcall passes extra arguments to the function, and returns all its results.
print(pcall(string.rep, "ab", 3))
print(pcall(string.rep))
