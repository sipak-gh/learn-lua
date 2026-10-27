# Chapter 15 — Wrapping SQLite

SQLite is a full SQL database in one C library. With the FFI, Lua calls it directly: no binding
library, no C glue. This chapter turns `sqlite3.h` into a cdef and builds a small Lua API on top.
`stash` moves from a Lua file to a real database with full-text search. You'll use cdefs, out
parameters, `ffi.metatype` and `ffi.gc` from [Chapter 13](13-ffi-basics.md) and
[Chapter 14](14-c-data.md). Callbacks (C calling Lua) come in [Chapter 16](16-callbacks-and-curl.md).

## Loading a library with `ffi.load`

`ffi.C` only sees the C library and what's linked into `luajit`. Other libraries must be loaded:
`ffi.load(name)` opens a shared library and returns a **namespace**, which you index like `ffi.C`.

`examples/ch15/load.lua`

```lua
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
```

```console
$ luajit examples/ch15/load.lua
userdata: 0x7dfb2212b630
3.37.2
3037002
false	libnosuchlib.so: cannot open shared object file: No such file or directory
false	examples/ch15/load.lua:21: missing declaration for symbol 'sqlite3_sourceid'
```

The address on the first line changes every run.

- The library has the code; the cdef has the types. You need both.
- A missing library or an undeclared symbol is a normal Lua error, so `pcall` catches it.
- `3037002` is version 3.37.2 as a number.

### Library names and sonames

On Linux, `ffi.load("sqlite3")` adds `lib` and `.so` and asks the system loader for
`libsqlite3.so`. A name with a dot, or a full path, is used as is.

That unversioned `libsqlite3.so` is a symlink that usually comes only with the **development**
package. Every install has the versioned **soname**, `libsqlite3.so.0`, whose number changes only
when binary compatibility breaks. So a program that must run without the dev package tries both:

```lua
local ok, lib = pcall(ffi.load, "sqlite3")
if not ok then
  lib = ffi.load("libsqlite3.so.0")
end
```

| library | short name | soname (Linux) |
|---------|------------|----------------|
| SQLite  | `sqlite3`  | `libsqlite3.so.0` |
| libcurl | `curl`     | `libcurl.so.4` |
| zlib    | `z`        | `libz.so.1` |

macOS uses `.dylib`, Windows `.dll`; `ffi.os` (Chapter 13) tells you which system you're on.

`ffi.load(name, true)` also puts the library's symbols in the global namespace, so `ffi.C` sees them.
You rarely want that; keep the namespace in a local.

## Translating a header into a cdef

A cdef is C declarations copied from the header, but only the ones you call. `sqlite3.h` is about
12,500 lines; `stash` needs a few dozen.

`examples/ch15/raw.lua`

```lua
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
```

```console
$ luajit examples/ch15/raw.lua
db:	cdata<struct sqlite3 *>: 0x56ed34b85498
C	1972LL	1972
Lua	1993LL	1993
1	near "SELEKT": syntax error
```

Translation rules:

