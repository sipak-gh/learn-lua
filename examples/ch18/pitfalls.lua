-- Three ways a benchmark can lie.
local function time(name, fn)
  local start = os.clock()
  local result = fn()
  print(("%-24s %7.3f ms"):format(name, (os.clock() - start) * 1000))
  return result
end

-- 1. Work whose result is never used may be removed by the compiler.
time("result thrown away", function()
  for i = 1, 1e7 do
    local _ = math.sqrt(i)
  end
end)
time("result used", function()
  local sum = 0
  for i = 1, 1e7 do
    sum = sum + math.sqrt(i)
  end
  return sum
end)

-- 2. One run is not a measurement: the first one includes compiling,
-- and any of them may be slowed down by whatever else the machine does.
local function work()
  local sum = 0
  for i = 1, 20000 do sum = sum + (i % 7) * (i % 3) end
  return sum
end
for round = 1, 4 do
  time("round " .. round, work)
end

-- 3. Garbage made by earlier code is collected during later code.
local function allocate()
  local t = {}
  for i = 1, 3e5 do t[i] = { i } end
  return t
end
local junk = {}
for i = 1, 3e6 do junk[i] = { i } end
junk = nil
time("after making garbage", allocate)
collectgarbage()                             -- a full collection, now
time("after collectgarbage()", allocate)
