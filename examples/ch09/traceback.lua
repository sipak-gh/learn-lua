-- xpcall(f, handler): the handler runs at the point of the error,
-- before the stack unwinds, so it can still see the stack.
local function inner()
  local t = nil
  return t.x
end
local function outer()
  inner()
  return "never"
end

local ok, tb = xpcall(outer, debug.traceback)
print(ok)
print(tb)
