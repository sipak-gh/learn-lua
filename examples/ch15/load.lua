-- ffi.load opens a shared library and returns its namespace.
-- Declarations still come from ffi.cdef: the library has the code,
-- the cdef tells LuaJIT the types.

local ffi = require("ffi")

ffi.cdef [[
const char *sqlite3_libversion(void);
int sqlite3_libversion_number(void);
]]

local sqlite = ffi.load("sqlite3")           -- finds libsqlite3.so on Linux
print(sqlite)
print(ffi.string(sqlite.sqlite3_libversion()))
print(sqlite.sqlite3_libversion_number())

-- A name that doesn't exist: ffi.load raises an error.
print(pcall(ffi.load, "nosuchlib"))

-- A symbol that wasn't declared in a cdef: an error too.
print(pcall(function() return sqlite.sqlite3_sourceid end))
