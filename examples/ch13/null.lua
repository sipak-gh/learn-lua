-- NULL pointers are cdata, not nil.

local ffi = require("ffi")
ffi.cdef [[
char *getenv(const char *name);
]]

local p = ffi.C.getenv("STASH_NO_SUCH_VAR")
print(type(p), p == nil)        -- cdata, but compares equal to nil
print(not p)                    -- false: every cdata is "true" in an if!
if p then print("if p: taken, even though p is NULL") end

-- The safe test is an explicit comparison:
if p == nil then print("p == nil: NULL") end

-- A helper that turns a C string result into a Lua string or nil:
local function cstring(ptr)
  if ptr == nil then return nil end
  return ffi.string(ptr)
end
print(cstring(p), cstring(ffi.C.getenv("HOME")) ~= nil)

-- You can make a NULL pointer of any type yourself:
local q = ffi.new("int *")      -- pointers start out NULL
print(q == nil, ffi.cast("void *", 0) == nil)
