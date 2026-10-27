-- Globals vs locals. Try: luajit locals.lua, then luajit -joff locals.lua
local N = 1e7

local function with_globals()
  local sum = 0
  for i = 1, N do
    sum = sum + math.floor(i / 3)            -- looks up `math`, then `floor`
  end
  return sum
end

local floor = math.floor                     -- looked up once, here
local function with_locals()
  local sum = 0
  for i = 1, N do
    sum = sum + floor(i / 3)
  end
  return sum
end

local function time(name, fn)
  local start = os.clock()
  fn()
  print(("%-12s %6.1f ms"):format(name, (os.clock() - start) * 1000))
end

time("globals", with_globals)
time("locals", with_locals)
