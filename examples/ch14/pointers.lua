-- Pointers: arithmetic, indexing, casts.

local ffi = require("ffi")

local arr = ffi.new("int[4]", { 10, 20, 30, 40 })

-- An array converts to a pointer to its first element.
local p = ffi.cast("int *", arr)
print(p[0], p[3])          -- indexing a pointer: p[i] is *(p + i)

-- Arithmetic moves in units of the pointed-to type (4 bytes for int).
local q = p + 2
print(q[0], q[-1])         -- negative indexes are fine if the memory is yours
print(q - p)               -- difference of two pointers, in elements
print(q > p, p == arr)     -- comparisons work on addresses

-- Write through a pointer:
q[1] = 99
print(arr[3])

-- ffi.cast reinterprets: here, the same bytes seen as single bytes.
local bytes = ffi.cast("uint8_t *", arr)
print(bytes[0], bytes[1], bytes[4])   -- 10 = 0x0a, little-endian

-- Casting numbers: same bits, different meaning, like C.
print(tonumber(ffi.cast("int32_t", 0xffffffff)), tonumber(ffi.cast("uint32_t", -1)))
local big = ffi.new("int", 300)
print(tonumber(ffi.cast("uint8_t", big)))   -- keeps the low 8 bits: 300 - 256

-- A pointer to a struct uses "." for fields too (no "->" in Lua).
ffi.cdef [[ typedef struct pair { int a, b; } pair; ]]
local pairs_arr = ffi.new("pair[2]", { { 1, 2 }, { 3, 4 } })
local pp = ffi.cast("pair *", pairs_arr) + 1
print(pp.a, pp.b, pp[0].a)

-- Pointers can be turned into numbers (addresses), e.g. for debugging.
print(ffi.cast("uintptr_t", q) - ffi.cast("uintptr_t", p))  -- bytes, not elements
