# Chapter 16 — Callbacks and libcurl

So far Lua has called C. Many C libraries also call **back**: you hand them a function and they call
it when something happens. `qsort` calls a comparator, libcurl calls a function per piece of a
download, SQLite calls a function per row an SQL function sees. This chapter turns Lua functions
into safe C function pointers; `stash` then downloads real pages with libcurl and gets a Lua `REGEXP`
operator. It builds on [Chapter 15](15-wrapping-sqlite.md)'s SQLite wrapper;
[Chapter 17](17-binary-data-and-zlib.md) moves on to binary data.

## A Lua function as a C function pointer

`qsort` from the C library sorts any array. It knows nothing about the elements, so you pass a
comparator that takes two pointers and returns a negative number, zero or a positive number.

`examples/ch16/qsort.lua`

```lua
-- C calls Lua: qsort from the C library, with a comparator written in Lua.
local ffi = require("ffi")

ffi.cdef [[
typedef int (*compare_fn)(const void *a, const void *b);
void qsort(void *base, size_t count, size_t size, compare_fn compare);
]]

local numbers = ffi.new("int[6]", { 42, 7, 19, 3, 88, 1 })

-- qsort hands us untyped pointers; we cast them to what they point to.
local function by_value(a, b)
  local x, y = ffi.cast("const int *", a)[0], ffi.cast("const int *", b)[0]
  return x < y and -1 or (x > y and 1 or 0)
end

local compare = ffi.cast("compare_fn", by_value)   -- a C function pointer
print(compare)
ffi.C.qsort(numbers, 6, ffi.sizeof("int"), compare)

local out = {}
for i = 0, 5 do
  out[#out + 1] = numbers[i]
end
print(table.concat(out, " "))

-- The same pointer, now calling a different Lua function: descending.
compare:set(function(a, b) return -by_value(a, b) end)
ffi.C.qsort(numbers, 6, ffi.sizeof("int"), compare)
print(numbers[0], numbers[5])

compare:free()                                     -- give the slot back
print(pcall(compare.set, compare, by_value))      -- a freed callback is dead
```

```console
$ luajit examples/ch16/qsort.lua
cdata<int (*)()>: 0x78da774ba008
1 3 7 19 42 88
88	1
false	bad callback
```

(The address changes every run.)

- `ffi.cast("compare_fn", lua_function)` creates a **callback**: a real C function pointer. When C
  calls it, LuaJIT converts the arguments to Lua values, runs the function and converts the result
  to the C return type.
- The arguments arrive as cdata, here two `const void *`. Cast to `const int *` and index `[0]` to
  read the integers ([Chapter 14](14-c-data.md)).
- `cb:set(fn)` points the callback at another Lua function while C keeps the same pointer. Useful
  when C stores the pointer and you can't give it a new one.
- `cb:free()` releases the callback. The pointer is then dead: using it is an error, and C must never
  call it again.

The type is a function pointer type, as a `typedef` in the cdef or inline:
`ffi.cast("int (*)(const void *, const void *)", fn)`. The cdata prints as `int (*)()`: LuaJIT
doesn't show the parameters.

## Callbacks are a limited resource

LuaJIT keeps callbacks in a fixed table of 500 to 1000 slots, depending on the CPU architecture. The
garbage collector never frees them. Two rules follow.

`examples/ch16/implicit.lua`

```lua
-- Passing a Lua function where C wants a function pointer works, but each
-- call makes a new callback that is never freed. Slots run out.
local ffi = require("ffi")

ffi.cdef [[
void qsort(void *base, size_t count, size_t size, int (*compare)(const void *, const void *));
]]

local numbers = ffi.new("int[2]", { 2, 1 })
local function compare(a, b)
  return ffi.cast("const int *", a)[0] - ffi.cast("const int *", b)[0]
end

-- Right: convert once, reuse the pointer.
local cb = ffi.cast("int (*)(const void *, const void *)", compare)
for _ = 1, 10000 do
  ffi.C.qsort(numbers, 2, 4, cb)
end
print("10000 sorts, one callback")

-- Wrong: every call converts the function again.
local calls = 0
local ok, err = pcall(function()
  for _ = 1, 10000 do
    ffi.C.qsort(numbers, 2, 4, compare)
    calls = calls + 1
  end
end)
print(calls, ok, err)

-- The slots are gone for good: even a single cast fails now.
print(pcall(ffi.cast, "int (*)(const void *, const void *)", compare))
```

```console
$ luajit examples/ch16/implicit.lua
10000 sorts, one callback
895	false	examples/ch16/implicit.lua:25: too many callbacks
false	too many callbacks
```

The count depends on the machine.

- **Passing a Lua function directly** where C expects a function pointer works, but LuaJIT converts
  it on every call. Each conversion takes a **permanent** slot (LuaJIT can't know whether C kept the
  pointer), so a loop eats them all.
- **An explicit `ffi.cast` callback lives until you call `free()`.** Losing the cdata doesn't free
  it; it only loses your way to free it.

So cast once, keep the cdata, reuse it. Free it when C is done with it, or keep it forever if C might
call it forever, as with a write callback that serves every download.

## Rules for callbacks

A callback runs in the middle of C code that knows nothing about Lua, so:

1. **Don't let errors escape.** A Lua error inside a callback unwinds the C frames between you and
   the catching `pcall`. LuaJIT allows it but advises against it: C cleanup (free memory, unlock,
   close a file) never runs. Catch errors with `pcall` inside the callback and report failure the
   way the C library expects: a return value, an error function.
