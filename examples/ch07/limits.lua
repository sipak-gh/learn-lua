-- Two metamethods that do NOT work on tables in Lua 5.1 / LuaJIT.
local t = setmetatable({ 1, 2, 3 }, {
  __len = function() return 99 end,          -- ignored for tables
  __gc = function() print("collected") end,  -- ignored for tables
})
print(#t)                    -- 3, not 99
t = nil
collectgarbage()             -- prints nothing
print("done")
