-- Raw bindings to the few C library functions stash uses. ffi.cdef takes
-- plain C declarations, copied from the system headers; ffi.C is the C
-- library itself, already loaded into every process.

local ffi = require("ffi")

-- mode_t is a typedef whose size depends on the platform, so we declare it
-- before the functions that use it.
if ffi.os == "OSX" then
  ffi.cdef("typedef uint16_t mode_t;")
else
  ffi.cdef("typedef uint32_t mode_t;")
end

ffi.cdef [[
int isatty(int fd);
int mkdir(const char *path, mode_t mode);
char *strerror(int errnum);
]]

local M = {}

-- #define constants don't exist for the FFI; we copy their values.
M.EEXIST = 17                                -- the same on Linux and macOS

-- The message for an errno value (default: the latest one).
function M.strerror(errnum)
  return ffi.string(ffi.C.strerror(errnum or ffi.errno()))
end

return M