2. **Never call back from a JIT-compiled FFI call.** More below.
3. **Keep it cheap.** Each C→Lua call costs about a `pcall` plus argument conversion, and the JIT
   can't optimize across the C boundary. `table.sort` is much faster than `qsort` with a Lua
   comparator. Use callbacks where the library requires them, not as a fast path.
4. **No variadic callbacks**, and no structs passed by value: LuaJIT supports neither as a callback
   signature.

### Variadic C functions

The other direction has a trap too. Functions like `printf` or `curl_easy_setopt` end in `...`, so
the FFI has no declared types for those arguments and picks one from the Lua value.

`examples/ch16/varargs.lua`

```lua
-- Variadic C functions (...) get no type information for the extra
-- arguments, so the FFI picks one from the Lua value.
local ffi = require("ffi")

ffi.cdef [[
int printf(const char *format, ...);
]]

ffi.C.printf("%.1f\n", 42)                       -- a Lua number goes as a double
ffi.C.printf("%d\n", ffi.cast("int", 42))        -- cast when C wants an int
ffi.C.printf("%ld\n", ffi.cast("long", 2^40))    -- ...or a long
ffi.C.printf("%s has %d bytes\n", "hello", ffi.new("int", #"hello"))
ffi.C.printf("%lld\n", 123LL)                    -- int64 cdata stays int64
-- ffi.C.printf("%d\n", 42) prints garbage: printf reads an int from a
-- register where the double was never put.
```

```console
$ luajit examples/ch16/varargs.lua
42.0
42
1099511627776
hello has 5 bytes
123
```

A Lua number goes as a `double`, a string as `const char *`, cdata as its own type. When C wants an
integer, cast: `ffi.cast("int", 42)` or `ffi.new("int", 42)`. Getting it wrong raises no error; C
just reads the wrong register, and the garbage depends on the machine.

## Wrapping libcurl

libcurl transfers data over HTTP, HTTPS, FTP, `file://` and more. Its "easy" interface is four calls:

| Call | Does |
|------|------|
| `curl_easy_init()` | creates a handle (an opaque `CURL *`) |
| `curl_easy_setopt(h, option, value)` | sets one option: the URL, a callback, a timeout... |
| `curl_easy_perform(h)` | runs the whole transfer; calls your callbacks while it runs |
| `curl_easy_cleanup(h)` | frees the handle |

curl doesn't collect the body; it calls a **write callback** with each piece as it arrives:
`size_t write(char *data, size_t size, size_t nitems, void *userdata)`. The piece is `size * nitems`
bytes (`size` is always 1), at most 16 KiB, not zero-terminated. The callback returns how many bytes
it took; anything else makes curl stop with an error.

`examples/ch16/curl_get.lua`

```lua
-- The smallest useful libcurl program: download a URL into a Lua string.
-- Run it from the course directory; it reads examples/ch16/page.html.
local ffi = require("ffi")

ffi.cdef [[
typedef struct CURL CURL;
CURL *curl_easy_init(void);
int curl_easy_setopt(CURL *curl, int option, ...);
int curl_easy_perform(CURL *curl);
const char *curl_easy_strerror(int code);
void curl_easy_cleanup(CURL *curl);
typedef size_t (*write_fn)(char *data, size_t size, size_t nitems, void *userdata);
]]
local curl = ffi.load("curl")

local CURLOPT_URL, CURLOPT_WRITEFUNCTION = 10002, 20011

local function get(url)
  local pieces = {}
  local on_write = ffi.cast("write_fn", function(data, size, nitems)
    local n = tonumber(size * nitems)
    pieces[#pieces + 1] = ffi.string(data, n)
    return n                                   -- "I took all n bytes"
  end)
  local handle = curl.curl_easy_init()
  curl.curl_easy_setopt(handle, CURLOPT_URL, url)
  curl.curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, on_write)
  local rc = curl.curl_easy_perform(handle)    -- on_write runs in here
  curl.curl_easy_cleanup(handle)
  on_write:free()
  if rc ~= 0 then
    return nil, ffi.string(curl.curl_easy_strerror(rc))
  end
  return table.concat(pieces), #pieces
end

local here = "file://" .. os.getenv("PWD") .. "/examples/ch16/"
local body, pieces = get(here .. "page.html")
print(#body .. " bytes in " .. pieces .. " piece(s)")
print(body:match("<title>(.-)</title>"))
print(get(here .. "missing.html"))
```

```console
$ luajit examples/ch16/curl_get.lua
140 bytes in 1 piece(s)
A page for curl
nil	Couldn't read a file:// file
```

- `size * nitems` multiplies two `size_t` cdata into a `uint64_t` cdata; `tonumber` makes it a Lua
  number.
- `ffi.string(data, n)` copies the piece: the pointer is valid only during the callback.
- `curl_easy_setopt` is variadic; the option number says which type curl reads. `CURLOPT_URL` reads a
  `char *`, so a Lua string works. A Lua function for `CURLOPT_WRITEFUNCTION` needs an explicit cast:
  a variadic argument has no type to convert to.
- The option numbers are `#define`s in `curl.h`: a type base plus an index. Strings and pointers
  start at 10000, functions at 20000, `long`s at 0, so `CURLOPT_URL` is 10000 + 2. Copy the final
  numbers into your cdef; they never change.

This example makes and frees a callback per download, fine for a script. `stash` makes one when it
loads and reuses it.

## SQL functions in Lua

