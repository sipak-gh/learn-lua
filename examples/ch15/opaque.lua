-- An opaque struct: declared, never defined. Lua can hold pointers to
-- it and pass them around, but cannot look inside or allocate one.

local ffi = require("ffi")

ffi.cdef [[
typedef struct sqlite3 sqlite3;
int sqlite3_open(const char *filename, sqlite3 **db);
int sqlite3_close(sqlite3 *db);
int sqlite3_get_autocommit(sqlite3 *db);
]]
local S = ffi.load("sqlite3")

print(ffi.sizeof("sqlite3"))                 -- unknown size
print(pcall(ffi.new, "sqlite3"))

-- ffi.metatype still works: methods for every `sqlite3 *`.
local Db = {}
Db.__index = Db
function Db:autocommit()
  return S.sqlite3_get_autocommit(self) == 1
end
ffi.metatype("sqlite3", Db)

local function open(path)
  local out = ffi.new("sqlite3 *[1]")
  assert(S.sqlite3_open(path, out) == 0)
  -- ffi.gc: when the pointer becomes garbage, run the finalizer.
  return ffi.gc(out[0], function(db)
    print("closing", db)
    S.sqlite3_close(db)
  end)
end

local db = open(":memory:")
print(db:autocommit())
db = nil
collectgarbage()                             -- the finalizer runs here
print("done")
