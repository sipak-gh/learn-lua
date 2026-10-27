-- Building a big string: collect pieces, join once.
local N = 20000

-- Slow: every .. makes a new string and copies everything so far.
local t0 = os.clock()
local s = ""
for i = 1, N do
  s = s .. i .. ","
end
local slow = os.clock() - t0

-- Fast: put the pieces in a table, then table.concat.
t0 = os.clock()
local parts = {}
for i = 1, N do
  parts[#parts + 1] = i .. ","
end
local s2 = table.concat(parts)
local fast = os.clock() - t0

print(#s, #s2, s == s2)
print(("concat in a loop: %.1f ms, table.concat: %.1f ms"):format(slow * 1000, fast * 1000))
print(table.concat({ "a", "b", "c" }, ", "))
print(table.concat({ 1, 2, 3 }, " + ", 2, 3))   -- items 2..3 only

-- LuaJIT's string.buffer does the same job without the table (Chapter 18).
local buffer = require("string.buffer")
local buf = buffer.new()
for i = 1, 3 do
  buf:put("item ", i, "; ")
end
print(buf:tostring())
