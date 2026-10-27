-- Coroutines are cheap, but a switch costs more than a function call.
-- Timings vary by machine; compare the two numbers, not the values.

local N = 1e7

local function closure_iter(n)
  local i = 0
  return function()
    i = i + 1
    if i <= n then
      return i
    end
  end
end

local function coroutine_iter(n)
  return coroutine.wrap(function()
    for i = 1, n do
      coroutine.yield(i)
    end
  end)
end

for _, case in ipairs({ { "closure", closure_iter }, { "coroutine", coroutine_iter } }) do
  local start, sum = os.clock(), 0
  for i in case[2](N) do
    sum = sum + i
  end
  print(("%-9s %6.0f ms  (sum %.0f)"):format(case[1], (os.clock() - start) * 1000, sum))
end
