-- Structs, nested structs and unions.

local ffi = require("ffi")
ffi.cdef [[
typedef struct point { double x, y; } point;
typedef struct {
  point min, max;          /* nested structs */
  char label[8];
} box;
typedef union {
  uint32_t u;
  float f;
  uint8_t bytes[4];
} word;
]]

-- Fields are read and written with ".", like a table.
local p = ffi.new("point", 1, 2)              -- positional initializers
p.x = p.x + 10
print(p.x, p.y)

-- A table initializer can name the fields; nested structs take nested tables.
local b = ffi.new("box", { min = { 0, 0 }, max = { x = 4, y = 3 }, label = "room" })
print(b.max.x - b.min.x, b.max.y - b.min.y, ffi.string(b.label))

-- b.max is not a copy: it is a reference into b's memory.
local corner = b.max
corner.x = 100
print(b.max.x)

-- Unknown fields are errors, not nil:
print(pcall(function() return p.z end))

-- A union stores all its fields in the same bytes.
local w = ffi.new("word")
w.f = 1.0
print(("float 1.0 = 0x%08x"):format(w.u), w.bytes[0], w.bytes[3])
print(ffi.sizeof("word"))
