# Chapter 8 — Modules

`stash.lua` is over 400 lines. This chapter splits it into **modules**, one job per file, loaded
with `require`. It also covers loading code at run time (`loadstring`, `loadfile`, `dofile`) and
**environments**, which give code its own globals, so `stash` can read a Lua config file safely.
[Chapter 7](07-metatables-and-objects.md) made the classes; [Chapter 9](09-errors.md) cleans up
error handling.

## A module is a file that returns a table

There is no `module` or `export` keyword. A module is a file that returns a table.
`require("name")` finds the file, runs it, and returns its result.

`examples/ch08/greet.lua`

```lua
-- A module is a file that returns a table.
print("loading greet, module name: " .. ...)   -- require passes the name as `...`

local M = {}

local count = 0                    -- private: a local, not exported

function M.hello(name)
  count = count + 1
  return "hello, " .. name
end

function M.count()
  return count
end

return M
```

`examples/ch08/use_greet.lua`

```lua
-- Where require looks: ? is replaced by the module name.
package.path = "examples/ch08/?.lua;examples/ch08/?/init.lua"

local greet = require("greet")       -- runs greet.lua once...
print(greet.hello("Ada"))

local again = require("greet")       -- ...and returns the cached table after that
print(again == greet, again.count())
print(package.loaded.greet == greet)

print(count)                         -- nil: greet's local `count` is private
```

```console
$ luajit examples/ch08/use_greet.lua
loading greet, module name: greet
hello, Ada
true	1
true
nil
```

- **`require` runs a file once** and caches the result in `package.loaded[name]`. Every caller
  shares that table and its state: `count` is `1` through either variable.
- **Locals are private.** Other files can't see `count`. Only the returned table is public.
- **`...` is the module name**, passed to the file (a file is a function,
  [Chapter 4](04-functions.md)).
- Convention: `local M = {}` ... `return M`, loaded into a local of the same name:
  `local greet = require("greet")`.

