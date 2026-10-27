-- coroutine.running() is the coroutine that runs this code; nil in the
-- main program. coroutine.isyieldable() says whether yield is allowed.

print("main:", coroutine.running(), coroutine.isyieldable())

local co
co = coroutine.create(function()
  print("inside:", coroutine.running() == co, coroutine.isyieldable())
  print("status of itself:", coroutine.status(co))
end)
coroutine.resume(co)

-- A coroutine that resumes another one is "normal" while the other runs.
local outer
outer = coroutine.create(function()
  local inner = coroutine.create(function()
    print("outer is", coroutine.status(outer))
  end)
  coroutine.resume(inner)
end)
coroutine.resume(outer)
