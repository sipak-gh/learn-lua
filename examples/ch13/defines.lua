-- C headers are full of #define constants. The FFI's C parser has no
-- preprocessor, so you bring the values over yourself.

local ffi = require("ffi")

-- This fails: cdef only understands declarations.
print(pcall(ffi.cdef, "#define EEXIST 17"))

-- Option 1: a plain Lua constant.
local O_RDONLY = 0

-- Option 2: an enum. Its constants live in ffi.C and are typed.
ffi.cdef [[
enum { SEEK_SET = 0, SEEK_CUR = 1, SEEK_END = 2 };
]]
print("enum:", ffi.C.SEEK_END)

-- Option 3: a static const. Also reachable through ffi.C.
ffi.cdef [[
static const int EEXIST = 17;
]]
print("static const:", ffi.C.EEXIST)

-- Enums also give names to a C type's values:
ffi.cdef [[
typedef enum { RED, GREEN = 5, BLUE } color;
]]
local c = ffi.new("color", "BLUE")    -- a string converts to the enum value
print("color:", tonumber(c), c == ffi.C.BLUE, ffi.C.GREEN)
print("lua const:", O_RDONLY)
