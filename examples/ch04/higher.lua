-- Higher-order functions take or return functions.
local function map(list, f)
  local out = {}
  for i, v in ipairs(list) do
    out[i] = f(v)
  end
  return out
end

local function filter(list, keep)
  local out = {}
  for _, v in ipairs(list) do
    if keep(v) then
      out[#out + 1] = v
    end
  end
  return out
end

local function reduce(list, f, acc)
  for _, v in ipairs(list) do
    acc = f(acc, v)
  end
  return acc
end

local function compose(f, g)
  return function(...) return f(g(...)) end
end

local nums = { 1, 2, 3, 4, 5, 6 }
local squares = map(nums, function(x) return x * x end)
local evens = filter(squares, function(x) return x % 2 == 0 end)
print(unpack(squares))
print(unpack(evens))
print(reduce(nums, function(a, b) return a + b end, 0))

local inc_then_double = compose(function(x) return x * 2 end,
                                function(x) return x + 1 end)
print(inc_then_double(5))
