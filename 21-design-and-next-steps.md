# Chapter 21 — Design and Next Steps

`stash` is done: a bookmark manager in Lua that drives SQLite, libcurl and zlib through the FFI,
takes plugins, and ships as one binary. This last chapter steps back: the ideas behind Lua and
LuaJIT that shaped every chapter, the conventions `stash` followed, the mistakes worth
remembering, and how LuaJIT relates to today's PUC Lua. Then `stash` gets version 1.0.0 and a
README, and you get a map of where to go next. [Chapter 20](20-embedding-luajit.md) packed
`stash` into one program; from here on, the appendices are your reference.

## Lua's design ideals

Lua was created in 1993 at PUC-Rio in Brazil, to be embedded in programs written in C. Its
authors describe it as powerful, efficient, lightweight and embeddable. Each word shows up as a
design choice you used.

### A small core

Count what the standard library offers:

`examples/ch21/small.lua`

```lua
-- How big is Lua? Count the functions in each standard library table.

local libs = { "_G", "string", "table", "math", "io", "os",
               "coroutine", "debug", "package", "bit", "jit", "ffi" }

local total = 0
for _, name in ipairs(libs) do
  local t = name == "_G" and _G or (_G[name] or require(name))
  local n = 0
  for _, v in pairs(t) do
    if type(v) == "function" then n = n + 1 end
  end
  total = total + n
  print(("%-10s %3d functions"):format(name, n))
end
print(("%-10s %3d"):format("total", total))

local kinds = {}
for _, v in pairs(_G) do
  kinds[type(v)] = (kinds[type(v)] or 0) + 1
end
print("globals by type:", kinds["function"], "functions,", kinds.table, "tables")
```

```console
$ luajit examples/ch21/small.lua
_G          29 functions
string      14 functions
table        9 functions
math        28 functions
io          11 functions
os          11 functions
coroutine    7 functions
debug       16 functions
package      3 functions
bit         12 functions
jit          6 functions
ffi         17 functions
total      163
globals by type:	29	functions,	12	tables
```

About 160 functions, 35 of them LuaJIT's additions (`bit`, `jit`, `ffi`). Lua leaves everything
else to the host program and to libraries. PUC Lua 5.5's source is about 32,000 lines of C; you
can read all of it.

A small core is a feature:

- **Easy to embed.** A host adds what its users need (`stash` added `stash.*` for plugins) and
  nothing else.
- **Easy to learn whole.** You have now seen almost every function counted above.
- **Easy to port.** Lua is plain ISO C and builds anywhere with a C compiler.

### Mechanisms, not policies

In its authors' words, Lua provides *meta-mechanisms* for implementing features instead of a
host of features built into the language. Lua has no classes, but metatables let you build them.
It has no module syntax, but `require` and tables make one. `stash` built each policy it needed
from a mechanism:

| Mechanism | Policy `stash` built with it | Chapter |
|-----------|------------------------------|---------|
| Metatables, `__index` | the `Entry` and `Store` classes | [7](07-metatables-and-objects.md) |
| Tables + `require` | one table per module | [8](08-modules.md) |
| Environments (`setfenv`) | `config.lua` as a settings file; plugin sandboxes | [8](08-modules.md), [19](19-plugins-and-scripting.md) |
| `error` with any value | error tables with a `kind` and exit codes | [9](09-errors.md) |
| `__index`/`__newindex` on `_G` | `stash.strict`: no accidental globals | [9](09-errors.md) |
| Coroutines | streaming iterators | [11](11-coroutines.md) |
| `ffi.gc`, `ffi.metatype` | C objects that clean up after themselves | [14](14-c-data.md), [15](15-wrapping-sqlite.md) |
| `package.loaders` | modules linked into the binary | [20](20-embedding-luajit.md) |

The price: every Lua project builds its own policies, so two Lua codebases can look different,
and one project's class library isn't another's. Hence the conventions below.

### One data structure

The table is Lua's only data structure: array, record, dictionary, set, module, object, class,
namespace and environment. One structure means one set of rules to learn and one thing for the
implementation to make fast. Inside, a table keeps an array part next to its hash part, so a
table used as an array is stored as compactly as an array.

### Economy

Lua reuses ideas instead of adding new ones:

