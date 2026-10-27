-- Lua tables vs C arrays: filling and summing a million numbers.
--
--   luajit bench/arrays.lua
--
-- Timings depend on the machine; compare runs on the same one.

package.path = "src/?.lua;" .. package.path

local ffi = require("ffi")
local table_new = require("table.new")     -- table.new(narray, nhash)
local clock = require("stash.clock")

local N = 1000000

local function measure(name, fn)
  local best = math.huge
  for _ = 1, 5 do
    collectgarbage()
    local start = clock.now()
    fn()
    best = math.min(best, clock.now() - start)
  end
  print(("%-28s %8.2f ms"):format(name, best * 1000))
end

-- Filling: a table grows as we go (and is copied each time it grows),
-- unless table.new makes it big enough up front.
measure("fill table", function()
  local t = {}
  for i = 1, N do t[i] = i * 0.5 end
end)
measure("fill table.new", function()
  local t = table_new(N, 0)
  for i = 1, N do t[i] = i * 0.5 end
end)
measure("fill double[N]", function()
  local a = ffi.new("double[?]", N)        -- zero-filled, fixed size
  for i = 0, N - 1 do a[i] = i * 0.5 end
end)

-- Summing: the loops are traces of a few machine instructions each.
local t, a = {}, ffi.new("double[?]", N)
for i = 1, N do t[i] = i * 0.5; a[i - 1] = i * 0.5 end

local function sum_table()
  local sum = 0
  for i = 1, N do sum = sum + t[i] end
  return sum
end
local function sum_array()
  local sum = 0
  for i = 0, N - 1 do sum = sum + a[i] end
  return sum
end
assert(sum_table() == sum_array())
measure("sum table", sum_table)
measure("sum double[N]", sum_array)

-- Memory: what does each one add to the heap? For plain numbers the
-- two are alike; the C array wins with smaller types and with records,
-- where every Lua table is a separate object with its own header.
local function heap_kb(make)
  collectgarbage()
  local before = collectgarbage("count")
  local keep = make()                      -- not garbage before we count
  local after = collectgarbage("count")
  return math.floor(after - before + 0.5)
end

local M = 100000
print(("%d numbers: table %d KB, double[] %d KB, uint8_t[] %d KB"):format(N,
  heap_kb(function() return table_new(N, 0) end),
  heap_kb(function() return ffi.new("double[?]", N) end),
  heap_kb(function() return ffi.new("uint8_t[?]", N) end)))
print(("%d points: tables %d KB, struct[] %d KB"):format(M,
  heap_kb(function()
    local points = table_new(M, 0)
    for i = 1, M do points[i] = { x = i, y = i } end
    return points
  end),
  heap_kb(function() return ffi.new("struct { double x, y; }[?]", M) end)))
