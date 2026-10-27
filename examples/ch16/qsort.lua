-- C calls Lua: qsort from the C library, with a comparator written in Lua.
local ffi = require("ffi")

ffi.cdef [[
typedef int (*compare_fn)(const void *a, const void *b);
void qsort(void *base, size_t count, size_t size, compare_fn compare);
]]

local numbers = ffi.new("int[6]", { 42, 7, 19, 3, 88, 1 })

-- qsort hands us untyped pointers; we cast them to what they point to.
local function by_value(a, b)
  local x, y = ffi.cast("const int *", a)[0], ffi.cast("const int *", b)[0]
  return x < y and -1 or (x > y and 1 or 0)
end

local compare = ffi.cast("compare_fn", by_value)   -- a C function pointer
print(compare)
ffi.C.qsort(numbers, 6, ffi.sizeof("int"), compare)

local out = {}
for i = 0, 5 do
  out[#out + 1] = numbers[i]
end
print(table.concat(out, " "))

-- The same pointer, now calling a different Lua function: descending.
compare:set(function(a, b) return -by_value(a, b) end)
ffi.C.qsort(numbers, 6, ffi.sizeof("int"), compare)
print(numbers[0], numbers[5])

compare:free()                                     -- give the slot back
print(pcall(compare.set, compare, by_value))      -- a freed callback is dead
