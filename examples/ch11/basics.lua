-- A coroutine is a function that can pause (yield) and continue later (resume).

local co = coroutine.create(function()
  print("  step 1")
  coroutine.yield()                          -- pause here
  print("  step 2")
  coroutine.yield()
  print("  step 3")
end)

print(type(co), coroutine.status(co))
print("resume:", coroutine.resume(co))
print(coroutine.status(co))
print("resume:", coroutine.resume(co))
print("resume:", coroutine.resume(co))
print(coroutine.status(co))
print("resume:", coroutine.resume(co))     -- nothing left to run
