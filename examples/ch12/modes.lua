-- Open modes decide what you may do and where you start.

local path = "modes.txt"

local function show(label)
  local f = assert(io.open(path, "rb"))
  print(("%-3s %s"):format(label, (f:read("*a"):gsub("\n", "|"))))  -- "|" marks a newline
  f:close()
end

local f = assert(io.open(path, "w"))         -- w: truncate (or create)
f:write("hello\n")
f:close()
show("w")

f = assert(io.open(path, "a"))               -- a: every write goes to the end
f:write("more\n")
f:close()
show("a")

f = assert(io.open(path, "r+"))              -- r+: read and write, start at 0, no truncation
f:write("J")                                 -- overwrites the "h"
f:close()
show("r+")

f = assert(io.open(path, "w+"))              -- w+: truncate, then read and write
f:write("fresh")
f:seek("set")                                -- back to the start before reading
print("w+ " .. f:read("*a"))
f:close()

os.remove(path)

-- Failure is a normal return value, not an error:
print(io.open("no/such/file.txt"))
print(io.open("/", "w"))
