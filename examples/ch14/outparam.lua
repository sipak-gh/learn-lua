-- Out parameters: C returns extra results by writing through a pointer.

local ffi = require("ffi")
ffi.cdef [[
long strtol(const char *s, char **endptr, int base);
]]

-- strtol(s, &end, base) parses a number and sets *end to the first
-- character it did not use. In Lua, a one-element array plays "&end".
local function parse_int(s, base)
  local endp = ffi.new("char *[1]")
  local n = ffi.C.strtol(s, endp, base or 10)
  -- endp[0] points into s; subtracting gives how many bytes were used.
  local used = endp[0] - ffi.cast("const char *", s)
  return tonumber(n), s:sub(used + 1)
end

print(parse_int("42 apples"))
print(parse_int("ff", 16))
print(parse_int("0x1F", 16))
print(parse_int("nope"))

-- The same idea with an int: let C fill it.
ffi.cdef [[
int sscanf(const char *s, const char *format, ...);
]]
local w, h = ffi.new("int[1]"), ffi.new("int[1]")
local count = ffi.C.sscanf("1920x1080", "%dx%d", w, h)
print(count, w[0], h[0])
