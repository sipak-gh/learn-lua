-- An error inside a coroutine stops it. resume catches the error like
-- pcall does; wrap raises it again in the caller.

local co = coroutine.create(function()
  coroutine.yield("first")
  error("something broke")
end)

print(coroutine.resume(co))
print(coroutine.resume(co))
print(coroutine.status(co))                  -- an error kills the coroutine

-- The coroutine's stack survives the error: debug.traceback can show it.
local bad = coroutine.create(function()
  local function inner() error("deep error") end
  inner()
end)
local _, err = coroutine.resume(bad)
print(debug.traceback(bad, err))

-- wrap: the error comes out of the call, so pcall or let it propagate.
local gen = coroutine.wrap(function() error({ code = 42 }) end)
local ok2, e = pcall(gen)
print(ok2, type(e), e.code)                  -- error values pass through unchanged

-- LuaJIT can yield across pcall (Lua 5.1 cannot).
local guarded = coroutine.wrap(function()
  local ok3, v = pcall(function()
    local got = coroutine.yield("yielded inside pcall")
    error("failed after resume with " .. got)
  end)
  coroutine.yield(ok3, v)
end)
print(guarded())
print(guarded("hello"))

-- Yielding where no coroutine is running is an error.
print(pcall(coroutine.yield))
