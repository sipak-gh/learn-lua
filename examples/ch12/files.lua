-- Write a file, then read it back in different ways.

local path = "notes.txt"

-- Shows values with newlines visible, e.g. "a\n".
local function show(...)
  local out = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    out[i] = type(v) == "string" and '"' .. v:gsub("\n", "\\n") .. '"' or tostring(v)
  end
  print(table.concat(out, "  "))
end

-- io.open returns a file handle, or nil plus an error message.
local f = assert(io.open(path, "w"))         -- "w": create or truncate
f:write("first line\n", "second line\n")     -- any number of strings...
f:write(42, " ", 3.5, "\n")                  -- ...and numbers
f:write("last line, no newline")
f:close()

f = assert(io.open(path, "r"))               -- "r": read (the default)
show(f:read("*l"))                           -- one line, without the "\n"
show(f:read("*L"))                           -- one line, keeping the "\n"
show(f:read("*n", "*n"))                     -- two numbers
show(f:read(5))                              -- up to 5 bytes
show(f:read("*a"))                           -- everything that is left
show(f:read("*a"), f:read("*l"), f:read(1))  -- at the end of the file
f:close()

os.remove(path)
