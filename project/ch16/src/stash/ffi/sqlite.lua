-- Raw bindings to SQLite: declarations copied from sqlite3.h (only the
-- parts stash uses) and the loaded library. stash.db builds a friendlier
-- API on top; nothing else should need this module.

local ffi = require("ffi")
local load = require("stash.ffi.load")

ffi.cdef [[
/* Opaque types: we only ever hold pointers to them. */
typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;
typedef struct sqlite3_context sqlite3_context;
typedef struct sqlite3_value sqlite3_value;

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

  SQLITE_UTF8 = 1,
  SQLITE_DETERMINISTIC = 0x800,
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

/* SQL functions written in Lua. */
typedef void (*sqlite3_function)(sqlite3_context *ctx, int argc, sqlite3_value **argv);
int sqlite3_create_function_v2(sqlite3 *db, const char *name, int nargs, int flags,
                               void *app, sqlite3_function func, sqlite3_function step,
                               void (*final)(sqlite3_context *), void (*destroy)(void *));
int sqlite3_value_type(sqlite3_value *value);
int64_t sqlite3_value_int64(sqlite3_value *value);
double sqlite3_value_double(sqlite3_value *value);
const unsigned char *sqlite3_value_text(sqlite3_value *value);
int sqlite3_value_bytes(sqlite3_value *value);
void sqlite3_result_int64(sqlite3_context *ctx, int64_t value);
void sqlite3_result_double(sqlite3_context *ctx, double value);
void sqlite3_result_text(sqlite3_context *ctx, const char *text, int nbytes,
                         void (*destructor)(void *));
void sqlite3_result_null(sqlite3_context *ctx);
void sqlite3_result_error(sqlite3_context *ctx, const char *message, int nbytes);
]]

return load({ "sqlite3", "libsqlite3.so.0" })
