-- Binding parameters: values go into a prepared statement's ? and :name
-- slots, so user input is never pasted into SQL text.

local ffi = require("ffi")

ffi.cdef [[
typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;
int sqlite3_open(const char *filename, sqlite3 **db);
int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int nbytes,
                       sqlite3_stmt **stmt, const char **tail);
int sqlite3_bind_parameter_index(sqlite3_stmt *stmt, const char *name);
int sqlite3_bind_int64(sqlite3_stmt *stmt, int i, int64_t value);
int sqlite3_bind_text(sqlite3_stmt *stmt, int i, const char *text, int nbytes,
                      void (*destructor)(void *));
int sqlite3_step(sqlite3_stmt *stmt);
const unsigned char *sqlite3_column_text(sqlite3_stmt *stmt, int i);
int sqlite3_finalize(sqlite3_stmt *stmt);
]]
local S = ffi.load("sqlite3")

-- sqlite3.h: #define SQLITE_TRANSIENT ((sqlite3_destructor_type)-1)
-- "-1 cast to a function pointer" means: copy the bytes now.
local TRANSIENT = ffi.cast("void (*)(void *)", -1)
print(TRANSIENT)

local pdb = ffi.new("sqlite3 *[1]")
S.sqlite3_open(":memory:", pdb)
local db = pdb[0]

local sql = "SELECT ?1 || ' is ' || :age || ' years old'"
local pstmt = ffi.new("sqlite3_stmt *[1]")
S.sqlite3_prepare_v2(db, sql, #sql, pstmt, nil)
local stmt = pstmt[0]

local name = "Lua's " .. "mascot"            -- a quote: no problem for a parameter
S.sqlite3_bind_text(stmt, 1, name, #name, TRANSIENT)
local age = S.sqlite3_bind_parameter_index(stmt, ":age")
print("index of :age", age)
S.sqlite3_bind_int64(stmt, age, 33)          -- a Lua number converts to int64_t
S.sqlite3_step(stmt)
print(ffi.string(S.sqlite3_column_text(stmt, 0)))
S.sqlite3_finalize(stmt)