A module may return any value (`stash`'s `sample.lua` returns a list). If it returns nothing,
like `strict.lua` below, `package.loaded` stores `true`.

## How `require` finds files

`package.path` is a `;`-separated list of **templates**. `require` replaces each `?` with the
module name and tries them in order. Dots become directory separators: `require("shapes.circle")`
looks for `shapes/circle.lua`. The template `?/init.lua` makes a directory a module.

`examples/ch08/shapes/init.lua`

```lua
-- shapes/init.lua: the module "shapes". It loads its submodules.
return {
  circle = require("shapes.circle"),     -- the dot becomes a directory separator
}
```

`examples/ch08/shapes/circle.lua`

```lua
-- shapes/circle.lua: the module "shapes.circle".
local M = {}

function M.area(r)
  return math.pi * r * r
end

return M
```

`examples/ch08/use_shapes.lua`

```lua
package.path = "examples/ch08/?.lua;examples/ch08/?/init.lua"

local shapes = require("shapes")          -- found as examples/ch08/shapes/init.lua
print(("%.2f"):format(shapes.circle.area(2)))
print(shapes.circle == require("shapes.circle"))

print(package.searchpath("shapes.circle", package.path))
print(package.searchpath("nosuch", package.path))
```

```console
$ luajit examples/ch08/use_shapes.lua
12.57
true
examples/ch08/shapes/circle.lua
nil	
	no file 'examples/ch08/nosuch.lua'
	no file 'examples/ch08/nosuch/init.lua'
```

`package.searchpath(name, path)` (LuaJIT, from Lua 5.2) returns the file `require` would load, or
`nil` plus the places it tried.

When nothing matches, `require` raises an error listing everything it tried:

`examples/ch08/missing.lua`

```lua
package.path = "examples/ch08/?.lua;examples/ch08/?/init.lua"
package.cpath = "examples/ch08/?.so"

local ok, err = pcall(require, "nosuch")
print(ok)
print(err)
```

```console
$ luajit examples/ch08/missing.lua
false
module 'nosuch' not found:
	no field package.preload['nosuch']
	no file 'examples/ch08/nosuch.lua'
	no file 'examples/ch08/nosuch/init.lua'
	no file 'examples/ch08/nosuch.so'
```

- `package.preload` comes first: loader functions for modules built in rather than stored in files.
- `package.cpath` does the same for **C modules** (`.so`, `.dll` libraries written for the Lua C
  API). `stash` uses the FFI instead ([Chapter 13](13-ffi-basics.md)) and never needs it.

The **default** `package.path` depends on the install. It starts with `./?.lua` (relative to the
current directory), then system directories such as `/usr/local/share/lua/5.1/?.lua`. The
`LUA_PATH` environment variable overrides it; `;;` in it stands for the default:

```console
$ LUA_PATH='examples/ch08/?.lua;;' luajit -e 'print(require("greet").hello("Bob"))'
loading greet, module name: greet
hello, Bob
```

`./?.lua` depends on where you **run** the program, not where it **is**: it only works from the
program's own directory. The `stash` launcher below fixes that.

## Circular requires

If `a` requires `b` and `b` requires `a`, the second `require("a")` runs while `a` is still
loading. LuaJIT detects it:

`examples/ch08/loop/a.lua` and `examples/ch08/loop/b.lua`

```lua
local b = require("b")      -- a needs b...
return { name = "a" }
```

```lua
local a = require("a")      -- ...and b needs a: a is still loading
return { name = "b" }
```

`examples/ch08/circular.lua`

```lua
package.path = "examples/ch08/loop/?.lua"
print(pcall(require, "a"))
```

```console
$ luajit examples/ch08/circular.lua
false	examples/ch08/loop/b.lua:1: loop or previous error loading module 'a'
```

Fix the design: move the shared part into a third module both require. In `stash`, dependencies
go one way: `main` → `commands` → `entry` → `util`.

## Writing good modules

- **Keep everything local.** Create no globals; the returned table is the interface. `stash`
  loads `strict.lua` first, so an accidental global is an error.
- **Localize imports** at the top (`local util = require("stash.util")`); they document the
  dependencies. Some code also localizes library functions (`local insert = table.insert`):
  shorter, and slightly faster in the plain interpreter. (The JIT makes it rarely matter; see
  [Chapter 18](18-performance-and-the-jit.md).)
- **Avoid `module()`.** Lua 5.1's `module("name", package.seeall)` makes the rest of the file a
  module by changing its environment and creating a global table. That pollutes the globals and
  hides where names come from. Lua 5.2 deprecated it and later versions dropped it; new code
  returns a table.

## Loading code at run time

`require` is built on functions you can use directly. They **compile** code into a function;
nothing runs until you call it.

| Function | Does | On a syntax error |
|----------|------|-------------------|
| `loadstring(s [, name])` | compiles a string | returns `nil, message` |
| `loadfile(path)` | compiles a file | returns `nil, message` |
| `dofile(path)` | compiles **and runs** a file | raises an error |

`examples/ch08/load.lua`

```lua
-- loadstring compiles a string into a function. Nothing runs yet.
local f = assert(loadstring("return 6 * 7"))
print(type(f), f())

-- A syntax error is not thrown: you get nil plus a message.
print(loadstring("return 6 *"))
print(loadstring("return 6 *", "=calc"))     -- the second argument names the chunk

-- A chunk is a function, so it takes arguments as `...`.
local add = loadstring("local a, b = ... return a + b")
print(add(2, 3))

-- loadfile does the same for a file. dofile loads AND runs it (and throws on errors).
print(loadfile("examples/ch08/nosuch.lua"))
print(dofile("examples/ch08/shapes/circle.lua").area(1))
```

```console
$ luajit examples/ch08/load.lua
function	42
nil	[string "return 6 *"]:1: unexpected symbol near '<eof>'
nil	calc:1: unexpected symbol near '<eof>'
5
nil	cannot open examples/ch08/nosuch.lua: No such file or directory
3.1415926535898
```

- A chunk is a function taking `...`, like a file.
- The chunk name shows in messages. The default is the code itself, `[string "..."]`. A name
  starting with `=` is used as is; `@` marks a file name. `loadfile` uses the file name.
- `load(fn [, name])` takes a reader function returning pieces of code. LuaJIT's `load` (as in
  Lua 5.2) also takes a string and a mode: `"t"` text only, `"b"` bytecode only. Use `"t"` for
  untrusted code: bytecode isn't checked, and a crafted chunk can crash the VM.

## Environments: `setfenv` and `getfenv`

In Lua 5.1, every function has an **environment**: the table its globals live in, normally `_G`.
`setfenv(f, t)` changes it; `getfenv(f)` reads it (`f` may be a level: `1` is the current
function).

`examples/ch08/env.lua`

