-- A few everyday libc functions.

local ffi = require("ffi")

ffi.cdef [[
size_t strlen(const char *s);
char *getenv(const char *name);
int getpid(void);
typedef long time_t;
time_t time(time_t *t);
int abs(int n);
double floor(double x);
]]

local C = ffi.C

-- A Lua string is passed as a const char* to its bytes.
local len = C.strlen("hello")
print("strlen:", len, type(len), tonumber(len))

-- getenv returns a char*. ffi.string copies the C string into a Lua string.
local home = C.getenv("HOME")
print("getenv:", type(home), ffi.string(home) == os.getenv("HOME"))

-- A missing variable gives a NULL pointer.
local missing = C.getenv("STASH_NO_SUCH_VAR")
print("NULL:", missing, missing == nil)

print("getpid:", type(C.getpid()))   -- int results arrive as Lua numbers
print("time:", C.time(nil) - os.time() <= 1)
print("abs:", C.abs(-42), "floor:", C.floor(2.7))
