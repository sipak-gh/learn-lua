-- By value vs. by reference.

local ffi = require("ffi")
ffi.cdef [[
typedef struct { int quot; int rem; } div_t;
div_t div(int numerator, int denominator);
typedef struct vec { double x, y; } vec;
]]

-- A C function can return a whole struct by value. LuaJIT hands you
-- a new cdata holding the copy.
local r = ffi.C.div(17, 5)
print(r.quot, r.rem)

-- In Lua, assigning a cdata copies the reference, not the bytes.
local a = ffi.new("vec", 1, 2)
local b = a
b.x = 99
print(a.x)                 -- 99: a and b are the same object

-- To copy the bytes, make a new cdata initialized from the old one.
local c = ffi.new("vec", a)
c.x = 0
print(a.x, c.x)

-- Assigning a struct into a struct field or array slot copies bytes too.
local list = ffi.new("vec[2]")
list[0] = a
a.y = -1
print(list[0].x, list[0].y, a.y)