```lua
-- Every function has an environment: the table its globals live in.
print(getfenv(1) == _G)                     -- level 1 = this chunk: the normal _G

local chunk = loadstring("x = 10; y = x * 2; print = nil")
local env = {}
setfenv(chunk, env)                         -- the chunk's globals now live in env
chunk()

print(env.x, env.y, rawget(_G, "x"))        -- 10 20 nil: _G was not touched
print(print ~= nil)                         -- our print still works

-- With an empty env, code can't reach anything you don't give it.
local evil = loadstring("os.exit(1)")
setfenv(evil, {})
print(pcall(evil))

-- Give it exactly what it may use.
local calc = loadstring("return math.max(a, b)")
setfenv(calc, { math = math, a = 3, b = 7 })
print(calc())
```

```console
$ luajit examples/ch08/env.lua
true
10	20	nil
true
false	[string "os.exit(1)"]:1: attempt to index global 'os' (a nil value)
7
```

- `x = 10` went into `env`, not `_G`; `print = nil` only hid `print` in `env`.
- In an empty environment there is no `os`, so no `os.exit`.
- To allow functions, put them in the environment table.

This is a partial **sandbox**: code can still loop forever, eat all memory, or reach string
methods through the shared string metatable. It stops honest config files from breaking things by
accident; it can't contain code from strangers.

Lua 5.2 replaced `setfenv` with `_ENV` and an `env` parameter, `load(s, name, mode, env)`. LuaJIT
has both: `load(code, "=config", "t", env)` compiles and sets the environment in one step. `stash`
uses `setfenv`, which every Lua 5.1-compatible version has.

## Config files as code

A config file can be plain Lua. Run it in an empty environment; the variables it sets are the
settings:

`examples/ch08/settings.lua`

```lua
-- A config file: plain Lua that assigns variables.
name = "demo"
width = 40 * 2
tags = { "lua", "jit" }
```

`examples/ch08/config.lua`

```lua
-- Load a config file as data: run it in an empty environment, then read
-- the variables it set.
local function load_config(path)
  local chunk, err = loadfile(path)
  if chunk == nil then
    return nil, err
  end
  local env = {}
  setfenv(chunk, env)
  chunk()
  return env
end

local cfg = assert(load_config("examples/ch08/settings.lua"))
print(cfg.name, cfg.width, table.concat(cfg.tags, ","))
print(load_config("examples/ch08/nosuch.lua"))
```

```console
$ luajit examples/ch08/config.lua
demo	80	lua,jit
nil	cannot open examples/ch08/nosuch.lua: No such file or directory
```

Config as code gives comments, tables, arithmetic and escapes with no parser to write. The cost:
runtime errors as well as syntax errors. `list_limit = 2 + nil` raises an error inside `chunk()`;
the checkpoint shows the result, and Chapter 9 handles it.

## Building stash: modules and a config file

`stash.lua` becomes a launcher, `stash`, plus nine modules in `src/stash/`:

```text
project/ch08/
├── stash                  launcher: sets package.path, runs stash.main
└── src/stash/
    ├── strict.lua         strict mode (from the top of stash.lua)
    ├── util.lua           split, truncate, title_from_url
    ├── entry.lua          the Entry class
    ├── memstore.lua       the MemoryStore class
    ├── sample.lua         the three sample entries (data only)
    ├── cli.lua            parse(): the old parse_args
    ├── config.lua         loads $STASH_HOME/config.lua
    ├── commands.lua       the commands
    └── main.lua           run(): config, aliases, dispatch
```

Module names follow directories: `src/stash/util.lua` is `require("stash.util")`. The `stash.`
prefix avoids clashes with other libraries' modules, such as another `util`. Two new features:

- **`$STASH_HOME/config.lua`** (default `~/.local/share/stash/config.lua`) sets `list_limit` (rows
  `list` shows by default, 20) and `aliases` (short names for longer commands).
- **Commands get a context** `ctx` instead of globals: `ctx.store`, `ctx.config`, and `ctx.out` (the
  print function). Tests in [Chapter 10](10-testing.md) pass their own `ctx` to capture output.

Delete `stash.lua` and create the files below.

### The launcher

`stash`

```lua
#!/usr/bin/env luajit
-- The stash launcher: makes src/ importable, then hands over to stash.main.

-- arg[0] is this script's path; its directory holds src/. This way stash
-- works from any current directory.
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = dir .. "/src/?.lua;" .. package.path

require("stash.strict")
require("stash.main").run(arg)
```

`arg[0]` is the path that started the script, such as `../stash`. `^(.*)/[^/]*$` keeps everything
before the last `/`; with no `/` (`luajit stash`), the directory is `.`. Prepending
`dir .. "/src/?.lua"` lets `require("stash.main")` find `src/stash/main.lua` from any directory.

The launcher has no `.lua` extension: it's the command people type. Make it executable:

```console
$ chmod +x stash
```

### Strict mode and the helpers