- **Functions are values**, so callbacks, methods, modules and plugin APIs all use closures.
- **Strings are immutable.** LuaJIT interns them all, so comparing two strings is a pointer
  comparison.
- **Multiple returns** replace output parameters, and replace exceptions for expected failures
  (`nil, message`).
- **Chunks are functions**, so a config file, a plugin and a module all load the same way.

## LuaJIT's ideals

LuaJIT, by Mike Pall, is an independent implementation of Lua 5.1. Its goals add to Lua's:

- **Performance through simplicity.** A fast interpreter written in assembler, plus a tracing JIT
  that compiles only the hot paths it actually sees ([Chapter 18](18-performance-and-the-jit.md)).
  Simple code (loops over arrays, numbers, plain tables) is what it makes fastest.
- **Drop-in compatible.** LuaJIT keeps Lua 5.1's language, C API and even ABI. A C module built
  for Lua 5.1 loads into LuaJIT unchanged, and `luajit` replaces `lua`.
- **The FFI instead of bindings.** Paste C declarations and call C from Lua. For C data access,
  the JIT generates code on par with a C compiler's. You wrote no C until Chapter 20, and then
  only to *start* Lua.
- **Small and embeddable.** `build/stash` is about 2.3 MB, more than half of it SQLite.

LuaJIT uses **rolling releases**: no tarballs, just a git branch. The version number's last part
is the timestamp of the latest commit, which is why `luajit -v` prints a number like
`2.1.1792588164`. Version 2.1 is the production branch.

## Conventions

Lua has no official style guide, so pick one and stick to it. The conventions `stash` used, and
why:

