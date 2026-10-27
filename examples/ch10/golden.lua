-- A golden test compares output with a file that holds the expected text.
-- (io.open and file reading are covered in Chapter 12.)
local report = dofile("examples/ch10/report.lua")

local function read_file(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  return text
end

local function lines(s)
  local result = {}
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    result[#result + 1] = line
  end
  return result
end

local function check_golden(actual, path)
  local expected = read_file(path)
  if actual == expected then
    return true
  end
  local a, e = lines(actual), lines(expected)
  for i = 1, math.max(#a, #e) do          -- point at the first line that differs
    if a[i] ~= e[i] then
      return false, ("%s line %d:\n  expected %q\n  actual   %q"):format(
        path, i, tostring(e[i]), tostring(a[i]))
    end
  end
end

local rows = { { name = "lua", count = 12 }, { name = "jit", count = 3 } }
print(check_golden(report(rows), "examples/ch10/golden/report.txt"))

rows[2].count = 30
print(check_golden(report(rows), "examples/ch10/golden/report.txt"))
