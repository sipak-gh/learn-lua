-- Gotcha: a generator's *return* values also come out of the wrapped
-- function. In a for loop they look like one more element, and the
-- next call hits a dead coroutine.

local gen = coroutine.wrap(function()
  coroutine.yield(1)
  coroutine.yield(2)
  return "oops"                              -- should be a plain `return`
end)

for v in gen do
  print(v)
end
