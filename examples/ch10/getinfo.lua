-- debug.getinfo(level, "Sl"): where is the code at that level of the stack?
-- 1 = the running function, 2 = its caller, 3 = the caller's caller.
local function where(level)
  local info = debug.getinfo(level, "Sl")
  return info.short_src .. ":" .. info.currentline
end

local function check()
  print("level 1: " .. where(1 + 1))      -- +1: skip `where` itself
  print("level 2: " .. where(2 + 1))
  print("level 3: " .. where(3 + 1))
end

local function a_test()
  check()                                  -- line 15
end

a_test()                                   -- line 18
