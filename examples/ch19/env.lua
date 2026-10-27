-- Every function has an environment: the table its globals live in.
-- setfenv swaps it, so the same code can run against a different world.

local code = [[
greeting = "hello from the plugin"      -- a global assignment...
function shout(s) return s:upper() end  -- ...and a global function
print(greeting)                          -- which print? the env's
]]

local chunk = assert(loadstring(code, "=plugin"))

local env = { print = function(...) print("[plugin]", ...) end }
setfenv(chunk, env)
chunk()

print(greeting)                         -- nil: our globals are untouched
print(env.greeting)                     -- the chunk's globals live in env
print(env.shout("quiet"))               -- functions it defines keep env
print(getfenv(env.shout) == env)

-- Without print in its environment, the chunk can't print at all.
local bare = setfenv(assert(loadstring("print('hi')", "=bare")), {})
print(pcall(bare))