| Topic | Convention in `stash` | Why |
|-------|-----------------------|-----|
| Indentation | 2 spaces | the most common choice: the manual and *Programming in Lua* use it |
| Variables, functions | `lower_snake_case` | matches the standard library (`string.byte`, `table.concat`) |
| Classes | `CamelCase`: `Entry`, `Store`, `Db` | tells you `.new` and methods are there |
| Constants | `UPPER_CASE`: `VERSION`, `SAFE` | a promise, not enforced (LuaJIT has no `<const>`; the `const` of newer builds isn't portable) |
| Unused values | `_`: `for _, v in ipairs(t)` | says "ignored" on purpose |
| Scope | `local` everything; `stash.strict` turns a global by mistake into an error | globals are slow, shared, and typos become `nil` |
| Modules | requires at the top, a `local M = {}`, `return M`; no globals | a module is just its return value |
| C bindings | one `src/stash/ffi/*.lua` per library, wrapped by a Lua module | `cdef`s in one place; the rest of the code never touches raw C |
| Expected failures | `return nil, message` (e.g. `cli.parse`, `config.load`) | the caller decides what to do |
| Problems for the user | raise an error table with `errors.usage`, `not_found` or `fail` | one place (`main`) turns them into messages and exit codes |
| Bugs | anything else; `STASH_DEBUG` prints its traceback | a bug should be loud |
| Performance | measure first, then cache in locals, avoid garbage | [Chapter 18](18-performance-and-the-jit.md) |
| Comments | say *why*, not *what* | the code already says what |

A linter catches what conventions miss: undefined and unused variables, shadowing. `luacheck` is
the usual one; `--std luajit` makes it know LuaJIT's extra globals (`jit`, `bit`).

## Common pitfalls

Most Lua bugs come from a short list, each shown here in a few lines:

`examples/ch21/pitfalls.lua`

```lua
-- The mistakes Lua programmers make most, each in a few lines.

-- 1. Only nil and false are false. 0 and "" are true.
local count = 0
if count then print("1. 0 is true") end

-- 2. # on a table with holes: any border is a valid answer.
local t = { 1, 2, nil, 4 }
print("2. #t =", #t, "(could be 2 or 4)")

-- 3. a and b or c is not a ternary when b can be false or nil.
local enabled = false
local setting = true and enabled or "default"
print("3. setting =", setting)

-- 4. Forgetting local makes a global.
local function count_words(s)
  n = 0                           -- oops: global n
  for _ in s:gmatch("%S+") do n = n + 1 end
  return n
end
count_words("a b c")
print("4. global n =", n)

-- 5. Indexes start at 1; t[0] is just another key.
local list = { "a", "b" }
list[0] = "zero"
print("5. #list =", #list, "unpack sees:", select("#", unpack(list)))

-- 6. String functions count bytes, not characters.
local word = "naïve"
print("6. #word =", #word, ("%-7s|"):format(word))

-- 7. . vs : calls.
local obj = { name = "obj" }
function obj:hello() return "hello from " .. tostring(self and self.name) end
print("7.", obj:hello(), pcall(obj.hello))

-- 8. A NULL pointer is cdata, not nil, and it is truthy.
local ffi = require("ffi")
local p = ffi.cast("void *", 0)
print("8. p == nil:", p == nil, "type:", type(p), "truthy:", not not p)

-- 9. 64-bit integers from C are cdata: 1LL ~= 1 as a table key.
local big = ffi.new("int64_t", 1)
local keys = { [1] = "number key" }
print("9.", big == 1, keys[big], tonumber(big) == 1, keys[tonumber(big)])

-- 10. Strings are immutable: gsub and friends return a new string.
local s = "hello"
s:upper()
print("10.", s, s:upper())
```

```console
$ luajit examples/ch21/pitfalls.lua
1. 0 is true
2. #t =	4	(could be 2 or 4)
3. setting =	default
4. global n =	3
5. #list =	2	unpack sees:	2
6. #word =	6	naïve |
7.	hello from obj	true	hello from nil
8. p == nil:	true	type:	cdata	truthy:	true
9.	true	nil	true	number key
10.	hello	HELLO
```

| # | Pitfall | Fix | Chapter |
|---|---------|-----|---------|
| 1 | `0` and `""` are true | test `x ~= 0`, `x ~= ""` | [2](02-values-and-types.md) |
| 2 | `#` on a table with holes | keep an explicit count (`n`), or no holes | [5](05-tables.md) |
| 3 | `a and b or c` when `b` is `false` | use an `if` | [3](03-control-flow.md) |
| 4 | missing `local` | `local`; `strict`; a linter | [4](04-functions.md), [9](09-errors.md) |
| 5 | `t[0]` isn't part of the array | start at 1 | [5](05-tables.md) |
| 6 | `#` and `%-7s` count bytes | count characters with a UTF-8 pattern | [6](06-strings.md) |
| 7 | `obj.method()` instead of `obj:method()` | `:` passes `self` | [7](07-metatables-and-objects.md) |
| 8 | a NULL pointer is truthy cdata | test `p == nil` | [13](13-ffi-basics.md) |
| 9 | 64-bit cdata isn't a number key | `tonumber(x)` before using it as a key | [14](14-c-data.md) |
| 10 | `s:upper()` doesn't change `s` | `s = s:upper()` | [6](06-strings.md) |

Two more take more than a line to show:

- **Leaking C memory.** Every pointer from C needs an owner: `ffi.gc`, a `close` method, or a
  comment saying who frees it ([Appendix B](appendix-b-ffi-reference.md) has a checklist).
- **Letting the GC free what C still uses.** A cdata or Lua string passed to C must stay
  referenced from Lua as long as C keeps the pointer: callbacks, buffers, `CURLOPT_*` strings
  ([Chapter 16](16-callbacks-and-curl.md)).

## PUC Lua 5.4 and 5.5 vs LuaJIT

The Lua team kept changing the language after 5.1. LuaJIT stayed with 5.1 and took only the 5.2
features that don't break existing code ([Appendix C](appendix-c-lua-versions.md) lists them).
So there are now two Luas. As of this writing, Lua 5.5 (December 2025) is the current PUC Lua,
and 5.4 gets no further releases.

| | LuaJIT 2.1 | PUC Lua 5.4 / 5.5 |
|--|------------|-------------------|
| Speed | a JIT: much faster on hot loops | a fast interpreter |
| C libraries | the FFI, from Lua | the C API, or a C library binding |
| Numbers | doubles only (plus 64-bit cdata) | integers and floats, `//`, bitwise operators |
| Environments | `setfenv` / `getfenv` | `_ENV`, `load(..., env)` |
| Newer features | `goto`, some 5.2 library features | `<const>`, `<close>`, `utf8`, and in 5.5 `global` declarations |
| Where it's used | games, OpenResty, Neovim, embedded | everywhere else, and where a JIT isn't allowed |

> LuaJIT 2.1 builds from July 2026 on also accept the bitwise operators `&`, `|`, `~`, `<<`, `>>`
> (32-bit, like the `bit` library) and other syntax backported from LuaJIT 3.0, but not `//`.
> Code that uses them runs only on those builds. [Appendix C](appendix-c-lua-versions.md) has the
> list.

Code that sticks to the shared subset runs on both. Detect features, not versions:

`examples/ch21/versions.lua`

```lua
-- One file, several Lua versions: detect features instead of versions.

print("_VERSION:", _VERSION)
print("LuaJIT:", jit and jit.version or "no")

local unpack = table.unpack or unpack          -- 5.1 has a global unpack
print("unpack:", unpack({ 1, 2, 3 }))

print("integers:", math.type and math.type(1) or "no integer subtype")
print("10 / 2 =", 10 / 2, " 2^53 + 1 =", 9007199254740993)

-- Run a chunk with its own globals, on any version.
local function run_with_env(code, env)
  if setfenv then                              -- Lua 5.1, LuaJIT
    local f = assert(loadstring(code))
    return setfenv(f, env)()
  end
  return assert(load(code, "=code", "t", env))()   -- Lua 5.2+
end
print("sandboxed:", run_with_env("return greeting", { greeting = "hi" }))
```

```console
$ luajit examples/ch21/versions.lua
_VERSION:	Lua 5.1
LuaJIT:	LuaJIT 2.1.1792588164
unpack:	1	2	3
integers:	no integer subtype
10 / 2 =	5	 2^53 + 1 =	9.007199254741e+15
sandboxed:	hi
$ lua5.4 examples/ch21/versions.lua
_VERSION:	Lua 5.4
LuaJIT:	no
unpack:	1	2	3
integers:	integer
10 / 2 =	5.0	 2^53 + 1 =	9007199254740993
sandboxed:	hi
```

(Your PUC Lua command may be `lua` or `lua5.4`.) Look at `10 / 2` and the big number:

- Lua 5.4 has an integer subtype. `/` always gives a float (`5.0`). Integers are exact up to
  2^63, so `9007199254740993` stays exact.
- LuaJIT has only doubles: `5` prints without `.0`, and 2^53 + 1 can't be represented exactly.

[Appendix C](appendix-c-lua-versions.md) lists every difference you'd hit moving `stash`-style
code to PUC Lua.

## The ecosystem

With a small core, you'll use libraries and frameworks. Some places to go:

| Project | What it is | Lua |
|---------|------------|-----|
| [LuaRocks](https://luarocks.org/) | the package manager for Lua modules: `luarocks install luacheck` | any |
| [OpenResty](https://openresty.org/) | nginx with LuaJIT inside: web apps and gateways scripted in Lua | its own LuaJIT fork |
| [Neovim](https://neovim.io/) | the editor; configs (`init.lua`) and plugins are Lua | Lua 5.1 API; built with LuaJIT where it can be |
| [LÖVE](https://love2d.org/) | a framework for 2D games | Lua or LuaJIT, depending on the build |
| [Defold](https://defold.com/) | a game engine with Lua scripting | LuaJIT on most platforms, Lua 5.1 on HTML5 |

Each one is a C or C++ program that embeds Lua and hands scripts an API table: the `stash`
plugin pattern at a bigger scale. Neovim even tells plugin authors to check `if jit then ... end`
before using LuaJIT extras.

## Building stash: version 1.0.0

`stash` gets its last changes:

- The version becomes `1.0.0`.
- `stash version -v` also prints the versions of LuaJIT and the three C libraries: the first
  thing you ask for in a bug report.
- A `README.md` documents the program for its users.

Start from your `project/ch20` code. One file changes, one test is added, and the README is new.

### `src/stash/commands.lua`: `version -v`

Two more requires at the top, in alphabetical order with the others, and the new version:

```lua
local compress = require("stash.compress")
local Db = require("stash.db")
local Entry = require("stash.entry")
local errors = require("stash.errors")
local fetch = require("stash.fetch")
local fs = require("stash.fs")
local html = require("stash.html")
local json = require("stash.json")
local util = require("stash.util")

local VERSION = "1.0.0"
```

Replace the `version` command:

```lua
command "version" {
  usage = "version [-v]",
  help = "print the version (-v: and the libraries' versions)",
  options = { ["-v"] = { "verbose", "flag" } },
  run = function(ctx, opts)
    ctx.out("stash " .. VERSION)
    if opts.verbose then
      ctx.out(jit.version)
      ctx.out("SQLite " .. Db.version())
      ctx.out("zlib " .. compress.version())
      ctx.out(fetch.version())
    end
  end,
}
```

Each library got a `version()` function in the chapter that wrapped it: `Db.version()` calls
`sqlite3_libversion`, `compress.version()` calls `zlibVersion`, and `fetch.version()` calls
`curl_version`. `jit.version` is a string.

Inside `build/stash`, `SQLite` reports the static library linked in, which can differ from the
shared one `./stash` loads. `version -v` tells you which one is running.

### `test/commands_test.lua`: a test for `-v`

Add `local util = require("stash.util")` to the requires at the top, and this test at the end:

```lua
test("version -v names the C libraries too", function()
  local lines = util.split(run(sample_store(), { "version", "-v" }), "\n")
  eq(lines[1], "stash 1.0.0")
  ok(lines[2]:find("^LuaJIT 2%.1"), lines[2])
  ok(lines[3]:find("^SQLite 3%."), lines[3])
  ok(lines[4]:find("^zlib 1%."), lines[4])
  ok(lines[5]:find("^libcurl/"), lines[5])
end)
```

Versions differ between machines, so the test checks only their shape.

### `README.md`: user documentation (new)

Users don't read the source. They need to know what the program does, what it needs, how to run
it, and where it keeps their data. Keep it short and true: every command in it should work as
written.

````markdown
# stash

A command-line bookmark manager with full-text search, written in Lua for
LuaJIT. stash saves a URL, downloads the page, and keeps its text
searchable and its HTML compressed in an SQLite database. It is the
project of the course *Learn Lua (LuaJIT) by Building stash*.

```
$ stash add file://$PWD/test/fixtures/lua.html -t lua,lang
added #1 The Programming Language Lua
$ stash search scripting
  1  The Programming Language Lua          lang,lua          2026-01-01
     ...a small, fast [scripting] language built to be...
```

## Requirements

- LuaJIT 2.1 (any build from 2023 or later)
- The shared libraries SQLite 3 (with FTS5), libcurl and zlib. On
  Debian/Ubuntu: `libsqlite3-0 libcurl4 zlib1g`.
- To build the single-file program: a C compiler, LuaJIT's headers and
  static library, and the static SQLite and zlib libraries
  (`libsqlite3-dev zlib1g-dev`).

## Running

From this directory, without building anything:

```
./stash help
```

Or build the single-file program `build/stash`, which needs neither
LuaJIT nor the Lua sources to run (libcurl is still loaded at run time):

```
make
make test        # the tests with luajit, then end-to-end with build/stash
make clean
```

## Commands

```
add URL [-t TAGS] [-n NOTE] [--no-fetch]  save a bookmark
list [-t TAG] [-m PATTERN] [--limit N]    list bookmarks
search WORDS...                           full-text search, best matches first
show ID [--body]                          show one bookmark, or its saved page
rm ID                                     delete a bookmark
tags                                      count bookmarks per tag
export [FILE]                             write all bookmarks as JSON
stats                                     count entries and the space pages take
plugins                                   list the loaded plugins
help                                      show this help
version [-v]                              print the version (-v: and the libraries' versions)
```

Exit codes: 0 success, 1 not found (or no search results), 2 usage error
or failure.

## Files and settings

Data lives in `$STASH_HOME` (default `~/.local/share/stash`):

- `stash.db`: the SQLite database.
- `config.lua`: settings, as Lua assignments:

  ```lua
  list_limit = 10
  aliases = { ls = "list", lua = "list -t lua" }
  color = "auto"                         -- or "always", "never"
  user_agent = "stash"
  timeout = 10                           -- seconds per download
  plugins = { "autotag", "wordcount", "checksum" }
  trusted_plugins = { "checksum" }       -- may use require and the FFI
  ```

- `plugins/NAME.lua`: plugins. `plugins/` here has three examples.

Environment: `STASH_HOME`; `NO_COLOR` turns color off; `COLUMNS` sets the
width when stdout is not a terminal; `STASH_NOW` (seconds since 1970)
fixes the clock, for tests; `STASH_DEBUG` adds tracebacks to internal
errors.

## Plugins

A plugin is a Lua file run in a sandbox that holds a few safe globals and
the `stash` table:

```lua
stash.command("hello", {
  usage = "hello [NAME]",
  help = "say hello",
  run = function(opts) stash.print("hello, " .. (opts[1] or "world")) end,
})
stash.on("add", function(entry) entry.tags[#entry.tags + 1] = "new" end)
```

The rest of the API: `stash.entries()`, `stash.get(id)`, `stash.page(id)`,
`stash.text(html)`, `stash.paint(text, style)`, `stash.fail(fmt, ...)`,
`stash.not_found(fmt, ...)`. The sandbox stops accidents, not attacks:
only install plugins you trust as much as any other program.

## Layout

```
stash                launcher: runs src/ with luajit
src/stash/           the modules; src/stash/ffi/ holds the C bindings
plugins/             example plugins
test/run.lua         test runner: luajit test/run.lua [FILTER]
bench/               benchmarks: luajit bench/run.lua [-p] [FILTER]
host/, Makefile      the single-file build
```
````

### Checkpoint

```console
$ luajit test/run.lua | tail -1
87 passed, 0 failed
$ ./stash version
stash 1.0.0
$ ./stash version -v
stash 1.0.0
LuaJIT 2.1.1792588164
SQLite 3.37.2
zlib 1.2.11
libcurl/7.81.0 OpenSSL/3.0.2 zlib/1.2.11 brotli/1.0.9 zstd/1.4.8 libidn2/2.3.2 libpsl/0.21.0 (+libidn2/2.3.2) libssh/0.9.6/openssl/zlib nghttp2/1.43.0 librtmp/2.3 OpenLDAP/2.5.20
$ make 2>&1 | tail -1
cc -I/usr/local/include/luajit-2.1 -Ibuild -Ibuild/bc -O2 -Wall -Wl,-E -o build/stash host/main.c /usr/local/lib/libluajit-5.1.a -Wl,--whole-archive -l:libsqlite3.a -l:libz.a -Wl,--no-whole-archive -lm -ldl -lpthread
$ STASH_BIN=build/stash luajit test/run.lua e2e | tail -1
6 passed, 0 failed
$ build/stash version -v | head -3
stash 1.0.0
LuaJIT 2.1.1792588164
SQLite 3.37.2
$ make clean
rm -rf build
$ export STASH_HOME=demo STASH_NOW=1767225600
$ ./stash add file://$PWD/test/fixtures/lua.html -t lua,lang
added #1 The Programming Language Lua
$ ./stash search scripting
  1  The Programming Language Lua          lang,lua          2026-01-01
     ...a small, fast [scripting] language built to be...
$ rm -r demo
```

The version lines are your own: the LuaJIT timestamp, the library versions, and especially the
long libcurl line, which lists what your libcurl was built with. The `cc` line shows your LuaJIT
prefix.

The complete project at this point is in `project/ch21/`: the finished `stash`.

## Where next

You know the whole language, the FFI, and how to embed LuaJIT. Some ways to go deeper:

- **Read the manuals.** The [Lua 5.1 reference manual](https://www.lua.org/manual/5.1/) is short
  and exact, and it's LuaJIT's language. The [LuaJIT docs](https://luajit.org/luajit.html) cover
  the FFI, `jit.*` and the extensions.
- **Read *Programming in Lua*** by Roberto Ierusalimschy, Lua's chief architect. The first
  edition (Lua 5.0) is [free online](https://www.lua.org/pil/contents.html); later editions cover
  newer versions.
- **Read source code.** PUC Lua's C source is small and clear; start with `lvm.c` and `ltable.c`.
  LuaJIT's is dense but rewarding; traces are built in `src/lj_record.c`.
- **Move to PUC Lua 5.4 or 5.5** for a project that can't use LuaJIT. Start with
  [Appendix C](appendix-c-lua-versions.md).
- **Embed Lua in your own program.** Any C, C++, Go, Rust or Zig program can host it. Give your
  users an API table and a sandbox, as in Chapter 19.
- **Grow `stash`.** Some ideas: an `import` command for browser bookmark exports, `search`
  ranking by tag, a `serve` command with a tiny HTTP server, async downloads with coroutines and
  libcurl's multi interface, or a plugin that syncs with another machine.

The community lives on the [lua-l mailing list](https://www.lua.org/lua-l.html), the
[LuaJIT list](https://luajit.org/list.html) and the [lua-users wiki](http://lua-users.org/wiki/).

## Summary

- Lua's ideals are a **small core**, **mechanisms instead of policies**, **one data structure**,
  **embeddability** and **economy**. `stash` built classes, modules, sandboxes and error kinds
  from a handful of mechanisms.
- LuaJIT adds **speed through a simple, tracing JIT**, **the FFI**, and **drop-in Lua 5.1
  compatibility**. It uses rolling releases.
- **Conventions** make Lua code readable across projects: `local` everything, one table per
  module, `nil, message` for expected failures, errors for problems, `CamelCase` classes.
- The **pitfalls** are few and well known: truthiness, `#` with holes, `and`/`or`, globals,
  bytes vs characters, `.` vs `:`, NULL cdata, 64-bit cdata.
- **PUC Lua 5.4/5.5** and **LuaJIT** are two dialects of one language. Detect features to write
  code that runs on both.
- The **ecosystem** (LuaRocks, OpenResty, Neovim, LÖVE, Defold) is mostly programs that embed
  Lua, as `stash` does for its plugins.
- `stash` 1.0.0 reports its library versions and has a README.

## Exercises

1. This code should print the tags used by at least two bookmarks: `jit 2` and `lua 3`. It
   prints nothing. Find the bugs, including the one that doesn't cause the wrong output yet.

   ```lua
   -- Prints the tags used by at least `min` bookmarks.
   function tag_counts(entries)
     counts = {}
     for _, e in ipairs(entries) do
       for _, tag in ipairs(e.tags) do
         counts[tag] = counts[tag] or 0 + 1
       end
     end
     return counts
   end
   
   local function show(counts, min)
     for tag, n in pairs(counts) do
       if n >= min then print(tag, n) end
     end
   end
   
   local entries = {
     { tags = { "lua", "jit" } },
     { tags = { "lua", "ffi" } },
     { tags = { "lua", "jit" } },
   }
   show(tag_counts(entries), 2)    -- expected: jit 2, lua 3
   ```

<details><summary>Solution</summary>

Three problems:

- **`counts[tag] or 0 + 1`** parses as `counts[tag] or (0 + 1)`, because `+` binds tighter than
  `or`. The first time it stores `1`; after that `counts[tag]` is `1` and stays `1`, so no count
  reaches 2. Write `(counts[tag] or 0) + 1`.
- **`counts = {}` is a global**, and so is the function `tag_counts`. Both work here, but would
  clash with any other code using those names. Add `local` to both; `stash.strict` or a linter
  would catch them.
- **`pairs` order is unspecified**, so even when fixed, `lua` might print before `jit`. Sort the
  keys if order matters.

```lua
-- Prints the tags used by at least `min` bookmarks.
local function tag_counts(entries)
  local counts = {}
  for _, e in ipairs(entries) do
    for _, tag in ipairs(e.tags) do
      counts[tag] = (counts[tag] or 0) + 1
    end
  end
  return counts
end

local function show(counts, min)
  local tags = {}
  for tag in pairs(counts) do tags[#tags + 1] = tag end
  table.sort(tags)
  for _, tag in ipairs(tags) do
    if counts[tag] >= min then print(tag, counts[tag]) end
  end
end

local entries = {
  { tags = { "lua", "jit" } },
  { tags = { "lua", "ffi" } },
  { tags = { "lua", "jit" } },
}
show(tag_counts(entries), 2)    -- expected: jit 2, lua 3
```

```console
$ luajit hunt.lua
jit	2
lua	3
```

</details>

2. Run `examples/ch19/env.lua` with PUC Lua 5.4 (`lua5.4`). It fails. Port it so it runs on both
   LuaJIT and Lua 5.4, with the same output except for the error message wording.

<details><summary>Solution</summary>

```console
$ lua5.4 examples/ch19/env.lua
lua5.4: examples/ch19/env.lua:10: attempt to call a nil value (global 'loadstring')
stack traceback:
	examples/ch19/env.lua:10: in main chunk
	[C]: in ?
```

Lua 5.2 removed `loadstring`, `setfenv` and `getfenv`; pass the environment to `load` instead.
LuaJIT's `load` takes the same arguments, so one version runs on both:

```lua
-- examples/ch19/env.lua, ported: load takes the environment.

local code = [[
greeting = "hello from the plugin"      -- a global assignment...
function shout(s) return s:upper() end  -- ...and a global function
print(greeting)                          -- which print? the env's
]]

local env = { print = function(...) print("[plugin]", ...) end }
local chunk = assert(load(code, "=plugin", "t", env))
chunk()

print(greeting)                         -- nil: our globals are untouched
print(env.greeting)                     -- the chunk's globals live in env
print(env.shout("quiet"))               -- functions it defines keep env

-- Without print in its environment, the chunk can't print at all.
local bare = assert(load("print('hi')", "=bare", "t", {}))
print(pcall(bare))
```

```console
$ luajit env.lua
[plugin]	hello from the plugin
nil
hello from the plugin
QUIET
false	bare:1: attempt to call global 'print' (a nil value)
$ lua5.4 env.lua
[plugin]	hello from the plugin
nil
hello from the plugin
QUIET
false	bare:1: attempt to call a nil value (global 'print')
```

The `getfenv(env.shout) == env` line has no portable version. In Lua 5.2+, a function's
environment is its `_ENV` upvalue, which `debug.getupvalue` can read, but `shout` uses no
globals, so it has no `_ENV` upvalue at all.

</details>

3. Lua's authors give you mechanisms, not policies. Find two *policies* in `stash` that another
   Lua program could reasonably choose differently, and name the mechanism each one is built on.

<details><summary>Solution</summary>

Many answers work. For example:

- **Classes.** A `stash` class is a table that is its own metatable, with `__index` pointing to
  itself and a `new` function. Other programs use a class library with inheritance and mixins,
  or closures instead of metatables. Mechanism: metatables and `__index`.
- **Error handling.** `stash` raises tables with a `kind` and maps kinds to exit codes. Other
  programs raise plain strings, or never raise and always return `nil, message`. Mechanism:
  `error` accepts any value, and `pcall` returns it unchanged.
- **Plugin isolation.** `stash` gives each plugin an allowlist environment and wraps each call
  in `pcall`. Another program could share one environment among all plugins, or run each in its
  own `lua_State`. Mechanism: environments (`setfenv`) and `pcall`.
- **Globals.** `stash.strict` makes reading or assigning an undeclared global an error. Many
  programs allow globals freely. Mechanism: a metatable on `_G`.

</details>

4. List the LuaJIT-only features `stash` uses. For each one, say what you'd use instead on PUC
   Lua 5.4.

<details><summary>Solution</summary>

`grep` finds them: `require("ffi")`, `bit.`, `jit.`, `setfenv` and `string.buffer`.

| LuaJIT feature | Used in | On Lua 5.4 |
|----------------|---------|------------|
| `ffi` | the bindings in `src/stash/ffi/`, `db`, `fetch`, `compress`, `fs`, `term`, `clock`, `buffer` | C modules written with the C API, or existing bindings from LuaRocks such as `lsqlite3`, `lua-zlib` and `luaposix` |
| `bit` | `compress` (CRC bytes), `fetch` (curl flags) | the operators `&`, `\|`, `~`, `<<`, `>>` |
| `jit` | `version -v`, `jit.off` in `db` and `fetch` | nothing needed: guard with `if jit then` |
| `setfenv` | `config`, `plugins` | `load(code, name, "t", env)` |
| `string.buffer` | `json` | collect pieces in a table and `table.concat` them |

The pure-Lua modules (`util`, `cli`, `entry`, `iter`, `html`, `errors`, `config` once ported)
need little or no change. The FFI is the big one: it is most of what makes `stash` a LuaJIT
program.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-21--design-and-next-steps)
