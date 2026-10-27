-- One file, several Lua versions: detect features instead of versions.

print("_VERSION:", _VERSION)
print("LuaJIT:", jit and jit.version or "no")

local unpack = table.unpack or unpack          -- 5.1 has a global unpack
print("unpack:", unpack({ 1, 2, 3 }))

print("integers:", math.type and math.type(1) or "no integer subtype")
print("10 / 2 =", 10 / 2, " 2^53 + 1 =", 9007199254740993)

-- Run a chunk with its own globals, on any version.
local function run_with_env(code, env)
  if setfenv then                              -- Lua 5.1, LuaJIT
    local f = assert(loadstring(code))
    return setfenv(f, env)()
  end
  return assert(load(code, "=code", "t", env))()   -- Lua 5.2+
end
print("sandboxed:", run_with_env("return greeting", { greeting = "hi" }))
