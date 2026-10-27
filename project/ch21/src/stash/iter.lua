-- Iterator pipelines. An iterator here is a function that returns the
-- next value on each call and nil at the end, so it works in a generic
-- for:  for v in it do ... end
--
-- coroutine.wrap turns a loop that *yields* values into such a function.
-- That lets each stage be written as a plain loop.

local M = {}

-- Iterates over the values of an array.
function M.values(array)
  return coroutine.wrap(function()
    for _, v in ipairs(array) do
      coroutine.yield(v)
    end
  end)
end

-- Passes on the values for which pred(value) is true.
function M.filter(pred, it)
  return coroutine.wrap(function()
    for v in it do
      if pred(v) then
        coroutine.yield(v)
      end
    end
  end)
end

-- Passes on at most n values, then stops pulling from `it`.
function M.take(n, it)
  return coroutine.wrap(function()
    if n <= 0 then
      return
    end
    local count = 0
    for v in it do
      coroutine.yield(v)
      count = count + 1
      if count == n then
        return
      end
    end
  end)
end

-- Drains an iterator into an array.
function M.collect(it)
  local result = {}
  for v in it do
    result[#result + 1] = v
  end
  return result
end

return M