Strict mode moves to its own module. It returns nothing; requiring it is the point.

`src/stash/strict.lua`

```lua
-- Strict mode: reading or assigning an undeclared global is an error.
-- Requiring this module once switches it on for the whole program.

setmetatable(_G, {
  __newindex = function(_, name)
    error("assignment to undeclared global '" .. tostring(name) .. "'", 2)
  end,
  __index = function(_, name)
    error("undeclared global '" .. tostring(name) .. "'", 2)
  end,
})

-- Nothing to return: require() stores `true` in package.loaded instead.
```

The string helpers become functions in a table:

`src/stash/util.lua`

```lua
-- Small string helpers shared by several modules.

local M = {}

-- Splits "a, b,,c" into { "a", "b", "c" }: pieces are trimmed, empty ones dropped.
function M.split(s, sep)
  local parts = {}
  for piece in s:gmatch("[^" .. sep .. "]+") do
    piece = piece:match("^%s*(.-)%s*$")
    if piece ~= "" then
      parts[#parts + 1] = piece
    end
  end
  return parts
end

-- Shortens s to at most `width` characters, marking the cut with "...".
function M.truncate(s, width)
  if #s <= width then
    return s
  end
  return s:sub(1, width - 3) .. "..."
end

-- "https://www.lua.org/pil/?x=1" -> "www.lua.org/pil"
function M.title_from_url(url)
  local rest = url:match("^%a[%w+.-]*://([^?#]*)") or url
  return (rest:gsub("/+$", ""))
end

return M
```

### Entry and MemoryStore

`entry.lua` is Chapter 7's `Entry` class, using `util.title_from_url`, with `return Entry` at the
end:

`src/stash/entry.lua`

```lua
-- Entry: one bookmark.

local util = require("stash.util")

local Entry = {}
Entry.__index = Entry

function Entry.new(fields)
  local self = setmetatable({}, Entry)
  self.id = fields.id                        -- nil until a store assigns one
  self.url = fields.url
  self.title = fields.title or util.title_from_url(fields.url)
  self.note = fields.note or ""
  self.tags = {}
  for i, tag in ipairs(fields.tags or {}) do
    self.tags[i] = tag
  end
  table.sort(self.tags)
  return self
end

function Entry:has_tag(tag)
  for _, t in ipairs(self.tags) do
    if t == tag then
      return true
    end
  end
  return false
end

-- Case-insensitive substring search over the text fields.
function Entry:matches(term)
  term = term:lower()
  for _, field in ipairs({ self.title, self.url, self.note, self:tag_string(" ") }) do
    if field:lower():find(term, 1, true) then
      return true
    end
  end
  return false
end

function Entry:tag_string(sep)
  return table.concat(self.tags, sep or ",")
end

function Entry.__tostring(self)
  return ("#%d %s"):format(self.id or 0, self.title)
end

function Entry.__lt(a, b)
  return a.id < b.id
end

return Entry
```

`memstore.lua` is the `MemoryStore` class. The sample data is no longer built in; the caller
passes it:

`src/stash/memstore.lua`

```lua
-- MemoryStore: keeps entries in a table. Every store implements the same
-- methods, so the commands do not care where entries live:
--   add(entry) -> entry      get(id) -> entry|nil     remove(id) -> entry|nil
--   list{tag=, limit=} -> array     search(term) -> array     tags() -> array

local Entry = require("stash.entry")

local MemoryStore = {}
MemoryStore.__index = MemoryStore

function MemoryStore.new(initial)
  local self = setmetatable({ by_id = {}, next_id = 1 }, MemoryStore)
  for _, fields in ipairs(initial or {}) do
    self:add(Entry.new(fields))
  end
  return self
end

function MemoryStore:add(entry)
  entry.id = self.next_id
  self.next_id = self.next_id + 1
  self.by_id[entry.id] = entry             -- keyed by id: get() is one lookup
  return entry
end

function MemoryStore:get(id)
  return self.by_id[id]
end

function MemoryStore:remove(id)
  local entry = self.by_id[id]
  self.by_id[id] = nil
  return entry
end

-- All entries sorted by id. (pairs() visits keys in no particular order.)
function MemoryStore:sorted()
  local list = {}
  for _, entry in pairs(self.by_id) do
    list[#list + 1] = entry
  end
  table.sort(list)                           -- uses Entry.__lt
  return list
end

function MemoryStore:list(filter)
  local result = {}
  for _, entry in ipairs(self:sorted()) do
    if filter.limit and #result >= filter.limit then
      break
    end
    if filter.tag == nil or entry:has_tag(filter.tag) then
      result[#result + 1] = entry
    end
  end
  return result
end

function MemoryStore:search(term)
  local result = {}
  for _, entry in ipairs(self:sorted()) do
    if entry:matches(term) then
      result[#result + 1] = entry
    end
  end
  return result
end

-- Returns { {tag=, count=}, ... }: most used first, then by name.
function MemoryStore:tags()
  local counts = {}
  for _, entry in pairs(self.by_id) do
    for _, tag in ipairs(entry.tags) do
      counts[tag] = (counts[tag] or 0) + 1
    end
  end
  local rows = {}
  for tag, count in pairs(counts) do
    rows[#rows + 1] = { tag = tag, count = count }
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.tag < b.tag
  end)
  return rows
end

return MemoryStore
```

