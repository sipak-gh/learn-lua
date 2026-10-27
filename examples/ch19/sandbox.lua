-- A sandbox: an environment holding only what we choose to share.

local SAFE = { "assert", "error", "ipairs", "next", "pairs", "pcall",
               "select", "tonumber", "tostring", "type", "unpack" }

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function sandbox()
  local env = {}
  for _, name in ipairs(SAFE) do
    env[name] = _G[name]
  end
  -- Copies: a plugin that changes string.rep changes only its own copy.
  env.string, env.table, env.math = copy(string), copy(table), copy(math)
  env.os = { time = os.time, date = os.date, clock = os.clock }
  env.print = print
  return env
end

-- Loads source code as text only ("t") and runs it in a fresh sandbox,
-- plus the `extra` globals, if any.
local function run(name, code, extra)
  local chunk, err = load(code, "=" .. name, "t")
  if chunk == nil then
    return print(name, "refused:", err)
  end
  local env = sandbox()
  for k, v in pairs(extra or {}) do env[k] = v end
  setfenv(chunk, env)
  local ok, perr = pcall(chunk)
  print(name, ok and "ok" or perr)
end

run("peek", [[ print(type(io), type(require), type(os.execute), type(os.time)) ]])
run("io", [[ io.open("/etc/passwd") ]])
run("vandal", [[ string.rep = nil; print(type(string.rep)) ]])
print("host still has string.rep:", type(string.rep))
-- Method calls on strings use the real string library, not the copy:
run("method", [[ string.upper = nil; print(("abc"):upper()) ]])
-- Bytecode is refused: it is never verified, and bad bytecode can crash.
run("bytecode", string.dump(function() print("hi") end))

-- Two "harmless" functions that open the sandbox wide:
run("getfenv", [[ print(type(getfenv(0).io)) ]], { getfenv = getfenv })
run("getmetatable", [[ getmetatable("").__index.upper = function() return "pwned" end ]],
    { getmetatable = getmetatable })
print(("host"):upper())
