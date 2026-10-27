-- The raw SQLite C API, called straight from Lua. Every call is C:
-- return codes, out parameters, pointers, manual cleanup.

local ffi = require("ffi")

ffi.cdef [[
typedef struct sqlite3 sqlite3;               /* opaque: only pointers */
typedef struct sqlite3_stmt sqlite3_stmt;
enum { SQLITE_OK = 0, SQLITE_ROW = 100, SQLITE_DONE = 101 };

int sqlite3_open(const char *filename, sqlite3 **db);
int sqlite3_close(sqlite3 *db);
const char *sqlite3_errmsg(sqlite3 *db);
int sqlite3_exec(sqlite3 *db, const char *sql, void *callback, void *arg, char **errmsg);
int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int nbytes,
                       sqlite3_stmt **stmt, const char **tail);
int sqlite3_step(sqlite3_stmt *stmt);
int64_t sqlite3_column_int64(sqlite3_stmt *stmt, int i);
const unsigned char *sqlite3_column_text(sqlite3_stmt *stmt, int i);
int sqlite3_finalize(sqlite3_stmt *stmt);
]]

local S = ffi.load("sqlite3")

-- sqlite3_open(const char *, sqlite3 **): the second argument is an out
-- parameter. A one-element array of pointers gives C somewhere to write.
local pdb = ffi.new("sqlite3 *[1]")
assert(S.sqlite3_open(":memory:", pdb) == S.SQLITE_OK)
local db = pdb[0]
print("db:", db)

assert(S.sqlite3_exec(db, [[
  CREATE TABLE langs (name TEXT, year INTEGER);
  INSERT INTO langs VALUES ('Lua', 1993), ('C', 1972);
]], nil, nil, nil) == S.SQLITE_OK)

local pstmt = ffi.new("sqlite3_stmt *[1]")
local sql = "SELECT name, year FROM langs ORDER BY year"
assert(S.sqlite3_prepare_v2(db, sql, #sql, pstmt, nil) == S.SQLITE_OK)
local stmt = pstmt[0]
while S.sqlite3_step(stmt) == S.SQLITE_ROW do     -- columns count from 0
  local name = ffi.string(S.sqlite3_column_text(stmt, 0))
  local year = S.sqlite3_column_int64(stmt, 1)
  print(name, year, tonumber(year))
end
S.sqlite3_finalize(stmt)

-- Errors are return codes; the message comes from sqlite3_errmsg.
local rc = S.sqlite3_prepare_v2(db, "SELEKT 1", -1, pstmt, nil)
print(rc, ffi.string(S.sqlite3_errmsg(db)))

S.sqlite3_close(db)