The sample data is its own module (a module can be pure data):

`src/stash/sample.lua`

```lua
-- Sample bookmarks. A module can be plain data: this file just returns a
-- table. (Nothing is saved yet; files arrive in Chapter 12.)

return {
  { url = "https://www.lua.org/", title = "The Programming Language Lua",
    tags = { "lua", "lang" }, note = "official site" },
  { url = "https://luajit.org/", title = "LuaJIT", tags = { "lua", "jit" } },
  { url = "https://sqlite.org/fts5.html", title = "SQLite FTS5 Extension",
    tags = { "db", "search" }, note = "full-text search" },
}
```

### Argument parsing

`cli.lua` holds the old `parse_args`, renamed `parse` (the module name already says "cli"). It
returns `nil` plus a message and lets the caller decide (the `nil, message` convention; see
Chapter 9).

`src/stash/cli.lua`

```lua
-- Command-line parsing.

local util = require("stash.util")

local M = {}

-- Parses args[first], args[first+1], ... using a spec that maps each flag
-- to { field, kind }. Kinds: "flag" (no value), "value", "number", "list"
-- (may repeat, values may be comma-separated). Returns an options table:
-- named fields for flags, and the remaining (positional) arguments at 1, 2, 3...
-- On a bad argument it returns nil plus a message.
function M.parse(args, first, spec)
  local opts = {}
  local i = first
  while i <= #args do
    local a = args[i]
    local option = spec[a]
    if option == nil then
      if a:sub(1, 1) == "-" and a ~= "-" then
        return nil, "unknown option " .. a
      end
      opts[#opts + 1] = a
    else
      local field, kind = option[1], option[2]
      if kind == "flag" then
        opts[field] = true
      else
        i = i + 1
        local value = args[i]
        if value == nil then
          return nil, a .. " needs a value"
        end
        if kind == "number" then
          value = tonumber(value)
          if value == nil then
            return nil, a .. " needs a number"
          end
        end
        if kind == "list" then
          opts[field] = opts[field] or {}
          for _, item in ipairs(util.split(value, ",")) do
            table.insert(opts[field], item)
          end
        else
          opts[field] = value
        end
      end
    end
    i = i + 1
  end
  return opts
end

return M
```

### Configuration

`src/stash/config.lua`

```lua
-- Configuration: $STASH_HOME/config.lua is a Lua file that sets variables.
--
--   list_limit = 10
--   aliases = { ls = "list", lua = "list -t lua" }
--
-- Config is code, so we run it, but in an empty environment: it cannot
-- see our globals, and its assignments land in a table we inspect.

local M = {}

-- Every known setting with its default. The type of the default is the
-- type the setting must have.
M.defaults = {
  list_limit = 20,
  aliases = {},
}

-- Returns the settings table, or nil and an error message.
function M.load(path)
  local settings = {}
  for key, value in pairs(M.defaults) do
    settings[key] = value
  end

  -- A missing config file is fine: use the defaults. (io.open is covered
  -- in Chapter 12; here it only checks that the file exists.)
  local file = io.open(path)
  if file == nil then
    return settings
  end
  file:close()

  local chunk, err = loadfile(path)
  if chunk == nil then
    return nil, err                          -- syntax error, with file:line
  end
  local env = {}
  setfenv(chunk, env)                        -- globals of the chunk now live in env
  chunk()

  for key, value in pairs(env) do
    local default = M.defaults[key]
    if default == nil then
      return nil, path .. ": unknown setting '" .. key .. "'"
    end
    if type(value) ~= type(default) then
      return nil, ("%s: '%s' must be a %s"):format(path, key, type(default))
    end
    settings[key] = value
  end
  return settings
end

return M
```

