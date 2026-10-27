-- Values flow both ways: resume's extra arguments come out of yield,
-- and yield's arguments come out of resume.

local co = coroutine.create(function(a, b)   -- first resume: the parameters
  print("  got", a, b)
  local c = coroutine.yield(a + b)           -- hand a + b out, wait for c
  print("  got", c)
  local d, e = coroutine.yield(c * 2)
  print("  got", d, e)
  return "done", d .. e                      -- return values end it
end)

print("out:", coroutine.resume(co, 1, 2))
print("out:", coroutine.resume(co, 10))
print("out:", coroutine.resume(co, "x", "y"))
print(coroutine.status(co))
