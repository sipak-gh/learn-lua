-- Things the JIT can't compile: run with luajit -jv nyi.lua

local function with_closure(n)
  local sum = 0
  for i = 1, n do
    local double = function(x) return x * 2 end   -- a new closure each time
    sum = sum + double(i)
  end
  return sum
end

local function double(x)
  return x * 2
end

local function without_closure(n)
  local sum = 0
  for i = 1, n do
    sum = sum + double(i)                    -- one function, made once
  end
  return sum
end

local function with_gsub(n)
  local sum = 0
  for i = 1, n do
    sum = sum + #(("a,b,c"):gsub(",", ";"))  -- a C function the JIT doesn't know
  end
  return sum
end

local function time(name, fn)
  local start = os.clock()
  fn(1e6)
  print(("%-16s %6.1f ms"):format(name, (os.clock() - start) * 1000))
end

time("with closure", with_closure)
time("without closure", without_closure)
time("with gsub", with_gsub)
