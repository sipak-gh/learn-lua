-- Asking the FFI about C types.

local ffi = require("ffi")
ffi.cdef [[
struct point { int x, y; };
struct sample { char tag; double value; short count; };
]]

-- ffi.typeof turns a C type into a ctype object. Calling it creates values.
local point_t = ffi.typeof("struct point")
local p = point_t(3, 4)
print(point_t, p.x, p.y)

-- Sizes and alignment in bytes (on this machine).
print("int", ffi.sizeof("int"), "double", ffi.sizeof("double"), "pointer", ffi.sizeof("void *"))
print("struct point", ffi.sizeof(point_t), ffi.alignof(point_t))

-- The compiler inserts padding to align each field.
print("struct sample", ffi.sizeof("struct sample"))
for _, field in ipairs({ "tag", "value", "count" }) do
  print("  offsetof " .. field, ffi.offsetof("struct sample", field))
end

-- ffi.istype checks whether a value has a given C type.
print(ffi.istype(point_t, p), ffi.istype("struct point", p), ffi.istype("int", p))
print(ffi.istype("int", 42))    -- a Lua number is not cdata at all

-- tostring of a ctype shows its C name; typeof also works on values.
print(ffi.typeof(p), ffi.typeof(1LL), ffi.typeof("int[3]"))