- `M.defaults` lists every setting; each default's **type** is the required type.
- `settings` starts as a copy of the defaults, so a config file sets only what it changes.
- `loadfile` reports a syntax error as `nil, message`; `M.load` passes it on.
- Afterwards `env` holds everything the chunk set. Unknown names (typos like `colour`) and wrong
  types are reported, not ignored.
- `chunk()` is unprotected: a **runtime** error in the config stops the program with a traceback.
  Chapter 9 fixes that.

### The commands

`src/stash/commands.lua`

```lua
-- The commands. Each one gets a context table `ctx` (the store, the
-- settings, and an `out` function for output) plus the parsed options.

local Entry = require("stash.entry")
local util = require("stash.util")

local VERSION = "0.1.0"

local commands = {}                          -- name -> command record
local order = {}                             -- names in the order help shows them

-- A tiny DSL: `command "add" { ... }` calls command("add"), which returns
-- a function that receives the table. Both calls need no parentheses.
local function command(name)
  return function(def)
    def.name = name
    def.options = def.options or {}
    commands[name] = def
    order[#order + 1] = name
  end
end

local function fail(fmt, ...)
  print("stash: " .. fmt:format(...))
end

local function format_row(entry)
  return ("%3d  %-36s  %s"):format(entry.id, util.truncate(entry.title, 36), entry:tag_string())
end

command "add" {
  usage = "add URL [-t TAGS] [-n NOTE]",
  help = "save a bookmark",
  options = { ["-t"] = { "tags", "list" }, ["-n"] = { "note", "value" } },
  run = function(ctx, opts)
    local url = opts[1]
    if url == nil then
      return fail("add: missing URL")
    end
    if not url:find("^%a[%w+.-]*://") then
      return fail("add: '%s' does not look like a URL", url)
    end
    local tags = {}
    for i, tag in ipairs(opts.tags or {}) do
      tag = tag:lower()
      if not tag:find("^[%w_-]+$") then
        return fail("add: bad tag '%s' (use letters, digits, - and _)", tag)
      end
      tags[i] = tag
    end
    local entry = ctx.store:add(Entry.new({ url = url, tags = tags, note = opts.note }))
    ctx.out("added " .. tostring(entry))
  end,
}

command "list" {
  usage = "list [-t TAG] [--limit N]",
  help = "list bookmarks",
  options = { ["-t"] = { "tag", "value" }, ["--limit"] = { "limit", "number" } },
  run = function(ctx, opts)
    local limit = opts.limit or ctx.config.list_limit
    for _, entry in ipairs(ctx.store:list({ tag = opts.tag, limit = limit })) do
      ctx.out(format_row(entry))
    end
  end,
}

command "search" {
  usage = "search TERM",
  help = "find bookmarks containing TERM",
  run = function(ctx, opts)
    local term = opts[1]
    if term == nil then
      return fail("search: missing TERM")
    end
    local found = ctx.store:search(term)
    for _, entry in ipairs(found) do
      ctx.out(format_row(entry))
    end
    if #found == 0 then
      fail("nothing matches '%s'", term)
    end
  end,
}

command "show" {
  usage = "show ID",
  help = "show one bookmark",
  run = function(ctx, opts)
    local id = tonumber(opts[1])
    if id == nil then
      return fail("show: missing or bad ID")
    end
    local entry = ctx.store:get(id)
    if entry == nil then
      return fail("no entry with id %d", id)
    end
    ctx.out(("%-6s %d"):format("id:", entry.id))
    ctx.out(("%-6s %s"):format("title:", entry.title))
    ctx.out(("%-6s %s"):format("url:", entry.url))
    ctx.out(("%-6s %s"):format("tags:", entry:tag_string(", ")))
    if entry.note ~= "" then
      ctx.out(("%-6s %s"):format("note:", entry.note))
    end
  end,
}

command "rm" {
  usage = "rm ID",
  help = "delete a bookmark",
  run = function(ctx, opts)
    local id = tonumber(opts[1])
    if id == nil then
      return fail("rm: missing or bad ID")
    end
    local entry = ctx.store:remove(id)
    if entry == nil then
      return fail("no entry with id %d", id)
    end
    ctx.out("removed " .. tostring(entry))
  end,
}

command "tags" {
  usage = "tags",
  help = "count bookmarks per tag",
  run = function(ctx)
    for _, row in ipairs(ctx.store:tags()) do
      ctx.out(("%4d  %s"):format(row.count, row.tag))
    end
  end,
}

command "help" {
  usage = "help",
  help = "show this help",
  run = function(ctx)
    ctx.out("usage: stash <command> [arguments]")
    ctx.out("")
    ctx.out("commands:")
    for _, name in ipairs(order) do
      local c = commands[name]
      ctx.out(("  %-28s  %s"):format(c.usage, c.help))
    end
  end,
}

command "version" {
  usage = "version",
  help = "print the version",
  run = function(ctx)
    ctx.out("stash " .. VERSION)
  end,
}

return commands
```

