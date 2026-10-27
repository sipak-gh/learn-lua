-- A sandbox does not stop a plugin from running forever. A count hook
-- can interrupt it -- but only in the interpreter: LuaJIT's compiled
-- code does not check hooks.

local function run_limited(code, max)
  local chunk = assert(load(code, "=plugin", "t"))
  setfenv(chunk, {})
  jit.off(chunk, true)                   -- interpret it, and what it defines
  debug.sethook(function() error("instruction limit reached", 2) end, "", max)
  local ok, err = pcall(chunk)
  debug.sethook()                        -- remove the hook
  return ok, err
end

print(run_limited("local n = 0 for i = 1, 1000 do n = n + i end", 1e6))
print(run_limited("while true do end", 1e6))