SQLite calls back too. `sqlite3_create_function_v2` registers a C function under an SQL name; with a
callback, that function is Lua. `stash.db` gets a `Db:create_function` method for it
(in [Building stash](#building-stash-downloads-with-libcurl-and-a-lua-regexp) below):

`examples/ch16/sqlfunc.lua`

```lua
-- A Lua function called from SQL, through stash.db's create_function.
package.path = "project/ch16/src/?.lua;" .. package.path
local Db = require("stash.db")

local db = assert(Db.open(":memory:"))
db:exec([[
  CREATE TABLE words (w TEXT);
  INSERT INTO words VALUES ('lua'), ('LuaJIT'), ('sqlite'), (NULL);
]])

db:create_function("vowels", 1, function(s)
  return s and select(2, s:gsub("[aeiouAEIOU]", ""))
end)

for row in db:rows("SELECT w, vowels(w) AS n FROM words ORDER BY n DESC, w") do
  print(row.w, row.n)
end

db:create_function("fails", 0, function() error("no luck", 0) end)
print(pcall(db.first, db, "SELECT fails()"))
```

```console
$ luajit examples/ch16/sqlfunc.lua
LuaJIT	3
lua	2
sqlite	2
nil	nil
false	database: no luck
```

- SQLite passes the arguments as an array of `sqlite3_value *`. The wrapper converts each to a Lua
  value, calls the function, and returns the result with a `sqlite3_result_*` call.
- `NULL` arrives as `nil`; a `nil` result becomes `NULL`.
- The error in `fails` doesn't escape into SQLite: the callback catches it with `pcall` and reports
  it with `sqlite3_result_error`. SQLite fails the statement, and the wrapper raises that as a Lua
  error, safely in Lua code.

## The JIT and callbacks: "bad callback"

About rule 2. When the JIT compiles a loop that calls a C function through the FFI, it emits a direct
machine-code call without the interpreter's bookkeeping. If that C function then calls back into Lua,
LuaJIT can't run the callback and stops the whole process:

`examples/ch16/panic.lua`

```lua
-- A JIT-compiled FFI call must not call back into Lua.
--   luajit examples/ch16/panic.lua       stash.db as it is: works
--   luajit examples/ch16/panic.lua on    with the JIT back on: PANIC
package.path = "project/ch16/src/?.lua;" .. package.path
local Db = require("stash.db")
local db = assert(Db.open(":memory:"))
if arg[1] == "on" then
  jit.on(db:prepare("SELECT 1").step)        -- undo stash.db's jit.off(Stmt.step)
end
db:exec("CREATE TABLE t (s TEXT)")
for i = 1, 1000 do
  db:run("INSERT INTO t VALUES (?)", { "row " .. i })
end
db:create_function("shout", 1, function(s) return s:upper() end)

local function count(sql)
  local n = 0
  for _ in db:rows(sql) do n = n + 1 end
  return n
end
print(count("SELECT s FROM t"))              -- hot loop: step() gets compiled
print(count("SELECT shout(s) FROM t"))       -- same loop, but now step() calls Lua
```

```console
$ luajit examples/ch16/panic.lua
1000
1000
$ luajit examples/ch16/panic.lua on
1000
PANIC: unprotected error in call to Lua API (bad callback)
```

The first `count` runs 1000 times through `Stmt:step`, so the JIT compiles the call to
`sqlite3_step`; no callback happens there. The second query calls the Lua function `shout` from
inside that compiled `sqlite3_step` call. A PANIC is not a Lua error: `pcall` can't catch it, and the
process exits with status 1.

Usually LuaJIT notices first: when an FFI call calls back while the interpreter runs it, LuaJIT
blacklists that call for compilation. The trap is a C function that calls back only **sometimes**,
after it was compiled. `sqlite3_step` is exactly that: most queries call no Lua.

The fix is `jit.off(f)`: never compile `f`, the Lua function that makes the FFI call. `stash.db`
does `jit.off(Stmt.step)`, so `sqlite3_step` is always called from the interpreter: a little slower,
no crash. `stash.fetch` does the same for `fetch.get`, which calls `curl_easy_perform`.
[Chapter 18](18-performance-and-the-jit.md) explains the JIT itself.

## Building stash: downloads with libcurl and a Lua REGEXP

Until now `stash add` could only read `file://` URLs, with Lua's `io` library. Now:

- `fetch.lua` uses libcurl, so `add` also reads `http://` and `https://` pages, follows redirects and
  sends a user agent. `add --no-fetch` saves a URL without downloading it.
- two new settings in `config.lua`: `user_agent` and `timeout`.
- `stash.db` gets `Db:create_function`; `Store` uses it to add a Lua-pattern `REGEXP` operator to
  SQL, used by `list -m PATTERN`.
- `help` sizes its first column to fit the longest usage line.

### `src/stash/ffi/curl.lua` (new)

The raw bindings, styled like `stash.ffi.sqlite`:

```lua
-- Raw bindings to libcurl's "easy" interface (from curl/curl.h and
-- curl/easy.h). stash.fetch wraps them.

local ffi = require("ffi")
local load = require("stash.ffi.load")

ffi.cdef [[
typedef struct CURL CURL;
typedef int CURLcode;                         /* C enums are ints */

enum {
  CURLE_OK = 0,
  CURL_GLOBAL_DEFAULT = 3,
  CURL_ERROR_SIZE = 256,

  /* Option numbers are a type base plus an index, see curl.h:
     LONG = 0, OBJECTPOINT/STRINGPOINT = 10000, FUNCTIONPOINT = 20000. */
  CURLOPT_URL = 10002,
  CURLOPT_ERRORBUFFER = 10010,
  CURLOPT_WRITEFUNCTION = 20011,
  CURLOPT_TIMEOUT = 13,
  CURLOPT_USERAGENT = 10018,
  CURLOPT_FAILONERROR = 45,
  CURLOPT_FOLLOWLOCATION = 52,
  CURLOPT_MAXREDIRS = 68,
  CURLOPT_NOSIGNAL = 99,
  CURLOPT_PROTOCOLS = 181,

  CURLPROTO_HTTP = 1,
  CURLPROTO_HTTPS = 2,
  CURLPROTO_FILE = 1024,

  CURLINFO_EFFECTIVE_URL = 0x100001,
  CURLINFO_RESPONSE_CODE = 0x200002,
  CURLINFO_CONTENT_TYPE = 0x100012,
};

/* The write callback: called with each piece of the body as it arrives. */
typedef size_t (*curl_write_callback)(char *data, size_t size, size_t nitems, void *userdata);

CURLcode curl_global_init(long flags);
char *curl_version(void);
const char *curl_easy_strerror(CURLcode code);

CURL *curl_easy_init(void);
CURLcode curl_easy_setopt(CURL *curl, int option, ...);
CURLcode curl_easy_perform(CURL *curl);
CURLcode curl_easy_getinfo(CURL *curl, int info, ...);
void curl_easy_cleanup(CURL *curl);
]]

return load({ "curl", "libcurl.so.4" })
```

`curl_easy_getinfo` is variadic too: the info number says what pointer type curl writes to.

### `src/stash/fetch.lua` (rewritten)

Replace the whole file. `can_fetch` and `file_path` are gone; curl handles `file://` itself.

```lua
-- Fetching pages with libcurl: http://, https:// and file:// URLs.
--
-- curl delivers the body in pieces to a write callback: a Lua function
-- that C calls. We make that callback once and reuse it for every
-- download (see "callbacks" in Chapter 16).

local ffi = require("ffi")
local Buffer = require("stash.buffer")
local C = require("stash.ffi.curl")

local M = {}

M.MAX_SIZE = 5 * 1024 * 1024                 -- larger pages are refused

assert(C.curl_global_init(C.CURL_GLOBAL_DEFAULT) == C.CURLE_OK, "cannot initialize libcurl")

-- The download in progress, filled by on_write. A Buffer (Chapter 14)
-- takes the bytes straight from curl's memory, no Lua string per piece.
local body = Buffer.new()
local too_large = false

-- C calls this; it must never raise a Lua error, because an error cannot
-- unwind through curl's C frames. Returning anything other than the
-- number of bytes received makes curl stop with CURLE_WRITE_ERROR.
local function on_write(data, size, nitems)
  local n = tonumber(size * nitems)          -- size_t arrives as a 64-bit cdata number
  if #body + n > M.MAX_SIZE then
    too_large = true
    return 0
  end
  local ok = pcall(body.append, body, data, n)
  return ok and n or 0
end

-- ffi.cast turns the Lua function into a C function pointer. It stays
-- alive as long as this module does: forever, which is what we want.
local write_callback = ffi.cast("curl_write_callback", on_write)

-- Reads a string-valued piece of information about the last transfer.
local function info_string(handle, what)
  local out = ffi.new("char *[1]")
  if C.curl_easy_getinfo(handle, what, out) == C.CURLE_OK and out[0] ~= nil then
    return ffi.string(out[0])
  end
end

function M.version()
  return ffi.string(C.curl_version())
end

-- Downloads url. options: user_agent (string), timeout (seconds).
-- Returns the body and a table { status=, url=, content_type= }, or nil
-- and an error message.
function M.get(url, options)
  options = options or {}
  local handle = C.curl_easy_init()
  if handle == nil then
    return nil, "cannot start libcurl"
  end
  handle = ffi.gc(handle, C.curl_easy_cleanup)
  local errbuf = ffi.new("char[?]", C.CURL_ERROR_SIZE)

  -- curl_easy_setopt is variadic (...), so the FFI cannot know the type
  -- curl expects: a Lua number would be passed as a double. Options that
  -- take a long get an explicit ffi.cast("long", ...).
  local function long(n)
    return ffi.cast("long", n)
  end
  C.curl_easy_setopt(handle, C.CURLOPT_URL, url)
  C.curl_easy_setopt(handle, C.CURLOPT_WRITEFUNCTION, write_callback)
  C.curl_easy_setopt(handle, C.CURLOPT_ERRORBUFFER, errbuf)
  C.curl_easy_setopt(handle, C.CURLOPT_PROTOCOLS,
                     long(bit.bor(C.CURLPROTO_HTTP, C.CURLPROTO_HTTPS, C.CURLPROTO_FILE)))
  C.curl_easy_setopt(handle, C.CURLOPT_FOLLOWLOCATION, long(1))
  C.curl_easy_setopt(handle, C.CURLOPT_MAXREDIRS, long(5))
  C.curl_easy_setopt(handle, C.CURLOPT_FAILONERROR, long(1))      -- HTTP 4xx/5xx are errors
  C.curl_easy_setopt(handle, C.CURLOPT_NOSIGNAL, long(1))
  C.curl_easy_setopt(handle, C.CURLOPT_TIMEOUT, long(options.timeout or 10))
  C.curl_easy_setopt(handle, C.CURLOPT_USERAGENT, options.user_agent or "stash")

  body:reset()
  too_large = false
  local rc = C.curl_easy_perform(handle)     -- calls on_write while it runs
  if too_large then
    return nil, ("page is larger than %d bytes"):format(M.MAX_SIZE)
  elseif rc ~= C.CURLE_OK then
    local message = ffi.string(errbuf)       -- details, when curl wrote any
    if message == "" then
      message = ffi.string(C.curl_easy_strerror(rc))
    end
    return nil, message
  end

  local status = ffi.new("long[1]")
  C.curl_easy_getinfo(handle, C.CURLINFO_RESPONSE_CODE, status)
  local info = {
    status = tonumber(status[0]),            -- 0 for file:// URLs
    url = info_string(handle, C.CURLINFO_EFFECTIVE_URL),
    content_type = info_string(handle, C.CURLINFO_CONTENT_TYPE),
  }
  return body:tostring(), info
end

-- curl_easy_perform calls back into Lua, so the function that calls it
-- must not be JIT-compiled (see Stmt.step in stash/db.lua).
jit.off(M.get)

return M
```

How it fits together:

- **One callback for the whole run.** `write_callback` is created when the module loads and kept in
  a module local. `require` keeps modules forever, so it never needs freeing.
- **The callback writes into a `Buffer`** ([Chapter 14](14-c-data.md)). `body.append` copies curl's
  bytes into the buffer's C memory: no Lua string per piece.
- **The callback can't raise.** The size check returns `0`, so curl stops with `CURLE_WRITE_ERROR`;
  `too_large` tells `get` why. `Buffer:append` could fail (out of memory), so it runs under `pcall`.
- **The error buffer.** `CURLOPT_ERRORBUFFER` takes a `char *` to at least `CURL_ERROR_SIZE` (256)
  bytes, where curl writes a detailed failure message like `Couldn't open file /path`.
  `ffi.new("char[?]", n)` zero-fills it, so `ffi.string(errbuf)` is `""` if curl wrote nothing; then
  `curl_easy_strerror(rc)` gives the generic message.
- **`long(n)`.** Numeric options are C `long`s and `curl_easy_setopt` is variadic, so each is cast.
  Uncast, curl would read garbage.
- **`CURLOPT_PROTOCOLS`** limits curl to HTTP, HTTPS and `file://`. A libcurl built with many
  protocols would otherwise accept `ftp://`, `ldap://`, `telnet://`... from any URL a user types.
  Each protocol is one bit of a number, so the flags combine with bitwise OR. `bit` is LuaJIT's
  built-in bit library: a global, no `require` needed. `bit.bor(a, b, c)` ORs its arguments, here
  `1`, `2` and `1024` into `1027`. [Chapter 17](17-binary-data-and-zlib.md) covers `bit` fully.
- **`CURLOPT_NOSIGNAL`** stops curl from using signals for timeouts; we don't want a signal arriving
  in the middle of Lua code.
- **`FAILONERROR`** turns HTTP errors (404, 500) into curl errors, so we don't save an error page.
- **Getting info back.** `curl_easy_getinfo` writes through an out parameter: `long[1]` for the
  status, `char *[1]` for strings. The strings belong to the handle, so `info_string` copies them
  with `ffi.string` before `ffi.gc` frees the handle.
- **`jit.off(M.get)`**, for the reason above.

`CURLOPT_PROTOCOLS` is deprecated since libcurl 7.85 (a bitmask can't name all the protocols newer
versions support) but still works. Its replacement, `CURLOPT_PROTOCOLS_STR` (option 10318), takes a
string:

```lua
C.curl_easy_setopt(handle, C.CURLOPT_PROTOCOLS_STR, "http,https,file")
```

`stash` keeps the old option because Ubuntu 22.04 ships libcurl 7.81, which lacks the new one. With
7.85 or newer, prefer `CURLOPT_PROTOCOLS_STR`; `fetch.version()` (see the checkpoint) shows yours.

### `src/stash/config.lua`

Two new settings, documented in the header comment:

```lua
-- Configuration: $STASH_HOME/config.lua is a Lua file that sets variables.
--
--   list_limit = 10
--   aliases = { ls = "list", lua = "list -t lua" }
--   color = "never"
--   user_agent = "my-bot/1.0"
--   timeout = 30
```

and added to the defaults:

```lua
M.defaults = {
  list_limit = 20,
  aliases = {},
  color = "auto",
  user_agent = "stash",                      -- sent with every download
  timeout = 10,                              -- seconds, per download
}
```

The [Chapter 8](08-modules.md) type checks apply: `timeout = "30"` is rejected because the default
is a number.

### `src/stash/ffi/sqlite.lua`

Two more opaque types, next to the others:

```lua
typedef struct sqlite3_context sqlite3_context;
typedef struct sqlite3_value sqlite3_value;
```

two more constants at the end of the `enum`:

```lua
  SQLITE_UTF8 = 1,
  SQLITE_DETERMINISTIC = 0x800,
```

and the functions for SQL functions, at the end of the cdef:

```lua
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
```

`sqlite3_create_function_v2` takes three function pointers: `func` for plain functions, `step` and
`final` for aggregates like `sum`. We pass only `func`.

### `src/stash/db.lua`

Add this after `Db:transaction`:

```lua
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
```

- `SQLITE_DETERMINISTIC` promises the same arguments always give the same result, so SQLite can
  optimize.
- Numbers come back as doubles (`sqlite3_result_double`). SQLite stores a whole number like `3.0` in
  an `INTEGER` column as an integer anyway.
- The callbacks would survive without `anchors` (explicit callbacks are never collected), but nothing
  would refer to them. The table makes ownership visible: `stash.db` made them, and they live as long
  as the process.

Then, after `Stmt:step`:

```lua
-- sqlite3_step may call our Lua SQL functions (create_function), and C
-- must never call back into Lua from a JIT-compiled FFI call: LuaJIT
-- stops with "PANIC: ... bad callback". Most steps call no Lua at all,
-- so the JIT would happily compile them; we tell it not to.
jit.off(Stmt.step)
```

`jit.off` comes after `Stmt.step` is defined: it takes the function value itself.

### `src/stash/store.lua`

SQLite parses `x REGEXP p` but has no `regexp` function unless the application provides one. In
`Store.open`, after the `PRAGMA`:

```lua
  db:exec("PRAGMA foreign_keys = ON")         -- SQLite leaves them off by default
  -- `x REGEXP p` calls regexp(p, x). SQLite has no built-in one; ours
  -- uses Lua patterns, case-insensitively: text and pattern are both
  -- lowercased, except %-escapes like %A, whose case is their meaning.
  db:create_function("regexp", 2, function(pattern, text)
    pattern = pattern:gsub("%%?.", function(s) return #s == 1 and s:lower() or s end)
    return text ~= nil and text:lower():find(pattern) ~= nil
  end)
```

Both sides are lowercased, so `^LUA` matches `lua.org`. A plain `pattern:lower()` would break
classes: `%A` (not a letter) would become `%a` (a letter). The `gsub` matches each `%`-escape as a
pair and leaves it alone, lowercasing only single characters.

`list` takes a third filter:

```lua
-- filter.tag, filter.match (a Lua pattern for the title or URL) and
-- filter.limit are optional; a missing parameter is NULL, and LIMIT -1
-- means no limit.
function Store:list(filter)
  local found = {}
  for row in self.db:rows(SELECT .. [[
      WHERE (:tag IS NULL OR e.id IN (SELECT entry_id FROM tags WHERE tag = :tag))
        AND (:match IS NULL OR e.title REGEXP :match OR e.url REGEXP :match)
      ORDER BY e.id LIMIT :limit]],
      { tag = filter.tag, match = filter.match, limit = filter.limit or -1 }) do
    found[#found + 1] = to_entry(row)
  end
  return found
end
```

The parentheses around the tag condition matter: `AND` binds tighter than `OR`.

### `src/stash/commands.lua`

`add` gets `--no-fetch` and the new `fetch.get`. Only HTML is parsed; a PDF or image URL is saved
without title or text.

```lua
command "add" {
  usage = "add URL [-t TAGS] [-n NOTE] [--no-fetch]",
  help = "save a bookmark",
  options = { ["-t"] = { "tags", "list" }, ["-n"] = { "note", "value" },
              ["--no-fetch"] = { "no_fetch", "flag" } },
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
    -- Download the page for its title and the search index.
    local title, text
    if not opts.no_fetch then
      local body, info = fetch.get(url, { user_agent = ctx.config.user_agent,
                                          timeout = ctx.config.timeout })
      if body == nil then
        errors.fail("cannot fetch %s: %s", url, info)
      end
      -- file:// URLs have no content type; trust them to be HTML.
      if info.content_type == nil or info.content_type:find("html") then
        title, text = html.title(body), html.text(body)
      end
    end
    local entry = ctx.store:add(Entry.new({ url = url, title = title, tags = tags,
                                            note = opts.note, created = util.now() }), text)
    ctx.out("added " .. tostring(entry))
  end,
}
```

`list` gets `-m`. A bad pattern would fail deep inside SQLite as a confusing database error (exit
code 2). Checking it first with `pcall(string.find, "", pattern)` makes it a usage error:

```lua
command "list" {
  usage = "list [-t TAG] [-m PATTERN] [--limit N]",
  help = "list bookmarks",
  options = { ["-t"] = { "tag", "value" }, ["-m"] = { "match", "value" },
              ["--limit"] = { "limit", "number" } },
  run = function(ctx, opts)
    -- Check the pattern here, where a mistake is a usage error.
    local valid, err = pcall(string.find, "", opts.match or "")
    if not valid then
      errors.usage("bad pattern '%s': %s", opts.match, err)
    end
    local limit = opts.limit or ctx.config.list_limit
    local filter = { tag = opts.tag, match = opts.match, limit = limit }
    for _, entry in ipairs(ctx.store:list(filter)) do
      ctx.out(format_row(ctx, entry))
    end
  end,
}
```

`help` computes its first column's width, since the usage lines grew:

```lua
command "help" {
  usage = "help",
  help = "show this help",
  run = function(ctx)
    ctx.out("usage: stash <command> [arguments]")
    ctx.out("")
    ctx.out("commands:")
    local width = 0                          -- of the longest usage line
    for _, name in ipairs(order) do
      width = math.max(width, #commands[name].usage)
    end
    for _, name in ipairs(order) do
      local c = commands[name]
      ctx.out(("  %-" .. width .. "s  %s"):format(c.usage, c.help))
    end
  end,
}
```

### Tests

`test/run.lua` runs the new file:

```lua
local FILES = {
  "util_test", "cli_test", "entry_test", "iter_test", "config_test",
  "commands_test", "json_test", "html_test", "fs_test", "term_test",
  "buffer_test", "db_test", "store_test", "fetch_test",
  "e2e_test",
}
```

`test/fetch_test.lua` (new) uses `file://` URLs, so it needs no network:

```lua
local fetch = require("stash.fetch")

local PAGES = "file://" .. os.getenv("PWD") .. "/test/fixtures"

test("file:// URLs are read by curl", function()
  local body, info = fetch.get(PAGES .. "/luajit.html")
  ok(body:find("<title>LuaJIT", 1, true))
  eq(info.status, 0)
  eq(info.content_type, nil)
end)

test("errors come back as messages", function()
  local body, err = fetch.get("file:///no/such/page.html")
  eq(body, nil)
  eq(err, "Couldn't open file /no/such/page.html")
  eq(select(2, fetch.get("ftp://example.com/")),
     'Protocol "ftp" not supported or disabled in libcurl')
end)

test("pages over the size limit are refused", function()
  local saved = fetch.MAX_SIZE
  fetch.MAX_SIZE = 100
  local body, err = fetch.get(PAGES .. "/luajit.html")
  fetch.MAX_SIZE = saved
  eq(body, nil)
  eq(err, "page is larger than 100 bytes")
  ok(fetch.get(PAGES .. "/luajit.html"))     -- and the next download works
end)
```

`test/db_test.lua`: add at the end:

```lua
test("Lua functions can be called from SQL", function()
  local db = memory_db()
  db:create_function("twice", 1, function(s) return s and s .. s end)
  db:create_function("fails", 0, function() error("nope", 0) end)
  eq(db:first("SELECT twice('ab') AS r").r, "abab")
  eq(db:first("SELECT twice(NULL) IS NULL AS r").r, 1)
  raises(function() db:first("SELECT fails()") end, "database: nope")
end)
```

`test/store_test.lua`: add at the end:

```lua
test("list -m matches a Lua pattern against title and URL", function()
  local store = sample_store()
  eq(#store:list({ match = "^alpha" }), 1)              -- case-insensitive
  eq(#store:list({ match = "^ALPHA" }), 1)              -- in the pattern too
  eq(#store:list({ match = "^%A" }), 0)                 -- but %A keeps its meaning
  eq(#store:list({ match = "[bc]%.org" }), 2)
  raises(function() store:list({ match = "[" }) end, "malformed pattern")
end)
```

`test/commands_test.lua`: `add` now downloads, so `"add stores the entry"` passes `--no-fetch`:

```lua
  eq(run(store, { "add", "https://sqlite.org/", "-t", "DB", "--no-fetch" }), "added #3 sqlite.org")
```

and `"errors carry a kind"` checks a bad pattern; add these two lines at its end:

```lua
  err = raises(function() run(sample_store(), { "list", "-m", "[x" }) end, "bad pattern '[x'")
  eq(err.kind, "usage")
```

`test/e2e_test.lua`: in `"add, list, rm round trip"`, add `--no-fetch` to the `example.com` line:

```lua
  eq(stash("add https://example.com/ -t web --no-fetch"), "added #2 example.com\n")
```

Now the tests never touch the network.

### Checkpoint

Where the output shows `/path/to/project/ch16`, you'll see your own path.

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
db_test          8 tests, 0 failed
store_test       9 tests, 0 failed
fetch_test       3 tests, 0 failed
e2e_test         5 tests, 0 failed

71 passed, 0 failed
$ export STASH_HOME=demo STASH_NOW=1767225600
$ PAGES=file://$PWD/test/fixtures
$ ./stash add $PAGES/lua.html -t lua,lang
added #1 The Programming Language Lua
$ ./stash add $PAGES/luajit.html -t lua,jit
added #2 LuaJIT: a Just-In-Time Compiler & FFI
$ ./stash add $PAGES/sqlite.html -t db
added #3 SQLite FTS5 Extension
$ ./stash add https://example.com/ -t web --no-fetch
added #4 example.com
$ ./stash add $PAGES/missing.html; echo "exit $?"
stash: cannot fetch file:///path/to/project/ch16/test/fixtures/missing.html: Couldn't open file /path/to/project/ch16/test/fixtures/missing.html
exit 2
$ ./stash add ftp://example.com/file.txt; echo "exit $?"
stash: cannot fetch ftp://example.com/file.txt: Protocol "ftp" not supported or disabled in libcurl
exit 2
$ ./stash list -m '^lua'
  2  LuaJIT: a Just-In-Time Compiler &...  jit,lua           2026-01-01
$ ./stash list -m 'fixtures/%a+%.html$' -t lua
  1  The Programming Language Lua          lang,lua          2026-01-01
  2  LuaJIT: a Just-In-Time Compiler &...  jit,lua           2026-01-01
$ ./stash list -m '[a-'; echo "exit $?"
stash list: bad pattern '[a-': malformed pattern (missing ']')
usage: stash list [-t TAG] [-m PATTERN] [--limit N]
exit 2
$ ./stash help
usage: stash <command> [arguments]

commands:
  add URL [-t TAGS] [-n NOTE] [--no-fetch]  save a bookmark
  list [-t TAG] [-m PATTERN] [--limit N]    list bookmarks
  search WORDS...                           full-text search, best matches first
  show ID                                   show one bookmark
  rm ID                                     delete a bookmark
  tags                                      count bookmarks per tag
  export [FILE]                             write all bookmarks as JSON
  help                                      show this help
  version                                   print the version
$ LUA_PATH="src/?.lua" luajit -e 'local f = require("stash.fetch") local body, info = f.get("file://" .. os.getenv("PWD") .. "/test/fixtures/lua.html") print(#body, info.status, info.url)'
237	0	file:///path/to/project/ch16/test/fixtures/lua.html
$ LUA_PATH="src/?.lua" luajit -e 'print(require("stash.fetch").version())'
libcurl/7.81.0 OpenSSL/3.0.2 zlib/1.2.11 brotli/1.0.9 zstd/1.4.8 libidn2/2.3.2 libpsl/0.21.0 (+libidn2/2.3.2) libssh/0.9.6/openssl/zlib nghttp2/1.43.0 librtmp/2.3 OpenLDAP/2.5.20
```

The last line is your libcurl's version and build options; yours will differ. A `file://` download
has status `0` (no HTTP). `list -m '^lua'` matches `LuaJIT: ...` but not
`The Programming Language Lua`: `^` anchors the pattern at the start of the title or URL.

With a network connection, `./stash add https://www.lua.org/` downloads the real page.

The complete project at this point is in `project/ch16/`.

## Summary

- `ffi.cast("fnptr type", lua_function)` makes a callback: a C function pointer that runs Lua.
  `cb:set(fn)` changes its function; `cb:free()` releases it.
- Callback slots are limited (500–1000) and never collected. Passing a Lua function directly makes a
  permanent callback per call. Cast once and reuse.
- Inside a callback, `pcall` everything and report errors the C way (a return value,
  `sqlite3_result_error`). Keep callbacks cheap.
- A C function that calls back into Lua must not be called from JIT-compiled code ("bad callback"
  PANIC). `jit.off()` the Lua function that makes the call.
- Variadic arguments: a Lua number is a `double`. Cast to `int` or `long` when C expects one.
- libcurl: init, setopt, perform, cleanup. The body arrives through `CURLOPT_WRITEFUNCTION`; details
  come from an error buffer and `curl_easy_getinfo` out parameters.
- `CURLOPT_PROTOCOLS` is deprecated since 7.85 in favor of `CURLOPT_PROTOCOLS_STR`.
- `sqlite3_create_function_v2` lets SQL call Lua functions, such as `REGEXP`.

## Exercises

1. Write `sort_strings(t)`, which sorts a Lua array of strings with `qsort` and a Lua comparator:
   copy the strings into a `const char *[?]` array, sort it, copy them back. Compare its speed with
   `table.sort` on 100,000 strings, using `os.clock()`.

   <details><summary>Solution</summary>

   ```lua
   local ffi = require("ffi")
   ffi.cdef [[
   void qsort(void *base, size_t count, size_t size, int (*compare)(const void *, const void *));
   int strcmp(const char *a, const char *b);
   ]]

   local compare = ffi.cast("int (*)(const void *, const void *)", function(a, b)
     local pa, pb = ffi.cast("const char **", a), ffi.cast("const char **", b)
     return ffi.C.strcmp(pa[0], pb[0])
   end)

   local function sort_strings(t)
     local n = #t
     local array = ffi.new("const char *[?]", n)
     for i = 1, n do
       array[i - 1] = t[i]                    -- the pointer is valid while t holds the string
     end
     ffi.C.qsort(array, n, ffi.sizeof("const char *"), compare)
     for i = 1, n do
       t[i] = ffi.string(array[i - 1])
     end
   end

   local function words(n)
     local t = {}
     for i = 1, n do t[i] = tostring(math.random(1e9)) end
     return t
   end

   local a, b = words(100000), words(100000)
   local start = os.clock()
   sort_strings(a)
   print(("qsort       %.3f s"):format(os.clock() - start))
   start = os.clock()
   table.sort(b)
   print(("table.sort  %.3f s"):format(os.clock() - start))
   ```

   ```console
   qsort       0.944 s
   table.sort  0.039 s
   ```

   Your numbers will differ, but `qsort` loses clearly: every comparison crosses from C into Lua.
   Storing the string pointers is safe only because `t` holds every string while `qsort` runs; the
   pointers are replaced right after.

   </details>

2. With `Db:create_function`, register a Lua function `title_case(s)` that capitalizes the first
   letter of each word, and use it in `SELECT title_case('hello lua world') AS t`.

   <details><summary>Solution</summary>

   Save this as `title_case.lua` in the project directory:

   ```lua
   package.path = "src/?.lua;" .. package.path
   local Db = require("stash.db")
   local db = assert(Db.open(":memory:"))
   db:create_function("title_case", 1, function(s)
     return s and (s:gsub("(%a)(%w*)", function(first, rest) return first:upper() .. rest end))
   end)
   print(db:first("SELECT title_case('hello lua world') AS t").t)
   ```

   ```console
   $ luajit title_case.lua
   Hello Lua World
   ```

   The parentheses around `s:gsub(...)` keep only its first result. Without them the count (3) would
   be a second result; `to_sql` ignores it, but don't rely on that.

   </details>

3. Make `fetch.get` set `CURLOPT_VERBOSE` (number 41, a `long`) when the environment variable
   `STASH_DEBUG` is set. What happens if you pass `1` instead of `ffi.cast("long", 1)`?

   <details><summary>Solution</summary>

   Add `CURLOPT_VERBOSE = 41,` to the `enum` in `stash/ffi/curl.lua`, then in `fetch.get`:

   ```lua
   if os.getenv("STASH_DEBUG") then
     C.curl_easy_setopt(handle, C.CURLOPT_VERBOSE, long(1))
   end
   ```

   curl then prints the transfer details on stderr. For an `https://` URL: the connection, the TLS
   handshake and the headers, in lines starting with `*`, `>` and `<`.

   With a plain `1`, the FFI passes a `double`. On x86-64, doubles travel in different registers than
   integers, so curl reads whatever is in the integer register. Verbose mode may or may not turn on,
   silently. That's why every numeric option in `fetch.lua` goes through `long()`.

   </details>

4. `on_write` returns `0` to stop a too-large download. Call `fetch.get` on a `file://` URL with
   `fetch.MAX_SIZE = 100` and print the curl error you'd get if `get` didn't check `too_large` first.
   (Hint: temporarily print `rc` and `curl_easy_strerror(rc)` inside `get`.)

   <details><summary>Solution</summary>

   Temporarily add after `curl_easy_perform`:

   ```lua
   print(rc, ffi.string(C.curl_easy_strerror(rc)))
   ```

   ```console
   $ LUA_PATH="src/?.lua" luajit -e 'local f = require("stash.fetch") f.MAX_SIZE = 100 print(f.get("file://" .. os.getenv("PWD") .. "/test/fixtures/lua.html"))'
   23	Failed writing received data to disk/application
   nil	page is larger than 100 bytes
   ```

   `23` is `CURLE_WRITE_ERROR`. curl's message blames "disk/application", which would confuse a user;
   the `too_large` flag lets `stash` say what really happened.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-16--callbacks-and-libcurl)
