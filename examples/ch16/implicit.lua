-- Passing a Lua function where C wants a function pointer works, but each
-- call makes a new callback that is never freed. Slots run out.
local ffi = require("ffi")

ffi.cdef [[
void qsort(void *base, size_t count, size_t size, int (*compare)(const void *, const void *));
]]

local numbers = ffi.new("int[2]", { 2, 1 })
local function compare(a, b)
  return ffi.cast("const int *", a)[0] - ffi.cast("const int *", b)[0]
end

-- Right: convert once, reuse the pointer.
local cb = ffi.cast("int (*)(const void *, const void *)", compare)
for _ = 1, 10000 do
  ffi.C.qsort(numbers, 2, 4, cb)
end
print("10000 sorts, one callback")

-- Wrong: every call converts the function again.
local calls = 0
local ok, err = pcall(function()
  for _ = 1, 10000 do
    ffi.C.qsort(numbers, 2, 4, compare)
    calls = calls + 1
  end
end)
print(calls, ok, err)

-- The slots are gone for good: even a single cast fails now.
print(pcall(ffi.cast, "int (*)(const void *, const void *)", compare))
