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

-- SQL values -> Lua values: the function arguments in create_function.
local function from_sql(value)
  local kind = S.sqlite3_value_type(value)
  if kind == S.SQLITE_INTEGER then
    return tonumber(S.sqlite3_value_int64(value))
  elseif kind == S.SQLITE_FLOAT then
    return S.sqlite3_value_double(value)
  elseif kind == S.SQLITE_NULL then
    return nil
  end
  local text = S.sqlite3_value_text(value)
  return ffi.string(text, S.sqlite3_value_bytes(value))
end

-- Lua value -> the result of an SQL function call.
local function to_sql(ctx, value)
  if value == nil then
    S.sqlite3_result_null(ctx)
  elseif type(value) == "boolean" then
    S.sqlite3_result_int64(ctx, value and 1 or 0)
  elseif type(value) == "number" then
    S.sqlite3_result_double(ctx, value)
  else
    value = tostring(value)
    S.sqlite3_result_text(ctx, value, #value, TRANSIENT)
  end
end

-- Callbacks made by ffi.cast are never garbage-collected, referenced or
-- not; only free() releases them. We never free these: SQLite may call
-- them until the process ends. This table just records that we own them.
local anchors = {}

-- Makes the Lua function fn(...) callable from SQL as name(...).
-- An error in fn becomes an SQL error; it must not escape into C.
function Db:create_function(name, nargs, fn)
  local callback = ffi.cast("sqlite3_function", function(ctx, argc, argv)
    local args = {}
    for i = 0, argc - 1 do
      args[i + 1] = from_sql(argv[i])
    end
    local ok, result = pcall(fn, unpack(args, 1, argc))
    if ok then
      to_sql(ctx, result)
    else
      result = tostring(result)
      S.sqlite3_result_error(ctx, result, #result)
    end
  end)
  anchors[#anchors + 1] = callback
  self:check(S.sqlite3_create_function_v2(self, name, nargs,
                                          S.SQLITE_UTF8 + S.SQLITE_DETERMINISTIC,
                                          nil, callback, nil, nil, nil))
end

-- Lua strings hold text and binary data alike; SQLite tells them apart.
-- Wrap binary data as Db.blob(s) to store it as a BLOB.
function Db.blob(data)
  return { blob = data }
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
    elseif type(value) == "table" and type(value.blob) == "string" then
      rc = S.sqlite3_bind_blob(self, index, value.blob, #value.blob, TRANSIENT)
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

-- sqlite3_step may call our Lua SQL functions (create_function), and C
-- must never call back into Lua from a JIT-compiled FFI call: LuaJIT
-- stops with "PANIC: ... bad callback". Most steps call no Lua at all,
-- so the JIT would happily compile them; we tell it not to.
jit.off(Stmt.step)

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
    elseif kind == S.SQLITE_BLOB then
      local data = S.sqlite3_column_blob(self, i)
      row[name] = ffi.string(data, S.sqlite3_column_bytes(self, i))    -- may hold zero bytes
    end
  end
  return row
end

function Stmt:finalize()
  ffi.gc(self, nil)
  S.sqlite3_finalize(self)
end

return Db
