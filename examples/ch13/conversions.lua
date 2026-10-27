-- How values cross between Lua and C.

local ffi = require("ffi")

-- 64-bit integers: the LL and ULL suffixes make int64_t / uint64_t cdata.
local big = 9007199254740993LL           -- 2^53 + 1: too big for a double
print(big, type(big), ffi.typeof(big))
print(("%.0f"):format(9007199254740993)) -- the same digits as a Lua number lose the 1
print(big + 1, big * 2)                  -- arithmetic stays 64-bit
print(-1ULL)                             -- unsigned wraps around
print(5LL / 2LL, 5LL % 3LL)              -- integer division

-- tonumber turns cdata numbers into Lua numbers (a double; may round).
print(tonumber(42LL), ("%.0f"):format(tonumber(big)))

-- Comparisons mix freely; table keys do not.
print(42LL == 42, 1LL < 2)
local t = { [42] = "number key" }
print(t[42LL])                           -- cdata is a different key

-- Lua -> C when calling a function with a declared type:
ffi.cdef [[
int abs(int n);
double fabs(double x);
]]
print(ffi.C.abs(-3.9))                   -- number -> int truncates toward 0
print(ffi.C.fabs(-3.9))
print(ffi.C.abs(true))                   -- a boolean becomes 1 or 0
print(pcall(ffi.C.abs, "7"))             -- strings are not converted to numbers
print(pcall(ffi.C.abs, nil))             -- nil is not a number

-- Results: small integers and doubles become Lua numbers,
-- 64-bit integers stay cdata, pointers stay cdata, bool becomes boolean.
local flags = ffi.new("bool[2]", true, false)
print(flags[0], flags[1], type(flags[0]))
