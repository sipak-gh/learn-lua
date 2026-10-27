-- Every function has an environment: the table its globals live in.
print(getfenv(1) == _G)                     -- level 1 = this chunk: the normal _G

local chunk = loadstring("x = 10; y = x * 2; print = nil")
local env = {}
setfenv(chunk, env)                         -- the chunk's globals now live in env
chunk()

print(env.x, env.y, rawget(_G, "x"))        -- 10 20 nil: _G was not touched
print(print ~= nil)                         -- our print still works

-- With an empty env, code can't reach anything you don't give it.
local evil = loadstring("os.exit(1)")
setfenv(evil, {})
print(pcall(evil))

-- Give it exactly what it may use.
local calc = loadstring("return math.max(a, b)")
setfenv(calc, { math = math, a = 3, b = 7 })
print(calc())
