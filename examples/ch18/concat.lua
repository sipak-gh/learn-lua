-- Three ways to build a long string from many pieces.
local buffer = require("string.buffer")
local N = 20000

local function time(name, fn)
  local start = os.clock()
  local s = fn()
  print(("%-14s %8.2f ms  %d bytes"):format(name, (os.clock() - start) * 1000, #s))
end

time("..", function()
  local s = ""
  for i = 1, N do
    s = s .. "line " .. i .. "\n"            -- copies all of s, every time
  end
  return s
end)

time("table.concat", function()
  local parts = {}
  for i = 1, N do
    parts[#parts + 1] = "line " .. i .. "\n"
  end
  return table.concat(parts)
end)

time("string.buffer", function()
  local buf = buffer.new()
  for i = 1, N do
    buf:put("line ", i, "\n")                -- appends in place
  end
  return buf:tostring()
end)