`command "add" { ... }` is a small **DSL** (domain-specific language) built on two rules from
[Chapter 4](04-functions.md): a call with one string or table argument needs no parentheses, and
functions can return functions. So it means `command("add")({ ... })`. `command` records the name,
defaults `options` to `{}`, and appends to `order`, so `help` lists commands in definition order.

Each `run` now takes `(ctx, opts)` and prints normal output with `ctx.out`. `list` falls back to
`ctx.config.list_limit` without `--limit`. Errors still go through `fail` and `print`; Chapter 9
replaces that.

### The entry point

`src/stash/main.lua`

```lua
-- Entry point: load the settings, pick the command, run it.

local cli = require("stash.cli")
local commands = require("stash.commands")
local config = require("stash.config")
local util = require("stash.util")
local MemoryStore = require("stash.memstore")
local sample = require("stash.sample")

local M = {}

local function fail(fmt, ...)
  print("stash: " .. fmt:format(...))
end

-- The data directory: $STASH_HOME, or ~/.local/share/stash.
-- (os.getenv reads an environment variable; more in Chapter 12.)
function M.home()
  return os.getenv("STASH_HOME") or (os.getenv("HOME") .. "/.local/share/stash")
end

-- Replaces an alias in args[1] by its words: with aliases = { ll = "list
-- --limit 5" }, `stash ll -t lua` becomes `stash list --limit 5 -t lua`.
local function expand_alias(args, aliases)
  local alias = args[1] and aliases[args[1]]
  if alias == nil then
    return args
  end
  local expanded = util.split(alias, " ")
  for i = 2, #args do
    expanded[#expanded + 1] = args[i]
  end
  return expanded
end

function M.run(args)
  local settings, err = config.load(M.home() .. "/config.lua")
  if settings == nil then
    return fail("%s", err)
  end

  args = expand_alias(args, settings.aliases)
  local name = args[1]
  if name == nil or name == "-h" or name == "--help" then
    name = "help"
  elseif name == "--version" then
    name = "version"
  end

  local command = commands[name]
  if command == nil then
    return fail("unknown command '%s' (try 'stash help')", name)
  end
  local opts, perr = cli.parse(args, 2, command.options)
  if opts == nil then
    return fail("%s: %s", name, perr)
  end

  local ctx = {
    store = MemoryStore.new(sample),
    config = settings,
    out = print,
  }
  command.run(ctx, opts)
end

return M
```

`M.run` does what `main` did, plus:

1. Load the settings. A broken config stops the run with a message.
2. Expand aliases: with `aliases = { ll = "list --limit 9" }`, `stash ll -t lua` becomes
   `stash list --limit 9 -t lua`. `expand_alias` builds a new array; the caller's `args` stays
   unchanged.

`M.home` is public so later chapters (and tests) can use it.

### Checkpoint

The first commands run without a config file; then `STASH_HOME=demo` points `stash` at one:

```console
$ ./stash list
  1  The Programming Language Lua          lang,lua
  2  LuaJIT                                jit,lua
  3  SQLite FTS5 Extension                 db,search
$ mkdir -p demo
$ (cd demo && ../stash version)
stash 0.1.0
$ export STASH_HOME=demo
$ printf 'list_limit = 2\naliases = { lua = "list -t lua", ll = "list --limit 9" }\n' > demo/config.lua
$ ./stash list
  1  The Programming Language Lua          lang,lua
  2  LuaJIT                                jit,lua
$ ./stash ll
  1  The Programming Language Lua          lang,lua
  2  LuaJIT                                jit,lua
  3  SQLite FTS5 Extension                 db,search
$ ./stash lua
  1  The Programming Language Lua          lang,lua
  2  LuaJIT                                jit,lua
$ echo 'colour = "never"' >> demo/config.lua
$ ./stash list
stash: demo/config.lua: unknown setting 'colour'
$ echo 'list_limit = ' > demo/config.lua
$ ./stash list
stash: demo/config.lua:2: unexpected symbol near '<eof>'
$ echo "list_limit = 2 + nil" > demo/config.lua
$ ./stash list
luajit: demo/config.lua:1: attempt to perform arithmetic on a nil value
stack traceback:
	demo/config.lua:1: in function 'chunk'
	./src/stash/config.lua:39: in function 'load'
	./src/stash/main.lua:37: in function 'run'
	./stash:10: in main chunk
	[C]: at 0x5ba2971833a0
[exit 1]
```

