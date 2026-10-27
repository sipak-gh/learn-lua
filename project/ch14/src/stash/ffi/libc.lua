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

void *malloc(size_t size);
void *realloc(void *ptr, size_t size);
void free(void *ptr);

struct winsize {
  unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel;
};
int ioctl(int fd, unsigned long request, ...);
]]

local M = {}

-- #define constants don't exist for the FFI; we copy their values.
M.EEXIST = 17                                -- the same on Linux and macOS
M.TIOCGWINSZ = ffi.os == "OSX" and 0x40087468 or 0x5413   -- this one differs

-- The message for an errno value (default: the latest one).
function M.strerror(errnum)
  return ffi.string(ffi.C.strerror(errnum or ffi.errno()))
end

return M
