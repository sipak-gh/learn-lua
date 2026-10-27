-- FFI calls are compiled by the JIT into direct machine-code calls.

local ffi = require("ffi")
ffi.cdef [[
int abs(int n);
]]
local C = ffi.C

local sum = 0
for i = 1, 1e7 do
  sum = sum + C.abs(-i)       -- one C call per iteration
end
print(sum)
