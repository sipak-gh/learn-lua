-- Loop over the lines of a file.

local path = "lines.txt"
local f = assert(io.open(path, "w"))
f:write("alpha\nbeta\n\ngamma")              -- an empty line, no final newline
f:close()

-- io.lines(path) opens the file, yields each line, and closes it at the end.
for line in io.lines(path) do
  print(("[%s]"):format(line))
end

-- file:lines() does the same on a handle you opened. You close it yourself.
f = assert(io.open(path))
local n = 0
for line in f:lines() do n = n + 1 end
f:close()
print("lines:", n)

os.remove(path)

-- io.lines on a missing file raises an error (unlike io.open).
local ok, msg = pcall(function()
  for line in io.lines("missing.txt") do print(line) end
end)
print(ok, msg)
