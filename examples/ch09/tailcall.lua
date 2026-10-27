local function inner() local t = nil; return t.x end
local function outer() inner(); return 1 end

-- Wrong: `return debug.traceback(...)` is a tail call. It replaces the
-- handler's own stack frame, so level 2 skips one frame too many.
local _, a = xpcall(outer, function(e) return debug.traceback(e, 2) end)
print(a)

-- Right: store the result first, then return it.
local _, b = xpcall(outer, function(e)
  local tb = debug.traceback(e, 2)
  return tb
end)
print(b)