- `(cd demo && ../stash version)` works from another directory: the launcher finds `src/` through
  `arg[0]`.
- `list_limit = 2` shortens `list`; the `ll` alias's `--limit 9` overrides it.
- The typo `colour` and the syntax error become messages.
- The last command is a **runtime** error in the config. Nothing catches it, so `luajit` prints a
  stack traceback and exits with status 1 (the `[C]: at 0x...` address varies).
  [Chapter 9](09-errors.md) turns this into a clean message.

The complete project at this point is in `project/ch08/`.

## Summary

- A module is a file that returns a table (or any value). Its locals are private.
- `require(name)` searches `package.path`, runs the file once, caches it in `package.loaded`.
  Dots are directories; `?/init.lua` makes a directory a module.
- The default path is relative to the current directory; building it from `arg[0]` works from
  anywhere. `LUA_PATH` overrides it (`;;` = default).
- Circular requires fail with "loop or previous error loading module". Design them away.
- Modules create no globals, localize imports, and skip the old `module()`.
- `loadstring`/`loadfile` compile and return `nil, message` on syntax errors; `dofile` compiles,
  runs, and raises errors.
- `setfenv(f, env)` gives a function its own globals: a simple sandbox, and Lua config files read
  as data.

## Exercises

1. Write `reload(name)` so `require` loads a module again. Test with `greet`: is the reloaded
   module the same table? Does it keep the old `count`?

<details><summary>Solution</summary>

```lua
package.path = "examples/ch08/?.lua"

local function reload(name)
  package.loaded[name] = nil         -- forget the cached module...
  return require(name)               -- ...so require runs the file again
end

local a = require("greet")
local b = reload("greet")
print(a == b, a.count(), b.count())
```

```console
loading greet, module name: greet
loading greet, module name: greet
false	0	0
```

The file ran twice: `b` is a new table with a fresh `count`, while code holding `a` keeps the old
one. Reloading is a debugging aid, not something to build on.

</details>

2. Change the launcher's line to `package.path = "./src/?.lua;" .. package.path` and run `stash`
   from another directory. What happens? Why does the original work?

<details><summary>Solution</summary>

```console
$ mkdir -p demo && cd demo && ../stash version
luajit: ../stash:9: module 'stash.strict' not found:
	no field package.preload['stash.strict']
	no file './src/stash/strict.lua'
...
```

`./` is the current directory, `demo/`, which has no `src/`. The original uses `arg[0]`'s
directory, `..`, where the launcher and `src/` live.

</details>

3. With `aliases = { ll = 5 }`, `stash ll` crashes inside `util.split`. Make `config.load` reject
   non-string alias values.

<details><summary>Solution</summary>

In `src/stash/config.lua`, check aliases after the settings loop:

```lua
    settings[key] = value
  end
  for name, words in pairs(settings.aliases) do
    if type(words) ~= "string" then
      return nil, ("%s: alias '%s' must be a string"):format(path, tostring(name))
    end
  end
  return settings
```

```console
$ echo 'aliases = { ll = 5 }' > demo/config.lua
$ ./stash ll
stash: demo/config.lua: alias 'll' must be a string
```

The check against the defaults is one level deep: `aliases` is a table, as required. Its contents
need their own check.

</details>

4. Let config files read environment variables:
   `list_limit = tonumber(os.getenv("STASH_LIMIT") or "20")`. `os` and `tonumber` must not count as
   unknown settings. Hint: [Chapter 7](07-metatables-and-objects.md).

<details><summary>Solution</summary>

Give the environment an `__index` table with the allowed functions:

```lua
  -- Config code can read these names, but they are not settings: they live
  -- in the __index table, so pairs(env) below never sees them.
  local env = setmetatable({}, {
    __index = { os = { getenv = os.getenv }, tonumber = tonumber },
  })
  setfenv(chunk, env)
```

```console
$ echo 'list_limit = tonumber(os.getenv("STASH_LIMIT") or "20")' > demo/config.lua
$ STASH_LIMIT=1 ./stash list
  1  The Programming Language Lua          lang,lua
$ echo 'os = 1' > demo/config.lua
$ ./stash list
stash: demo/config.lua: unknown setting 'os'
```

Reads of `os` miss in `env` and reach `__index`. Assignments still land in `env`, so `pairs(env)`
sees exactly the file's settings. The config gets an `os` with only `getenv`, not the real one with
`exit` and `remove`.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-8--modules)
