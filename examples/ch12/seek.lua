-- file:seek(whence, offset) moves the read/write position and returns it.

local path = "seek.txt"
local f = assert(io.open(path, "w+"))
f:write("0123456789")

print("size:", f:seek("end"))       -- end + 0 = the file size
print("pos:", f:seek("set", 3))     -- absolute position 3
print("read:", f:read(2))           -- "34", position is now 5
print("pos:", f:seek("cur"))        -- current position, unchanged
print("pos:", f:seek("cur", -4))    -- move back 4
print("read:", f:read("*a"))
print("pos:", f:seek("end", -2))
print("read:", f:read("*a"))
f:close()

-- A common helper: the size of a file without reading it.
local function file_size(p)
  local h = io.open(p, "rb")
  if not h then return nil end
  local size = h:seek("end")
  h:close()
  return size
end
print("file_size:", file_size(path), file_size("missing.txt"))
os.remove(path)