| In the header | In the cdef |
|---------------|-------------|
| `typedef struct sqlite3 sqlite3;` | the same: an **opaque** type |
| `#define SQLITE_ROW 100` | an `enum { SQLITE_ROW = 100 }`; the FFI has no preprocessor |
| `SQLITE_API int sqlite3_step(sqlite3_stmt*);` | `int sqlite3_step(sqlite3_stmt *stmt);` (drop the macro) |
| `sqlite3_int64` | `int64_t` (it's a `long long`) |
| `const void *` / `const char *` | the same; Lua strings convert to them |

Constants in an `enum` become namespace fields: `S.SQLITE_ROW` is the number `100`. Parameter names
are optional but document the cdef.

In the output:

- `sqlite3_column_int64` returns `int64_t`: cdata that prints as `1972LL`. `tonumber()` makes it a
  plain number. Do that before using it as a table key, comparing it with a string or formatting it
  with `%d`.
- Columns count from 0; SQL `?` parameters count from 1. Both are SQLite's rules.
- A failing call returns a code (`1` = `SQLITE_ERROR`). `sqlite3_errmsg(db)` gives the message.

### Opaque handles

`typedef struct sqlite3 sqlite3;` declares a struct with no body. You can't allocate one or read its
fields, but you can hold pointers, pass them back to SQLite and attach methods. C hides internals
this way, and it suits the FFI well.

`examples/ch15/opaque.lua`

```lua
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
```

```console
$ luajit examples/ch15/opaque.lua
nil
false	bad argument #1 to '?' (size of C type is unknown or too large)
true
closing	cdata<struct sqlite3 *>: 0x64411e3f24a8
done
```

(Addresses change every run.)

- `ffi.sizeof` returns `nil` and `ffi.new` fails: the size is unknown.
- `ffi.metatype` still works. Its methods apply to **pointers** to the struct, all you ever have.
- `ffi.gc(ptr, finalizer)` ties the C object to the garbage collector: when the pointer becomes
  garbage, the finalizer (a Lua function or a C one like `S.sqlite3_close`) runs.

### Out parameters

Many C functions return a status code and write the result through a pointer:
`int sqlite3_open(const char *, sqlite3 **db)`. `ffi.new("sqlite3 *[1]")` is a one-element pointer
array that converts to `sqlite3 **`; after the call, `[0]` holds the result. The wrapper uses this
[Chapter 14](14-c-data.md) idiom everywhere.

## Binding parameters and `SQLITE_TRANSIENT`

Never paste user input into SQL text. Write `?` or `:name` placeholders, prepare once, then **bind**
values. No quoting problems, no SQL injection.

`examples/ch15/bind.lua`

```lua
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
```

```console
$ luajit examples/ch15/bind.lua
cdata<void (*)()>: 0xffffffffffffffff
index of :age	2
Lua's mascot is 33 years old
```

The last argument of `sqlite3_bind_text` says who owns the bytes:

- `SQLITE_STATIC` (`0`, or `nil` from Lua): they stay valid until the statement is done; don't copy.
- `SQLITE_TRANSIENT` (`-1`): copy them now.
- a real function: call it to free them later.

In C these are macros: `#define SQLITE_TRANSIENT ((sqlite3_destructor_type)-1)`. A cdef can't hold
that, so cast -1 to a function pointer: `ffi.cast("void (*)(void *)", -1)`.

Always use `TRANSIENT` for Lua strings. A Lua string passed to C is only guaranteed to live during
the call (Chapter 14), and the statement runs later; with `STATIC`, SQLite could read freed memory.

`sqlite3_bind_parameter_index(stmt, ":age")` turns a name into a slot number. Unbound parameters are
`NULL`.

## A two-layer design

The raw API works, but every call site would repeat the chores (check the code, fetch the message,
convert cdata, finalize). So use two layers:

| Layer | Module | Contains |
|-------|--------|----------|
| raw bindings | `stash.ffi.sqlite` | the cdef and `ffi.load`, nothing else; returns the namespace |
| wrapper | `stash.db` | `Db` and `Stmt` objects with Lua-style methods |

The wrapper's rules:

- **Lua values in, Lua values out.** Callers pass strings, numbers and tables and get tables of plain
  values back. No cdata leaks out except the `Db` handle.
- **Errors are Lua errors** with SQLite's message, not return codes.
- **The wrapper owns cleanup.** `ffi.gc` closes what callers forget.

Only `stash.db` requires `stash.ffi.sqlite`, so if SQLite changes, or you port to another platform,
two files change. Everything else talks to `Db`.

From here on the examples use `stash.db` (full code in
[Building stash](#building-stash-sqlite-storage-and-full-text-search) below). First, what it buys you:

`examples/ch15/wrapper.lua`

```lua
-- The same work as raw.lua, through stash's wrapper (stash.db).
-- Run from the course root: the wrapper lives in project/ch15/src.
package.path = "project/ch15/src/?.lua;" .. package.path

local Db = require("stash.db")

local db = assert(Db.open(":memory:"))
db:exec("CREATE TABLE langs (name TEXT, year INTEGER, note TEXT)")
db:run("INSERT INTO langs VALUES (?, ?, ?)", { "Lua", 1993, "small" })
db:run("INSERT INTO langs (name, year) VALUES (:name, :year)", { name = "C", year = 1972 })
print("last id", db:last_id())

for row in db:rows("SELECT * FROM langs ORDER BY year") do
  print(row.name, row.year, row.note)        -- plain Lua values; NULL is nil
end
print(db:first("SELECT count(*) AS n FROM langs").n)

-- SQLite's error message, raised as a Lua error.
print(pcall(db.first, db, "SELECT nope FROM langs"))
db:close()
```

```console
$ luajit examples/ch15/wrapper.lua
last id	2
C	1972	nil
Lua	1993	small
2
false	database: no such column: nope
```

Compared with `raw.lua`: no out parameters, `ffi.string`, `tonumber` or return codes.

### Methods on C pointers

`Db` and `Stmt` are plain method tables, attached to the opaque structs with `ffi.metatype`:

```lua
local Db = {}
Db.__index = Db
local Stmt = {}
Stmt.__index = Stmt

-- Methods for pointers to these (opaque) structs.
ffi.metatype("struct sqlite3", Db)
ffi.metatype("struct sqlite3_stmt", Stmt)

-- SQLITE_TRANSIENT is ((void(*)(void*))-1) in sqlite3.h: it tells SQLite
-- to copy our string, which is only guaranteed to live during the call.
local TRANSIENT = ffi.cast("void (*)(void *)", -1)
```

Every `sqlite3 *` now has `Db`'s methods, even the one `sqlite3_db_handle(stmt)` returns;
`Stmt:db()` uses it to find a statement's database.

### Ownership with `ffi.gc`

```lua
-- Opens (creating if needed) a database file; ":memory:" is a database
-- that lives only in memory. Returns the handle, or nil and a message.
function Db.open(path)
  local out = ffi.new("sqlite3 *[1]")        -- an out parameter: sqlite3 **
  local rc = S.sqlite3_open_v2(path, out, S.SQLITE_OPEN_READWRITE + S.SQLITE_OPEN_CREATE, nil)
  local db = out[0]
  if rc ~= S.SQLITE_OK then
    -- Even a failed open allocates a handle (unless out of memory).
    local message = db ~= nil and ffi.string(S.sqlite3_errmsg(db)) or "out of memory"
    S.sqlite3_close_v2(db)
    return nil, ("cannot open %s: %s"):format(path, message)
  end
  S.sqlite3_busy_timeout(db, 2000)           -- wait for other writers up to 2 s
  return ffi.gc(db, S.sqlite3_close_v2)
end

function Db:close()
  ffi.gc(self, nil)                          -- no finalizer: we close it now
  S.sqlite3_close_v2(self)
end
```

- `sqlite3_open_v2` takes flags: read-write, create if needed.
- Even a failed open usually returns a handle holding the error message. It must be closed.
- `ffi.gc(db, S.sqlite3_close_v2)` returns the same pointer with a finalizer, so the GC closes a
  dropped handle.
- `Db:close()` first removes the finalizer with `ffi.gc(self, nil)`; otherwise the GC would close it
  again (a double free).

Why `sqlite3_close_v2`? The GC finalizes in no set order and may close a database before its
statements. `sqlite3_close` then refuses (`SQLITE_BUSY`) and the connection leaks; `sqlite3_close_v2`
frees it after the last statement is finalized. Statements get `ffi.gc(stmt, S.sqlite3_finalize)`.

### Turning return codes into errors

```lua
-- Raises an error with SQLite's message for the latest failure.
function Db:check(rc)
  if rc ~= S.SQLITE_OK then
    errors.fail("database: %s", ffi.string(S.sqlite3_errmsg(self)))
  end
end
```

`errors.fail` raises the error table from [Chapter 9](09-errors.md): a database problem becomes
`stash: database: ...` with exit code 2. `Db:check` is a method on a C pointer, called as
`self:check(rc)`.

`sqlite3_exec` runs SQL without parameters. On failure it **allocates** the message, so the wrapper
copies it with `ffi.string` and frees it with `sqlite3_free`. Whoever allocates, frees; a C library's
docs say who.

### Rows as Lua tables, through an iterator

```lua
-- Iterates over the rows of a query, each one a table keyed by column name.
function Db:rows(sql, params)
  local stmt = self:prepare(sql):bind(params)
  return function()
    if stmt:step() then
      return stmt:row()
    end
    stmt:finalize()
  end
end
```

A stateful iterator ([Chapter 11](11-coroutines.md)) closing over the statement. `Stmt:step()`
returns `true` per row and `false` at the end, where the iterator finalizes the statement and returns
nothing, ending the `for` loop.

`Stmt:row()` reads each column by type into a table keyed by name: `INTEGER` → `tonumber(int64)`,
`FLOAT` → number, `TEXT` → `ffi.string(ptr, len)`. `NULL` columns are left out (they read as `nil`).
Pass the length: text may contain zero bytes.

If a loop `break`s early, the statement isn't finalized right away; `ffi.gc` finalizes it later.

### Binding by table

`Stmt:bind(params)` walks the table with `pairs`. Number keys (`params[1]`) go to `?1`, string keys
(`params.name`) to `:name`. Whole numbers below 2^53 bind as `int64`, other numbers as `double`,
strings as text with `TRANSIENT`, booleans as 0 or 1. Anything else is an error.

### Transactions with `pcall`

```lua
-- Runs fn() in a transaction: all its changes happen, or none do.
function Db:transaction(fn, ...)
  self:exec("BEGIN")
  local ok, err = pcall(fn, ...)
  if not ok then
    self:exec("ROLLBACK")
    error(err, 0)                            -- re-raise, unchanged
  end
  self:exec("COMMIT")
end
```

`examples/ch15/transaction.lua`

```lua
-- A transaction is all or nothing. Db:transaction(fn) runs fn inside
-- BEGIN ... COMMIT, and rolls back if fn raises an error.
package.path = "project/ch15/src/?.lua;" .. package.path

local Db = require("stash.db")
local db = assert(Db.open(":memory:"))
db:exec("CREATE TABLE accounts (name TEXT PRIMARY KEY, balance INTEGER)")
db:run("INSERT INTO accounts VALUES ('ann', 100), ('bob', 0)")

local function transfer(from, to, amount)
  db:transaction(function()
    db:run("UPDATE accounts SET balance = balance + ? WHERE name = ?", { amount, to })
    local row = db:first("SELECT balance FROM accounts WHERE name = ?", { from })
    if row.balance < amount then
      error("not enough money", 0)           -- after bob was already paid!
    end
    db:run("UPDATE accounts SET balance = balance - ? WHERE name = ?", { amount, from })
  end)
end

local function show()
  local parts = {}
  for row in db:rows("SELECT * FROM accounts ORDER BY name") do
    parts[#parts + 1] = row.name .. "=" .. row.balance
  end
  print(table.concat(parts, " "))
end

transfer("ann", "bob", 30)
show()
print(pcall(transfer, "ann", "bob", 500))
show()                                       -- bob's +500 was rolled back

-- BEGIN does not nest: a transaction inside a transaction fails.
print(pcall(db.transaction, db, function() db:transaction(function() end) end))
```

```console
$ luajit examples/ch15/transaction.lua
ann=70 bob=30
false	not enough money
ann=70 bob=30
false	database: cannot start a transaction within a transaction
```

- `pcall` catches any error in `fn`; the wrapper rolls back and re-raises with `error(err, 0)` (level
  0 adds no position).
- Transactions are also fast: outside one, SQLite commits (and syncs the disk) after every statement.
- `BEGIN` doesn't nest (last line). [Chapter 18](18-performance-and-the-jit.md) fixes this with
  savepoints.

## Full-text search with FTS5

FTS5 is SQLite's full-text search extension. A `CREATE VIRTUAL TABLE ... USING fts5(...)` table
looks like a table, but SQLite keeps an index of every word behind it.

`examples/ch15/fts5.lua`

```lua
-- Full-text search with SQLite's FTS5 extension.
package.path = "project/ch15/src/?.lua;" .. package.path

local Db = require("stash.db")
local db = assert(Db.open(":memory:"))

-- A virtual table: SQLite keeps an inverted index of every word.
db:exec("CREATE VIRTUAL TABLE docs USING fts5(title, body)")
local docs = {
  { "Lua", "Lua is a small scripting language. Tables are its only data structure." },
  { "LuaJIT", "LuaJIT is a tracing JIT compiler for Lua, with an FFI for C." },
  { "SQLite", "SQLite is a C library. FTS5 adds full-text search to SQLite tables." },
}
for _, d in ipairs(docs) do
  db:run("INSERT INTO docs (title, body) VALUES (?, ?)", d)
end

local function search(query)
  print("-- " .. query)
  local ok, err = pcall(function()
    for row in db:rows([[
        SELECT title, snippet(docs, 1, '[', ']', '...', 6) AS snip
        FROM docs WHERE docs MATCH ? ORDER BY rank]], { query }) do
      print(row.title, row.snip)
    end
  end)
  if not ok then print(err) end
end

search("tables")                 -- words, case-insensitive; rank = best first
search("lua c")                  -- every word must appear
search("compil*")                -- prefix query
search("title:sqlite")           -- a column filter
search("c++")                    -- user input is FTS5 syntax...
search('"c++"')                  -- ...unless you quote it
```

```console
$ luajit examples/ch15/fts5.lua
-- tables
Lua	...scripting language. [Tables] are its only...
SQLite	...full-text search to SQLite [tables].
-- lua c
LuaJIT	...[Lua], with an FFI for [C].
-- compil*
LuaJIT	LuaJIT is a tracing JIT [compiler]...
-- title:sqlite
SQLite	SQLite is a C library. FTS5...
-- c++
database: fts5: syntax error near "+"
-- "c++"
LuaJIT	...Lua, with an FFI for [C].
SQLite	SQLite is a [C] library. FTS5...
```

- `docs MATCH ?` finds rows containing **every** query word, ignoring case.
- `ORDER BY rank` puts the best matches first (BM25 by default).
- `snippet(docs, col, before, after, ellipsis, n)` returns about `n` words around the match, marked.
  Column `-1` picks the best column.
- A trailing `*` is a prefix query; `title:` limits the search to one column.

The last two queries show the gotcha: the query is a small language, so input like `c++`, `-x` or
`a:b` is a syntax error or means something else. Quote each word; inside double quotes every word is
plain text (write `""` for a quote). `stash` quotes each word and keeps a trailing `*`.

FTS5 must be compiled into your SQLite (most Linux distributions do).
`SELECT sqlite_compileoption_used('ENABLE_FTS5')` returns 1 if it is.

## Migrations: the schema as a Lua array

Schemas change, but users already have databases with the old one. **Migrations** fix this: an
array of SQL scripts, run in order, each exactly once.

`examples/ch15/migrate.lua`

```lua
-- Schema migrations: a Lua array of SQL strings. The database records
-- how many it has run in PRAGMA user_version (an integer SQLite keeps
-- in the file header for applications to use).
package.path = "project/ch15/src/?.lua;" .. package.path

local Db = require("stash.db")

local MIGRATIONS = {
  "CREATE TABLE notes (id INTEGER PRIMARY KEY, text TEXT NOT NULL)",
}

local function migrate(db)
  local version = db:first("PRAGMA user_version").user_version
  for i = version + 1, #MIGRATIONS do
    db:transaction(function()
      db:exec(MIGRATIONS[i])
      db:exec("PRAGMA user_version = " .. i)
    end)
    print("ran migration " .. i)
  end
end

local db = assert(Db.open(":memory:"))
migrate(db)                                  -- runs 1
migrate(db)                                  -- nothing to do

-- A later release appends a migration; old databases catch up.
MIGRATIONS[2] = "ALTER TABLE notes ADD COLUMN created INTEGER NOT NULL DEFAULT 0"
migrate(db)                                  -- runs 2 only
print(db:first("PRAGMA user_version").user_version)
for row in db:rows("PRAGMA table_info(notes)") do
  print(row.cid, row.name, row.type)
end
```

```console
$ luajit examples/ch15/migrate.lua
ran migration 1
ran migration 2
2
0	id	INTEGER
1	text	TEXT
2	created	INTEGER
```

- `PRAGMA user_version` is a header number SQLite leaves to applications; here it counts migrations
  run.
- Each migration and its version bump run in one transaction, so a failure leaves the previous
  version, not a half-changed database.
- Never edit a shipped migration; append a new one.

Migrations are data: a Lua array of strings and a six-line loop.

## Building stash: SQLite storage and full-text search

Since [Chapter 12](12-io-and-os.md), `stash` has kept bookmarks in `$STASH_HOME/entries.lua`. Now
they move into `$STASH_HOME/stash.db`:

- `add` also stores the page **text** in an FTS5 index.
- `search WORDS...` is a full-text search, best matches first, with a snippet under each hit.
- tags get their own table, so `list -t` and `tags` are SQL queries.

The new layers:

```text
commands  ->  Store (store.lua)  ->  Db (db.lua)  ->  stash.ffi.sqlite  ->  libsqlite3
```

`stash` starts with a fresh database and doesn't import an old `entries.lua`; delete it if you have
one. A lot of code moves, so we go file by file.

### Remove the old store

`MemoryStore`, `FileStore`, the serializer and their tests go:

```console
$ rm src/stash/memstore.lua src/stash/filestore.lua src/stash/serialize.lua
$ rm test/memstore_test.lua test/filestore_test.lua
```

### `src/stash/ffi/load.lua` (new)

Tries several library names, for the soname reason above:

```lua
-- Loads a shared C library, trying several names in turn.
--
-- ffi.load("sqlite3") looks for libsqlite3.so (Linux) or libsqlite3.dylib
-- (macOS). On Linux that unversioned name often comes only with the
-- development package, so we also try the versioned name ("soname")
-- that every installed copy has: libsqlite3.so.0.

local ffi = require("ffi")

return function(names)
  local problems = {}
  for _, name in ipairs(names) do
    local ok, lib = pcall(ffi.load, name)
    if ok then
      return lib
    end
    problems[#problems + 1] = lib
  end
  error("cannot load C library: " .. table.concat(problems, "; "), 2)
end
```

`error(..., 2)` blames the caller: the module that asked for the library.

### `src/stash/ffi/sqlite.lua` (new)

The raw bindings: declarations and the load, nothing else:

```lua
-- Raw bindings to SQLite: declarations copied from sqlite3.h (only the
-- parts stash uses) and the loaded library. stash.db builds a friendlier
-- API on top; nothing else should need this module.

local ffi = require("ffi")
local load = require("stash.ffi.load")

ffi.cdef [[
/* Opaque types: we only ever hold pointers to them. */
typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;

/* #defines from sqlite3.h, as an enum the FFI understands. */
enum {
  SQLITE_OK = 0,
  SQLITE_ROW = 100,
  SQLITE_DONE = 101,

  SQLITE_OPEN_READWRITE = 0x00000002,
  SQLITE_OPEN_CREATE = 0x00000004,

  SQLITE_INTEGER = 1,
  SQLITE_FLOAT = 2,
  SQLITE_TEXT = 3,
  SQLITE_BLOB = 4,
  SQLITE_NULL = 5,
};

const char *sqlite3_libversion(void);

int sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs);
int sqlite3_close_v2(sqlite3 *db);
const char *sqlite3_errmsg(sqlite3 *db);
int sqlite3_busy_timeout(sqlite3 *db, int ms);
int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void *, int, char **, char **), void *arg,
                 char **errmsg);
void sqlite3_free(void *ptr);
int sqlite3_changes(sqlite3 *db);
int64_t sqlite3_last_insert_rowid(sqlite3 *db);

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int nbytes,
                       sqlite3_stmt **stmt, const char **tail);
sqlite3 *sqlite3_db_handle(sqlite3_stmt *stmt);
int sqlite3_bind_parameter_index(sqlite3_stmt *stmt, const char *name);
int sqlite3_bind_int64(sqlite3_stmt *stmt, int i, int64_t value);
int sqlite3_bind_double(sqlite3_stmt *stmt, int i, double value);
int sqlite3_bind_text(sqlite3_stmt *stmt, int i, const char *text, int nbytes,
                      void (*destructor)(void *));
int sqlite3_bind_null(sqlite3_stmt *stmt, int i);
int sqlite3_step(sqlite3_stmt *stmt);
int sqlite3_reset(sqlite3_stmt *stmt);
int sqlite3_finalize(sqlite3_stmt *stmt);

int sqlite3_column_count(sqlite3_stmt *stmt);
const char *sqlite3_column_name(sqlite3_stmt *stmt, int i);
int sqlite3_column_type(sqlite3_stmt *stmt, int i);
int64_t sqlite3_column_int64(sqlite3_stmt *stmt, int i);
double sqlite3_column_double(sqlite3_stmt *stmt, int i);
const unsigned char *sqlite3_column_text(sqlite3_stmt *stmt, int i);
int sqlite3_column_bytes(sqlite3_stmt *stmt, int i);
]]

return load({ "sqlite3", "libsqlite3.so.0" })
```

`sqlite3_exec` takes a callback (a function pointer); `stash` passes `nil` (callbacks are Chapter 16).
`require` caches modules, so this cdef runs once per process. That matters: redeclaring a struct is
an error (`attempt to redefine`).

### `src/stash/db.lua` (new)

The wrapper described above, in full:

```lua
-- A small, Lua-flavored SQLite API on top of the raw bindings.
--
--   local db = Db.open("stash.db")
--   db:run("INSERT INTO t(a, b) VALUES (?, :b)", { 1, b = "two" })
--   for row in db:rows("SELECT a, b FROM t") do print(row.a, row.b) end
--
-- Database handles and statements are C pointers with methods attached
-- by ffi.metatype, and ffi.gc closes them if we forget to.

local ffi = require("ffi")
local errors = require("stash.errors")
local S = require("stash.ffi.sqlite")

local Db = {}
Db.__index = Db
local Stmt = {}
Stmt.__index = Stmt

-- Methods for pointers to these (opaque) structs.
ffi.metatype("struct sqlite3", Db)
ffi.metatype("struct sqlite3_stmt", Stmt)

-- SQLITE_TRANSIENT is ((void(*)(void*))-1) in sqlite3.h: it tells SQLite
-- to copy our string, which is only guaranteed to live during the call.
local TRANSIENT = ffi.cast("void (*)(void *)", -1)

function Db.version()
  return ffi.string(S.sqlite3_libversion())
end

-- Raises an error with SQLite's message for the latest failure.
function Db:check(rc)
  if rc ~= S.SQLITE_OK then
    errors.fail("database: %s", ffi.string(S.sqlite3_errmsg(self)))
  end
end

-- Opens (creating if needed) a database file; ":memory:" is a database
-- that lives only in memory. Returns the handle, or nil and a message.
function Db.open(path)
  local out = ffi.new("sqlite3 *[1]")        -- an out parameter: sqlite3 **
  local rc = S.sqlite3_open_v2(path, out, S.SQLITE_OPEN_READWRITE + S.SQLITE_OPEN_CREATE, nil)
  local db = out[0]
  if rc ~= S.SQLITE_OK then
    -- Even a failed open allocates a handle (unless out of memory).
    local message = db ~= nil and ffi.string(S.sqlite3_errmsg(db)) or "out of memory"
    S.sqlite3_close_v2(db)
    return nil, ("cannot open %s: %s"):format(path, message)
  end
  S.sqlite3_busy_timeout(db, 2000)           -- wait for other writers up to 2 s
  return ffi.gc(db, S.sqlite3_close_v2)
end

function Db:close()
  ffi.gc(self, nil)                          -- no finalizer: we close it now
  S.sqlite3_close_v2(self)
end

-- Runs one or more SQL statements that take no parameters.
function Db:exec(sql)
  local errmsg = ffi.new("char *[1]")
  if S.sqlite3_exec(self, sql, nil, nil, errmsg) ~= S.SQLITE_OK then
    local message = ffi.string(errmsg[0])
    S.sqlite3_free(errmsg[0])                -- SQLite allocated it; SQLite frees it
    errors.fail("database: %s", message)
  end
end

-- Compiles one SQL statement.
function Db:prepare(sql)
  local out = ffi.new("sqlite3_stmt *[1]")
  self:check(S.sqlite3_prepare_v2(self, sql, #sql, out, nil))
  return ffi.gc(out[0], S.sqlite3_finalize)
end

-- Runs a statement that returns no rows; returns the number of rows changed.
function Db:run(sql, params)
  local stmt = self:prepare(sql):bind(params)
  stmt:step()
  stmt:finalize()
  return S.sqlite3_changes(self)
end

-- Iterates over the rows of a query, each one a table keyed by column name.
function Db:rows(sql, params)
  local stmt = self:prepare(sql):bind(params)
  return function()
    if stmt:step() then
      return stmt:row()
    end
    stmt:finalize()
  end
end

-- The first row of a query, or nil.
function Db:first(sql, params)
  local stmt = self:prepare(sql):bind(params)
  local row = stmt:step() and stmt:row() or nil
  stmt:finalize()
  return row
end

-- The id of the row most recently inserted.
function Db:last_id()
  return tonumber(S.sqlite3_last_insert_rowid(self))  -- int64_t arrives as cdata
end

-- Runs fn() in a transaction: all its changes happen, or none do.
function Db:transaction(fn, ...)
  self:exec("BEGIN")
  local ok, err = pcall(fn, ...)
  if not ok then
    self:exec("ROLLBACK")
    error(err, 0)                            -- re-raise, unchanged
  end
  self:exec("COMMIT")
end

-- Binds parameters: params[1] goes to ?1 (or the first ?), and
-- params.name goes to :name. Parameters not given stay NULL.
function Stmt:bind(params)
  for key, value in pairs(params or {}) do
    local index = key
    if type(key) == "string" then
      index = S.sqlite3_bind_parameter_index(self, ":" .. key)
      if index == 0 then
        error("no parameter :" .. key, 2)
      end
    end
    local rc
    if type(value) == "number" and value == math.floor(value) and math.abs(value) < 2^53 then
      rc = S.sqlite3_bind_int64(self, index, value)
    elseif type(value) == "number" then
      rc = S.sqlite3_bind_double(self, index, value)
    elseif type(value) == "string" then
      rc = S.sqlite3_bind_text(self, index, value, #value, TRANSIENT)
    elseif type(value) == "boolean" then
      rc = S.sqlite3_bind_int64(self, index, value and 1 or 0)
    else
      error(("cannot bind a %s"):format(type(value)), 2)
    end
    self:db():check(rc)
  end
  return self
end

function Stmt:db()
  return S.sqlite3_db_handle(self)
end

-- Advances to the next row: true if there is one, false when done.
function Stmt:step()
  local rc = S.sqlite3_step(self)
  if rc == S.SQLITE_ROW then
    return true
  elseif rc == S.SQLITE_DONE then
    return false
  end
  local db = self:db()
  self:finalize()
  db:check(rc)
end

-- The current row as a Lua table. NULL columns are simply absent.
function Stmt:row()
  local row = {}
  for i = 0, S.sqlite3_column_count(self) - 1 do      -- columns count from 0
    local name = ffi.string(S.sqlite3_column_name(self, i))
    local kind = S.sqlite3_column_type(self, i)
    if kind == S.SQLITE_INTEGER then
      row[name] = tonumber(S.sqlite3_column_int64(self, i))
    elseif kind == S.SQLITE_FLOAT then
      row[name] = S.sqlite3_column_double(self, i)
    elseif kind == S.SQLITE_TEXT then
      -- Ask for the text before its length, as the SQLite docs advise.
      local text = S.sqlite3_column_text(self, i)
      row[name] = ffi.string(text, S.sqlite3_column_bytes(self, i))
    end
  end
  return row
end

function Stmt:finalize()
  ffi.gc(self, nil)
  S.sqlite3_finalize(self)
end

return Db
```

`Stmt:step()` handles its own errors: it finalizes the statement, then raises SQLite's message, which
survives `finalize` because it belongs to the connection.

### `src/stash/store.lua` (new)

`Store` keeps the methods the commands used with `MemoryStore`, so most commands don't change. It
speaks SQL through `Db`:

```lua
-- Store: bookmarks in an SQLite database, with full-text search (FTS5).
-- It has the same methods the commands used before, plus the page text:
--   add(entry, text) -> entry   get(id) -> entry|nil   remove(id) -> entry|nil
--   list{tag=, limit=} -> array   search(query) -> array   tags() -> array
--   entries() -> iterator over all entries in id order

local Db = require("stash.db")
local Entry = require("stash.entry")
local util = require("stash.util")

-- The schema grows by appending to this list; never edit a migration
-- that has shipped. The database remembers how many it has applied in
-- PRAGMA user_version.
local MIGRATIONS = {
  [[
  CREATE TABLE entries (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,   -- AUTOINCREMENT: ids are never reused
    url     TEXT NOT NULL,
    title   TEXT NOT NULL,
    note    TEXT NOT NULL DEFAULT '',
    created INTEGER NOT NULL
  );
  CREATE TABLE tags (
    entry_id INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    tag      TEXT NOT NULL,
    PRIMARY KEY (entry_id, tag)
  );
  CREATE INDEX tags_by_tag ON tags(tag);

  -- The search index: one row per entry, rowid = entries.id.
  CREATE VIRTUAL TABLE search USING fts5(title, url, note, tags, body);
  CREATE TRIGGER entries_deleted AFTER DELETE ON entries BEGIN
    DELETE FROM search WHERE rowid = old.id;
  END;
  ]],
}

local Store = {}
Store.__index = Store

-- Brings the schema up to date, one migration per transaction.
local function migrate(db)
  local version = db:first("PRAGMA user_version").user_version
  for i = version + 1, #MIGRATIONS do
    db:transaction(function()
      db:exec(MIGRATIONS[i])
      db:exec("PRAGMA user_version = " .. i)
    end)
  end
end

-- Opens the database in `path` (":memory:" for a throwaway one).
-- Returns the store, or nil and an error message.
function Store.open(path)
  local db, err = Db.open(path)
  if db == nil then
    return nil, err
  end
  db:exec("PRAGMA foreign_keys = ON")         -- SQLite leaves them off by default
  migrate(db)
  return setmetatable({ db = db }, Store)
end

function Store:close()
  self.db:close()
end

-- Every query that returns entries selects these columns. The tags come
-- along as one comma-separated string.
local SELECT = [[
  SELECT e.id, e.url, e.title, e.note, e.created,
         (SELECT group_concat(tag) FROM tags WHERE entry_id = e.id) AS tags
  FROM entries e
]]

local function to_entry(row)
  row.tags = util.split(row.tags or "", ",")
  return Entry.new(row)
end

function Store:add(entry, text)
  local db = self.db
  db:transaction(function()
    db:run("INSERT INTO entries (url, title, note, created) VALUES (:url, :title, :note, :created)",
           { url = entry.url, title = entry.title, note = entry.note, created = entry.created })
    entry.id = db:last_id()
    for _, tag in ipairs(entry.tags) do
      db:run("INSERT INTO tags (entry_id, tag) VALUES (?, ?)", { entry.id, tag })
    end
    db:run("INSERT INTO search (rowid, title, url, note, tags, body) VALUES (?, ?, ?, ?, ?, ?)",
           { entry.id, entry.title, entry.url, entry.note, entry:tag_string(" "), text or "" })
  end)
  return entry
end

function Store:get(id)
  local row = self.db:first(SELECT .. "WHERE e.id = ?", { id })
  return row and to_entry(row)
end

function Store:remove(id)
  local entry = self:get(id)
  if entry then
    self.db:run("DELETE FROM entries WHERE id = ?", { id })   -- tags and search rows follow
  end
  return entry
end

-- Iterates over all entries in id order.
function Store:entries()
  local rows = self.db:rows(SELECT .. "ORDER BY e.id")
  return function()
    local row = rows()
    return row and to_entry(row)
  end
end

-- filter.tag and filter.limit are optional; a missing parameter is NULL,
-- and LIMIT -1 means no limit.
function Store:list(filter)
  local found = {}
  for row in self.db:rows(SELECT .. [[
      WHERE :tag IS NULL OR e.id IN (SELECT entry_id FROM tags WHERE tag = :tag)
      ORDER BY e.id LIMIT :limit]], { tag = filter.tag, limit = filter.limit or -1 }) do
    found[#found + 1] = to_entry(row)
  end
  return found
end

-- Turns what the user typed into an FTS5 query: every word must appear.
-- Each word is quoted, so characters like - or : are not FTS5 syntax;
-- a trailing * still means "any word starting with this".
function Store.fts_query(text)
  local words = {}
  for word in text:gmatch("%S+") do
    local star = word:match("%*$") and "*" or ""
    word = word:gsub("%*$", ""):gsub('"', '""')
    if word ~= "" then
      words[#words + 1] = '"' .. word .. '"' .. star
    end
  end
  return table.concat(words, " ")
end

-- Full-text search, best matches first. Each entry gets a `snippet`
-- field: a few words of context with the matches in [brackets].
function Store:search(text)
  local query = Store.fts_query(text)
  local found = {}
  if query == "" then
    return found
  end
  for row in self.db:rows([[
      SELECT rowid AS id, snippet(search, -1, '[', ']', '...', 8) AS snippet
      FROM search WHERE search MATCH ? ORDER BY rank]], { query }) do
    local entry = self:get(row.id)
    entry.snippet = row.snippet
    found[#found + 1] = entry
  end
  return found
end

-- Returns { {tag=, count=}, ... }: most used first, then by name.
function Store:tags()
  local rows = {}
  for row in self.db:rows("SELECT tag, count(*) AS count FROM tags GROUP BY tag "
                          .. "ORDER BY count DESC, tag") do
    rows[#rows + 1] = row
  end
  return rows
end

return Store
```

Notes:

- **Schema.** `entries`: one row per bookmark; `AUTOINCREMENT` never reuses ids, even after `rm`.
  `tags`: one row per (entry, tag). `ON DELETE CASCADE` deletes an entry's tags with it, but only with
  `PRAGMA foreign_keys = ON`, which SQLite leaves off for backward compatibility; `Store.open` turns
  it on per connection.
- **Search index.** A separate FTS5 table whose `rowid` is the entry id. Virtual tables can't have
  foreign keys, so a trigger deletes the search row with the entry.
- **Tags in one query.** A `group_concat(tag)` subquery returns `"jit,lua"`; `to_entry` splits it.
- **Optional filters.** `:tag IS NULL OR ...`: when `filter.tag` is `nil`, nothing is bound and the
  parameter is `NULL`. `LIMIT -1` means no limit.
- **`Store.fts_query`** quotes each word for FTS5.
- **`entries()`** wraps `db:rows` in an iterator making `Entry` objects, so `export` (Chapter 12) now
  streams straight from SQLite.

### `src/stash/html.lua`

The index wants text, not HTML. Add `M.text` after the `TITLE` pattern, before `M.title`:

```lua
local TITLE = "<" .. nocase("title") .. "[^>]*>(.-)</" .. nocase("title") .. "%s*>"

-- The text of a page, for the search index: no tags, comments, scripts
-- or styles, and the whitespace squeezed.
function M.text(html)
  html = html:gsub("<!%-%-.-%-%->", " ")
  for _, tag in ipairs({ "script", "style" }) do
    html = html:gsub("<" .. nocase(tag) .. "[^>]*>.-</" .. nocase(tag) .. "%s*>", " ")
  end
  html = html:gsub("<[^>]*>", " ")
  return M.squeeze(M.decode_entities(html))
end
```

Comments, scripts and styles go first (readers never see them). Then tags become spaces, entities are
decoded and whitespace is squeezed.

### `src/stash/entry.lua`

Delete `Entry:matches`; FTS5 does the searching now.

### `src/stash/main.lua`

Replace the `require("stash.filestore")` line so the requires read:

```lua
local cli = require("stash.cli")
local commands = require("stash.commands")
local config = require("stash.config")
local errors = require("stash.errors")
local term = require("stash.term")
local util = require("stash.util")
local fs = require("stash.fs")
local Store = require("stash.store")
```

In `execute`, open the store like this, and close it at the end:

```lua
  local ok, merr = fs.mkdir_p(M.home())
  if not ok then
    errors.fail("cannot create %s", merr)
  end
  local store, serr = Store.open(M.home() .. "/stash.db")
  if store == nil then
    errors.fail("%s", serr)
  end
  local ctx = {
    store = store,
    config = settings,
    out = print,
    paint = term.painter(term.use_color(settings.color)),
    width = term.width(),
  }
  command.run(ctx, opts)
  store:close()
end
```

`FileStore` created the directory when saving; SQLite won't, so `main` calls `fs.mkdir_p`
(Chapter 12).

### `src/stash/commands.lua`

`add` passes the page text to the store (new: `text` and the second argument of `ctx.store:add`):

```lua
command "add" {
  usage = "add URL [-t TAGS] [-n NOTE]",
  help = "save a bookmark",
  options = { ["-t"] = { "tags", "list" }, ["-n"] = { "note", "value" } },
  run = function(ctx, opts)
    local url = opts[1]
    if url == nil then
      errors.usage("missing URL")
    end
    if not url:find("^%a[%w+.-]*://") then
      errors.usage("'%s' does not look like a URL", url)
    end
    local tags = {}
    for i, tag in ipairs(opts.tags or {}) do
      tag = tag:lower()
      if not tag:find("^[%w_-]+$") then
        errors.usage("bad tag '%s' (use letters, digits, - and _)", tag)
      end
      tags[i] = tag
    end
    -- Read the page when we can, for its title and the search index.
    local title, text
    if fetch.can_fetch(url) then
      local body, err = fetch.get(url)
      if body == nil then
        errors.fail("cannot fetch %s: %s", url, err)
      end
      title, text = html.title(body), html.text(body)
    end
    local entry = ctx.store:add(Entry.new({ url = url, title = title, tags = tags,
                                            note = opts.note, created = util.now() }), text)
    ctx.out("added " .. tostring(entry))
  end,
}
```

`search` takes several words and prints a snippet under each row:

```lua
command "search" {
  usage = "search WORDS...",
  help = "full-text search, best matches first",
  run = function(ctx, opts)
    local words = table.concat(opts, " ")
    if words == "" then
      errors.usage("missing WORDS")
    end
    local found = ctx.store:search(words)
    for _, entry in ipairs(found) do
      ctx.out(format_row(ctx, entry))
      ctx.out("     " .. entry.snippet)
    end
    if #found == 0 then
      errors.not_found("nothing matches '%s'", words)
    end
  end,
}
```

### Tests

`test/run.lua` drops `memstore_test` and `filestore_test` and adds the two new files:

```lua
-- Test files, in the order they run.
local FILES = {
  "util_test", "cli_test", "entry_test", "iter_test", "config_test",
  "commands_test", "json_test", "html_test", "fs_test", "term_test",
  "buffer_test", "db_test", "store_test",
  "e2e_test",
}
```

`test/db_test.lua` (new) checks the wrapper on an in-memory database:

```lua
local Db = require("stash.db")

local function memory_db()
  local db = assert(Db.open(":memory:"))
  db:exec("CREATE TABLE t (n INTEGER, x REAL, s TEXT)")
  return db
end

test("values go in and come back as Lua values", function()
  local db = memory_db()
  eq(db:run("INSERT INTO t VALUES (?, ?, ?)", { 42, 0.5, "it's" }), 1)
  eq(db:last_id(), 1)
  same(db:first("SELECT n, x, s FROM t"), { n = 42, x = 0.5, s = "it's" })
end)

test("named parameters, and NULL for the ones not given", function()
  local db = memory_db()
  db:run("INSERT INTO t VALUES (:n, :x, :s)", { n = 7, s = "seven" })
  same(db:first("SELECT * FROM t"), { n = 7, s = "seven" })
  raises(function() db:run("INSERT INTO t VALUES (:n, 0, '')", { m = 1 }) end, "no parameter :m")
end)

test("rows iterates in order", function()
  local db = memory_db()
  for i = 1, 3 do
    db:run("INSERT INTO t (n) VALUES (?)", { i * 10 })
  end
  local seen = {}
  for row in db:rows("SELECT n FROM t WHERE n > ? ORDER BY n", { 10 }) do
    seen[#seen + 1] = row.n
  end
  same(seen, { 20, 30 })
end)

test("SQL errors carry SQLite's message", function()
  local db = memory_db()
  raises(function() db:prepare("SELEKT 1") end, 'database: near "SELEKT": syntax error')
  raises(function() db:exec("INSERT INTO nope VALUES (1)") end, "database: no such table: nope")
end)

test("errors while stepping are reported too", function()
  local db = assert(Db.open(":memory:"))
  db:exec("CREATE TABLE u (name TEXT NOT NULL)")
  raises(function() db:run("INSERT INTO u VALUES (NULL)") end,
         "database: NOT NULL constraint failed: u.name")
end)

test("a failed transaction leaves no trace", function()
  local db = memory_db()
  raises(function()
    db:transaction(function()
      db:run("INSERT INTO t (n) VALUES (1)")
      error("boom")
    end)
  end, "boom")
  eq(db:first("SELECT count(*) AS n FROM t").n, 0)
end)

test("opening a bad path fails cleanly", function()
  local db, err = Db.open("no/such/dir/x.db")
  eq(db, nil)
  eq(err, "cannot open no/such/dir/x.db: unable to open database file")
end)
```

`test/store_test.lua` (new, 76 lines) tests `Store` the same way: ids, tag filters, search ranking
and snippets, FTS5 quoting. Copy it from `project/ch15/test/store_test.lua`.

Small updates to the other tests:

`test/commands_test.lua`: replace `require("stash.memstore")` with `require("stash.entry")` and
`require("stash.store")`, and build the sample store in SQLite:

```lua
-- A fresh in-memory database with two entries.
local function sample_store()
  local store = assert(Store.open(":memory:"))
  store:add(Entry.new({ url = "https://www.lua.org/", title = "Lua", tags = { "lua" },
                        created = NOW }), "Lua is a scripting language")
  store:add(Entry.new({ url = "https://luajit.org/", title = "LuaJIT", tags = { "lua", "jit" },
                        note = "fast", created = NOW }), "LuaJIT compiles Lua code")
  return store
end
```

Then add a `search` test at the end:

```lua
test("search shows a snippet under each match", function()
  eq(run(sample_store(), { "search", "compiles" }), table.concat({
    "  2  LuaJIT                                jit,lua           2026-01-01",
    "     LuaJIT [compiles] Lua code",
  }, "\n"))
  raises(function() run(sample_store(), { "search", "python" }) end, "nothing matches 'python'")
end)
```

`test/entry_test.lua`: delete the test `"matches ignores case and treats the term literally"`.

`test/html_test.lua`: add a test for `text`:

```lua
test("text drops tags, scripts and comments", function()
  eq(html.text("<p>Hello <b>you</b></p><!-- hidden --><SCRIPT>x()</SCRIPT>&amp; more"),
     "Hello you & more")
end)
```

### Checkpoint

Run these from the project directory. The two `luajit -e` lines use the wrapper to look inside the
database.

```console
$ luajit test/run.lua
util_test        3 tests, 0 failed
cli_test         5 tests, 0 failed
entry_test       4 tests, 0 failed
iter_test        4 tests, 0 failed
config_test      4 tests, 0 failed
commands_test    6 tests, 0 failed
json_test        6 tests, 0 failed
html_test        5 tests, 0 failed
fs_test          3 tests, 0 failed
term_test        3 tests, 0 failed
buffer_test      3 tests, 0 failed
db_test          7 tests, 0 failed
store_test       8 tests, 0 failed
e2e_test         5 tests, 0 failed

66 passed, 0 failed
$ export STASH_HOME=demo STASH_NOW=1767225600
$ PAGES=file://$PWD/test/fixtures
$ ./stash add $PAGES/lua.html -t lua,lang -n "the official site"
added #1 The Programming Language Lua
$ ./stash add $PAGES/luajit.html -t lua,jit
added #2 LuaJIT: a Just-In-Time Compiler & FFI
$ ./stash add $PAGES/sqlite.html -t db,search
added #3 SQLite FTS5 Extension
$ ./stash list
  1  The Programming Language Lua          lang,lua          2026-01-01
  2  LuaJIT: a Just-In-Time Compiler &...  jit,lua           2026-01-01
  3  SQLite FTS5 Extension                 db,search         2026-01-01
$ ./stash search table
  3  SQLite FTS5 Extension                 db,search         2026-01-01
     ...an SQLite virtual [table] module that provides full...
  1  The Programming Language Lua          lang,lua          2026-01-01
     ...Its only data structure is the [table].
$ ./stash search fts5 search
  3  SQLite FTS5 Extension                 db,search         2026-01-01
     SQLite [FTS5] Extension [FTS5] is an SQLite virtual...
$ ./stash search c functions
  2  LuaJIT: a Just-In-Time Compiler &...  jit,lua           2026-01-01
     ...Its FFI library calls [C] [functions] and uses...
$ ./stash search compil*
  2  LuaJIT: a Just-In-Time Compiler &...  jit,lua           2026-01-01
     ...a Just-In-Time [Compiler] & FFI LuaJIT runs...
$ ./stash search console; echo "exit $?"
stash: nothing matches 'console'
exit 1
$ ./stash tags
   2  lua
   1  db
   1  jit
   1  lang
   1  search
$ ./stash rm 3
removed #3 SQLite FTS5 Extension
$ ./stash search fts5; echo "exit $?"
stash: nothing matches 'fts5'
exit 1
$ ./stash add https://example.com/ -t web
added #4 example.com
$ ./stash list -t web
  4  example.com                           web               2026-01-01
$ ls demo
stash.db
$ LUA_PATH="src/?.lua" luajit -e 'local db = require("stash.db").open("demo/stash.db") print(db:first("PRAGMA user_version").user_version) for r in db:rows("SELECT * FROM tags") do print(r.entry_id, r.tag) end'
1
1	lang
1	lua
2	jit
2	lua
4	web
$ LUA_PATH="src/?.lua" luajit -e 'print(require("stash.db").version())'
3.37.2
```

The cascade removed entry 3's tags. `search console` finds nothing because `html.text` dropped the
`<script>` in `sqlite.html`. Your SQLite version may differ.

The complete project at this point is in `project/ch15/`.

## Summary

- `ffi.load("name")` opens `libname.so` and returns a namespace; declarations still come from
  `ffi.cdef`. Fall back to the soname (`libsqlite3.so.0`) if the dev symlink is missing.
- Translate only the header parts you use. `#define` → `enum`; opaque structs stay opaque;
  `sqlite3_int64` → `int64_t`.
- Out parameters: `ffi.new("T *[1]")`, then read `[0]`.
- `int64_t` results: `tonumber()`. `const char *` results: `ffi.string(p, len)`.
- `SQLITE_TRANSIENT` is `ffi.cast("void (*)(void *)", -1)`. Use it for Lua strings: they live only
  during the call.
- Two layers: raw bindings (cdef + load) and a wrapper (`ffi.metatype` methods, `ffi.gc` ownership,
  `sqlite3_errmsg` errors, iterators, tables in and out).
- Remove a finalizer with `ffi.gc(p, nil)` before freeing by hand.
- Transactions: `BEGIN`, `pcall(fn)`, then `COMMIT` or `ROLLBACK` and re-raise.
- FTS5: a virtual table, `MATCH`, `ORDER BY rank`, `snippet()`. Quote user input.
- Migrations: an array of SQL strings plus `PRAGMA user_version`.

## Exercises

1. Add `Db:total_changes()`: the number of rows changed since the database was opened. SQLite's
   function is `int sqlite3_total_changes(sqlite3 *db);`. Which two files change?

   <details><summary>Solution</summary>

   The raw layer gets the declaration, the wrapper the method. In `src/stash/ffi/sqlite.lua`, next to
   `sqlite3_changes`:

   ```c
   int sqlite3_total_changes(sqlite3 *db);
   ```

   In `src/stash/db.lua`:

   ```lua
   function Db:total_changes()
     return S.sqlite3_total_changes(self)    -- an int: already a Lua number
   end
   ```

   Check it:

   ```console
   $ LUA_PATH="src/?.lua" luajit -e 'local db = require("stash.db").open(":memory:") db:exec("CREATE TABLE t (n)") db:run("INSERT INTO t VALUES (1), (2)") db:run("DELETE FROM t") print(db:total_changes())'
   4
   ```

   </details>

2. Write `Db:pluck(sql, params)`, which returns an array of every row's first column. Use it to list
   all tags in `stash.db`: `db:pluck("SELECT DISTINCT tag FROM tags ORDER BY tag")`.

   <details><summary>Solution</summary>

   Rows are keyed by name, so we need the first column's name. The statement knows it:

   ```lua
   function Db:pluck(sql, params)
     local stmt = self:prepare(sql):bind(params)
     local name = ffi.string(S.sqlite3_column_name(stmt, 0))
     local values = {}
     while stmt:step() do
       values[#values + 1] = stmt:row()[name]
     end
     stmt:finalize()
     return values
   end
   ```

   After the checkpoint above, in the project directory:

   ```console
   $ LUA_PATH="src/?.lua" luajit -e 'local db = require("stash.db").open("demo/stash.db") print(table.concat(db:pluck("SELECT DISTINCT tag FROM tags ORDER BY tag"), " "))'
   jit lang lua web
   ```

   A `NULL` leaves a hole in the array, so `#values` may be wrong for nullable columns. Add
   `WHERE col IS NOT NULL` or index with an explicit counter.

   </details>

3. FTS5's `highlight(table, column, before, after)` returns a whole column with matches marked.
   Make `fts5.lua` print the title with `highlight(docs, 0, '*', '*')`. What do the `title:sqlite`
   and `lua c` queries print now?

   <details><summary>Solution</summary>

   Replace the `SELECT` line with:

   ```lua
   SELECT highlight(docs, 0, '*', '*') AS title, snippet(docs, 1, '[', ']', '...', 6) AS snip
   ```

   ```console
   -- lua c
   LuaJIT	...[Lua], with an FFI for [C].
   ...
   -- title:sqlite
   *SQLite*	SQLite is a C library. FTS5...
   ```

   Column 0 is `title`. `LuaJIT` stays unmarked: FTS5 matches whole words (tokens), and the token is
   `luajit`. Rows that match only in the body print the title unchanged.

   </details>

4. `for row in db:rows(sql) do ... break end` leaves the loop before the iterator finalizes the
   statement. Is that a leak? What happens, and when?

   <details><summary>Solution</summary>

   No leak. `Db:prepare` returned the statement through `ffi.gc(out[0], S.sqlite3_finalize)`, and
   only the iterator closure references it. After the loop both are garbage, and the next GC cycle
   calls `sqlite3_finalize`. Until then the statement holds a read lock: another connection that
   writes waits for the busy timeout (2 s), then fails with `database is locked`. In a long-running
   program, finalize explicitly (or collect the rows first) if that matters. Since the database is
   closed with `sqlite3_close_v2`, the GC's finalization order doesn't matter.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-15--wrapping-sqlite)
