# Chapter 9 — Errors

In [Chapter 8](08-modules.md), a config mistake crashed `stash` with a traceback; other problems
printed a message but exited with status 0, so scripts can't tell success from failure. This chapter covers raising and catching errors, when to return
`nil, message` instead, and cleaning up without `finally`. Then `stash` gets one scheme: clear
messages on stderr, proper exit codes, tracebacks only for real bugs.
[Chapter 10](10-testing.md) builds tests on it.

## Raising and catching

`error(message)` stops the current function and its callers until something **catches** the
error. `pcall(f, ...)` ("protected call") calls `f` with the arguments and returns `true` plus
`f`'s results, or `false` plus the error value. An uncaught error makes `luajit` print it and exit
with status 1.

`examples/ch09/raise.lua`

```lua
-- error() raises an error; pcall catches it and returns false plus the message.
local function check_age(age)
  if type(age) ~= "number" then
    error("age must be a number")         -- level 1 (default): blames this line
  end
  if age < 0 then
    error("age must not be negative", 2)  -- level 2: blames the caller
  end
  return age
end

print(pcall(check_age, 30))
print(pcall(check_age, "old"))
print(pcall(function()
  local age = check_age(-1)               -- line 15: level 2 points here
  return age
end))
print(pcall(error, "no position", 0))     -- level 0: the message as is
```

```console
$ luajit examples/ch09/raise.lua
true	30
false	examples/ch09/raise.lua:4: age must be a number
false	examples/ch09/raise.lua:15: age must not be negative
false	no position
```

The second argument of `error` is the **level**: whom the `file:line:` prefix blames.

| Level | Blames | Use it for |
|-------|--------|------------|
| `1` (default) | the line calling `error` | bugs in your own function |
| `2` | the line calling **your** function | bad arguments: the caller's mistake |
| `0` | nobody: no prefix | user messages, or re-raising an error that has a prefix |

Level 2 counts **stack frames**. In a tail call, `return check_age(-1)`, the caller's frame is gone
before `check_age` runs, leaving no line to blame. So the example stores the result in a local.

## Runtime errors

Lua itself raises errors for impossible operations. They're caught the same way:

`examples/ch09/runtime.lua`

```lua
-- Runtime errors are raised by Lua itself. pcall catches them the same way.
local t = nil
print(pcall(function() return t.name end))
print(pcall(function() return undefined_function() end))
print(pcall(function() return "abc" + 1 end))
print(pcall(function() return #42 end))

-- pcall passes extra arguments to the function, and returns all its results.
print(pcall(string.rep, "ab", 3))
print(pcall(string.rep))
```

```console
$ luajit examples/ch09/runtime.lua
false	examples/ch09/runtime.lua:3: attempt to index upvalue 't' (a nil value)
false	examples/ch09/runtime.lua:4: attempt to call global 'undefined_function' (a nil value)
false	examples/ch09/runtime.lua:5: attempt to perform arithmetic on a string value
false	examples/ch09/runtime.lua:6: attempt to get length of a number value
true	ababab
false	bad argument #1 to '?' (string expected, got no value)
```

Messages name the variable when known (`upvalue 't'`, `global 'undefined_function'`), often
enough to find the bug. Library errors name the bad argument. The last line has no
position and `'?'` as the name because `pcall` called `string.rep` directly. From a Lua line,
`local x = string.rep()`, the message is
`file:line: bad argument #1 to 'rep' (string expected, got no value)`.

## `assert`

`assert(v, message)` raises `message` if `v` is `false` or `nil`. Otherwise it returns **all** its
arguments, so it can wrap a call:

`examples/ch09/assert.lua`

```lua
-- assert(v, message) raises message if v is false or nil.
-- Otherwise it returns ALL its arguments.
print(assert(42, "unused"))
print(pcall(function() assert(1 > 2) end))
print(pcall(function() assert(nil, "port is required") end))

-- The idiom: wrap a function that returns nil plus a message.
local n = assert(tonumber("17"))
print(n)
print(pcall(function()
  local chunk = assert(loadstring("return 1 +"))
end))
```

```console
$ luajit examples/ch09/assert.lua
42	unused
false	examples/ch09/assert.lua:4: assertion failed!
false	examples/ch09/assert.lua:5: port is required
17
false	examples/ch09/assert.lua:11: [string "return 1 +"]:1: unexpected symbol near '<eof>'
```

- Without a message you get the unhelpful `assertion failed!`. Give one.
- `assert(f())` is the standard "this must not fail". If `f` returns `nil, message`, `assert`
  raises `message`.
- Like `error`, `assert` adds the calling line's position.

## `nil, message` or an error?

Lua has two conventions for failure:

- **Return `nil, message`** for **expected** failures: a missing file, bad input, a timeout. The
  caller handles it on the spot. `io.open`, `tonumber`, `loadstring` and `loadfile` do this.
- **Raise an error** for **bugs** and failures no nearby caller can fix. It travels up to code
  that knows what to do, often the top of the program.

`examples/ch09/nil_err.lua`

```lua
-- Expected failures: return nil plus a message, and let the caller decide.
local function parse_port(s)
  local n = tonumber(s)
  if n == nil or n % 1 ~= 0 then
    return nil, "not a whole number: " .. tostring(s)
  end
  if n < 1 or n > 65535 then
    return nil, "port out of range: " .. n
  end
  return n
end

for _, s in ipairs({ "8080", "http", "70000" }) do
  local port, err = parse_port(s)
  if port then
    print("port", port)
  else
    print("error", err)
  end
end

-- Converting between the two styles:
print(pcall(function() return assert(parse_port("x")) end))  -- nil, err -> error
local ok, err = pcall(error, "boom", 0)                       -- error -> false, err
print(ok, err)
```

```console
$ luajit examples/ch09/nil_err.lua
port	8080
error	not a whole number: http
error	port out of range: 70000
false	not a whole number: x
false	boom
```

Rule of thumb: libraries return `nil, message`; programs decide. `assert` turns `nil, message`
into an error and `pcall` turns an error into `false, message`, so each caller picks its style.

## Error objects

`error` accepts any value. A table can carry fields, such as a kind or exit code, so the catcher
can decide without parsing a message:

`examples/ch09/objects.lua`

```lua
-- Any value can be an error. A table can carry fields for the handler.
local AppError = {}
AppError.__index = AppError
AppError.__tostring = function(e) return e.kind .. ": " .. e.message end

local function fail(kind, message)
  error(setmetatable({ kind = kind, message = message }, AppError))
end

local ok, err = pcall(fail, "not_found", "no such entry")
print(ok, type(err), err.kind, err.message)
print(tostring(err))
print(getmetatable(err) == AppError)

-- A string error from Lua itself is not an AppError: that's a bug.
local _, bug = pcall(function() return nil .. "x" end)
print(type(bug), getmetatable(bug) == AppError)
```

```console
$ luajit examples/ch09/objects.lua
false	table	not_found	no such entry
not_found: no such entry
true
string	false
```

- Lua adds no position to table errors; the level does nothing.
- Give the table a metatable: `getmetatable(err) == AppError` separates your errors from Lua's
  string errors, and `__tostring` makes them printable.

An uncaught table error can only be printed if it has a `__tostring`:

```console
$ luajit -e 'error({ code = 2 })'
luajit: (error object is not a string)
[exit 1]
$ luajit -e 'error(setmetatable({}, { __tostring = function() return "custom message" end }))'
luajit: custom message
stack traceback:
	[C]: in function 'error'
	(command line):1: in main chunk
	[C]: at 0x57589ba303a0
[exit 1]
```

(The `[C]: at 0x...` address varies between runs.)

## `xpcall` and tracebacks

A **stack traceback** lists the calls that led to an error. By the time `pcall` returns, the
stack has unwound. `xpcall(f, handler)` calls `handler(err)` at the moment of
the error, **before** unwinding, and returns the handler's result.
`debug.traceback(message, level)` builds the traceback text.

`examples/ch09/traceback.lua`

```lua
-- xpcall(f, handler): the handler runs at the point of the error,
-- before the stack unwinds, so it can still see the stack.
local function inner()
  local t = nil
  return t.x
end
local function outer()
  inner()
  return "never"
end

local ok, tb = xpcall(outer, debug.traceback)
print(ok)
print(tb)
```

```console
$ luajit examples/ch09/traceback.lua
false
examples/ch09/traceback.lua:5: attempt to index local 't' (a nil value)
stack traceback:
	examples/ch09/traceback.lua:5: in function 'inner'
	examples/ch09/traceback.lua:8: in function <examples/ch09/traceback.lua:7>
	[C]: in function 'xpcall'
	examples/ch09/traceback.lua:12: in main chunk
	[C]: at 0x64426f4fb3a0
```

Read from the top: the error is in `inner` at line 5, called from line 8 in `outer`. `[C]` lines
are C functions; the last one's address varies. Like Lua 5.2, LuaJIT accepts arguments:
`xpcall(f, handler, ...)`.

A trap in your own handler: `return debug.traceback(e, 2)` is a **tail call**. It replaces the
handler's frame, shifting levels by one, so the frame where the error happened is skipped:

`examples/ch09/tailcall.lua`

```lua
local function inner() local t = nil; return t.x end
local function outer() inner(); return 1 end

-- Wrong: `return debug.traceback(...)` is a tail call. It replaces the
-- handler's own stack frame, so level 2 skips one frame too many.
local _, a = xpcall(outer, function(e) return debug.traceback(e, 2) end)
print(a)

-- Right: store the result first, then return it.
local _, b = xpcall(outer, function(e)
  local tb = debug.traceback(e, 2)
  return tb
end)
print(b)
```

```console
$ luajit examples/ch09/tailcall.lua
examples/ch09/tailcall.lua:1: attempt to index local 't' (a nil value)
stack traceback:
	examples/ch09/tailcall.lua:2: in function <examples/ch09/tailcall.lua:2>
	[C]: in function 'xpcall'
	examples/ch09/tailcall.lua:6: in main chunk
	[C]: at 0x5946ed7423a0
examples/ch09/tailcall.lua:1: attempt to index local 't' (a nil value)
stack traceback:
	examples/ch09/tailcall.lua:1: in function 'inner'
	examples/ch09/tailcall.lua:2: in function <examples/ch09/tailcall.lua:2>
	[C]: in function 'xpcall'
	examples/ch09/tailcall.lua:10: in main chunk
	[C]: at 0x5946ed7423a0
```

The first traceback lacks the key line, `in function 'inner'`. Store the result in a local (or a
table) and return that.

## Cleaning up without `finally`

Lua has no `try`/`finally`. To release something (close a file, remove a lock) even on error,
catch the error, clean up, and raise it again:

`examples/ch09/cleanup.lua`

```lua
-- No `finally` in Lua: catch the error, clean up, then raise it again.
local function open(name)
  print("open " .. name)
  return { name = name, close = function(self) print("close " .. self.name) end }
end

local function with(resource, fn)
  local ok, err = pcall(fn, resource)
  resource:close()                -- runs whether fn failed or not
  if not ok then
    error(err, 0)                 -- level 0: keep the original position
  end
  return err                      -- on success, err holds fn's first result
end

print(with(open("a"), function(r) return "used " .. r.name end))
print(pcall(with, open("b"), function(r) error("disk full") end))
```

```console
$ luajit examples/ch09/cleanup.lua
open a
close a
used a
open b
close b
false	examples/ch09/cleanup.lua:17: disk full
```

- `error(err, 0)` re-raises with level 0 because `err` already has a position. Level 1 would add a
  second `file:line:` prefix pointing into `with`.
- A helper like `with` keeps the pattern in one place; callers write only the body.

## Exit codes

A program's **exit status** tells its caller whether it worked: `0` for success, anything else
for failure. Shells test it (`$?`, `&&`, `if`). `os.exit(code)` ends the program at once with that
status; `true` means 0, `false` means 1:

```console
$ luajit -e 'os.exit(3)'; echo "exit $?"
exit 3
$ luajit -e 'os.exit(false)'; echo "exit $?"
exit 1
$ luajit -e 'print("done")'; echo "exit $?"
done
exit 0
$ luajit -e 'error("oops", 0)' 2>/dev/null; echo "exit $?"
exit 1
```

- A normal end gives 0; an uncaught error gives 1.
- `os.exit` skips everything after it, including pending cleanup. Call it once, at the very end.
- Choose and document your codes. Many tools use 1 for "it didn't work" and 2 for "you used me
  wrong".

## Building stash: consistent errors and exit codes

The plan:

- Expected problems are raised as **error objects** with a `kind`: `usage` (the user typed
  something wrong), `not_found`, or `failed`. Any code can raise one; no passing back up.
- `main.run` catches everything with `xpcall`. Anything that isn't an error object is a **bug**:
  `stash` says "internal error" and keeps the traceback for `STASH_DEBUG`.
- Messages go to **stderr**, so `stash list > out.txt` never writes errors into `out.txt`.
- Exit codes: 0 success, 1 not found, 2 usage error or failure. The launcher passes it to
  `os.exit`.

### The errors module

Create `src/stash/errors.lua`:

`src/stash/errors.lua`

```lua
-- Errors stash expects -- bad usage, a missing entry, a failed operation --
-- are raised as tables with a `kind` and a `message`. Any other error
-- value (usually a string from a runtime error) means a bug.

local M = {}

local Error = {}
Error.__index = Error

function Error.__tostring(e)
  return e.message
end

-- The process exit code for each kind of error.
M.EXIT = { not_found = 1, usage = 2, failed = 2, bug = 2 }

local function raise(kind, fmt, ...)
  -- A table error value carries no "file:line:" prefix, so no level is needed.
  error(setmetatable({ kind = kind, message = fmt:format(...) }, Error))
end

function M.usage(fmt, ...) raise("usage", fmt, ...) end
function M.not_found(fmt, ...) raise("not_found", fmt, ...) end
function M.fail(fmt, ...) raise("failed", fmt, ...) end

function M.is_error(value)
  return getmetatable(value) == Error
end

return M
```

- The `Error` metatable marks error objects; `is_error` checks for it.
- `raise` formats the message like `fail` did: `errors.usage("bad tag '%s'", tag)`.
- `usage`, `not_found` and `fail` never return, since `error` doesn't.

### Raising errors in the commands

In `src/stash/commands.lua`, require `errors` and add a `need_id` helper below `order`. The top of
the file becomes:

```lua
-- The commands. Each one gets a context table `ctx` (the store, the
-- settings, and an `out` function for output) plus the parsed options.
-- Problems are raised with the helpers in stash.errors; main turns them
-- into messages and exit codes.

local Entry = require("stash.entry")
local errors = require("stash.errors")
local util = require("stash.util")

local VERSION = "0.1.0"

local commands = {}                          -- name -> command record
local order = {}                             -- names in the order help shows them

-- Parses the ID argument of show and rm.
local function need_id(opts)
  local id = tonumber(opts[1])
  if id == nil then
    errors.usage(opts[1] and "bad ID '%s'" or "missing ID", opts[1])
  end
  return id
end
```

Delete `fail`. In every command, replace `return fail(...)` with an `errors` call. Messages drop
the command name; `main` adds it. In `add`:

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
    local entry = ctx.store:add(Entry.new({ url = url, tags = tags, note = opts.note }))
    ctx.out("added " .. tostring(entry))
  end,
}
```

In `search`:

```lua
command "search" {
  usage = "search TERM",
  help = "find bookmarks containing TERM",
  run = function(ctx, opts)
    local term = opts[1]
    if term == nil then
      errors.usage("missing TERM")
    end
    local found = ctx.store:search(term)
    for _, entry in ipairs(found) do
      ctx.out(format_row(entry))
    end
    if #found == 0 then
      errors.not_found("nothing matches '%s'", term)
    end
  end,
}
```

`show` and `rm` use `need_id`; `or` raises `not_found` when the store returns `nil`:

```lua
command "show" {
  usage = "show ID",
  help = "show one bookmark",
  run = function(ctx, opts)
    local id = need_id(opts)
    local entry = ctx.store:get(id) or errors.not_found("no entry with id %d", id)
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
    local id = need_id(opts)
    local entry = ctx.store:remove(id) or errors.not_found("no entry with id %d", id)
    ctx.out("removed " .. tostring(entry))
  end,
}
```

`errors.not_found(...)` runs only when the left side of `or` is `nil`, and never returns, so
`entry` is always an entry after that line.

### Catching errors in main

Replace `src/stash/main.lua` with:

`src/stash/main.lua`

```lua
-- Entry point: load the settings, pick the command, run it, and turn any
-- error into a message on stderr plus an exit code.

local cli = require("stash.cli")
local commands = require("stash.commands")
local config = require("stash.config")
local errors = require("stash.errors")
local util = require("stash.util")
local MemoryStore = require("stash.memstore")
local sample = require("stash.sample")

local M = {}

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

-- Messages go to stderr so they never mix with real output.
-- (io.stderr:write is covered in Chapter 12.)
local function report(line)
  io.stderr:write(line, "\n")
end

-- Does the work. Raises errors instead of returning them; `state` records
-- the command being run, for the error report.
local function execute(args, state)
  local settings, err = config.load(M.home() .. "/config.lua")
  if settings == nil then
    errors.fail("%s", err)
  end

  args = expand_alias(args, settings.aliases)
  local name = args[1]
  if name == nil or name == "-h" or name == "--help" then
    name = "help"
  elseif name == "--version" then
    name = "version"
  end

  local command = commands[name] or errors.usage("unknown command '%s'", name)
  state.command = command
  local opts, perr = cli.parse(args, 2, command.options)
  if opts == nil then
    errors.usage("%s", perr)
  end

  local ctx = {
    store = MemoryStore.new(sample),
    config = settings,
    out = print,
  }
  command.run(ctx, opts)
end

-- Runs stash with the given arguments and returns the exit code:
-- 0 success, 1 not found, 2 usage error or failure.
function M.run(args)
  local state = {}
  -- The handler runs where the error happened, before the stack unwinds,
  -- so it is the last chance to capture a traceback.
  local ok, err = xpcall(function() execute(args, state) end, function(e)
    if errors.is_error(e) then
      return e
    end
    return { kind = "bug", message = tostring(e), traceback = debug.traceback(tostring(e), 2) }
  end)
  if ok then
    return 0
  end

  local command = state.command
  if err.kind == "usage" and command then
    report(("stash %s: %s"):format(command.name, err.message))
    report("usage: stash " .. command.usage)
  elseif err.kind == "usage" then
    report("stash: " .. err.message .. " (try 'stash help')")
  elseif err.kind == "bug" then
    report("stash: internal error: " .. err.message)
    if os.getenv("STASH_DEBUG") then
      report(err.traceback)
    end
  else
    report("stash: " .. err.message)
  end
  return errors.EXIT[err.kind]
end

return M
```

How it fits together:

- `execute` is the old `run`, using `errors.*` instead of `fail`. It records the command in
  `state.command` before parsing, so the report knows which usage line to print.
- `M.run` calls `execute` through `xpcall`. The handler passes error objects through and wraps
  anything else in a `bug` table, capturing the traceback while the stack still exists. The
  `debug.traceback` call sits inside a table constructor, so it isn't a tail call.
- The report depends on the kind; usage errors with a known command add its usage line.
- `M.run` **returns** the exit code instead of calling `os.exit`, so callers (Chapter 10's tests)
  get the code and keep running.

`config.load` keeps the `nil, message` convention, which suits a library function; `execute`
turns it into an error with `errors.fail`.

### Config runtime errors

A runtime error in the config file is the user's problem, not a `stash` bug. In
`src/stash/config.lua`, replace the `chunk()` line with a `pcall`:

```lua
  local env = {}
  setfenv(chunk, env)                        -- globals of the chunk now live in env
  local ok, run_err = pcall(chunk)           -- a runtime error in the file is not our bug
  if not ok then
    return nil, run_err
  end
```

### The launcher

The last line of `stash` passes the exit code on:

`stash`

```lua
#!/usr/bin/env luajit
-- The stash launcher: makes src/ importable, then hands over to stash.main.

-- arg[0] is this script's path; its directory holds src/. This way stash
-- works from any current directory.
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = dir .. "/src/?.lua;" .. package.path

require("stash.strict")
os.exit(require("stash.main").run(arg))
```

### Checkpoint

```console
$ ./stash show 2; echo "exit $?"
id:    2
title: LuaJIT
url:   https://luajit.org/
tags:  jit, lua
exit 0
$ ./stash show 9; echo "exit $?"
stash: no entry with id 9
exit 1
$ ./stash show two; echo "exit $?"
stash show: bad ID 'two'
usage: stash show ID
exit 2
$ ./stash add; echo "exit $?"
stash add: missing URL
usage: stash add URL [-t TAGS] [-n NOTE]
exit 2
$ ./stash search python; echo "exit $?"
stash: nothing matches 'python'
exit 1
$ ./stash search python 2>/dev/null; echo "exit $?"
exit 1
$ ./stash frobnicate; echo "exit $?"
stash: unknown command 'frobnicate' (try 'stash help')
exit 2
$ ./stash list --limit; echo "exit $?"
stash list: --limit needs a value
usage: stash list [-t TAG] [--limit N]
exit 2
$ export STASH_HOME=demo
$ mkdir -p demo
$ echo "list_limit = 2 + nil" > demo/config.lua
$ ./stash list; echo "exit $?"
stash: demo/config.lua:1: attempt to perform arithmetic on a nil value
exit 2
```

- Usage errors print the usage line and exit 2; missing entries exit 1.
- `2>/dev/null` hides the message: it went to stderr.
- Chapter 8's config crash is now a one-line message with exit code 2.

The `bug` path needs a bug; Exercise 1 plants one.

The complete project at this point is in `project/ch09/`.

## Summary

- `error(value, level)` raises; level 1 blames the current line, 2 the caller, 0 adds nothing.
  Tail calls remove frames and shift levels.
- `pcall(f, ...)` returns `true, results...` or `false, err`. `xpcall(f, handler)` runs the handler
  before unwinding; use it with `debug.traceback`, without a tail call.
- `assert(v, msg)` raises `msg` if `v` is false or nil, else returns all arguments; `assert(f())`
  turns `nil, message` into an error.
- Return `nil, message` for expected failures; raise for bugs and failures handled far away.
- Error values can be tables with fields and a metatable, unlike Lua's string errors.
- No `finally`: `pcall`, clean up, `error(err, 0)`. A helper keeps it in one place.
- `os.exit(code)` sets the exit status: 0 is success; an uncaught error gives 1.

## Exercises

1. In a copy of `project/ch09`, change `entry.title` to `entry.titel` in `format_row`. Run
   `stash list`, then `STASH_DEBUG=1 stash list`. Where does the message point, and where is the
   real mistake?

<details><summary>Solution</summary>

```console
$ ./stash list; echo "exit $?"
stash: internal error: ./src/stash/util.lua:19: attempt to get length of local 's' (a nil value)
exit 2
$ STASH_DEBUG=1 ./stash list
stash: internal error: ./src/stash/util.lua:19: attempt to get length of local 's' (a nil value)
./src/stash/util.lua:19: attempt to get length of local 's' (a nil value)
stack traceback:
	./src/stash/util.lua:19: in function 'truncate'
	./src/stash/commands.lua:36: in function 'format_row'
	./src/stash/commands.lua:71: in function 'run'
	./src/stash/main.lua:68: in function 'execute'
	./src/stash/main.lua:77: in function <./src/stash/main.lua:77>
	[C]: in function 'xpcall'
	./src/stash/main.lua:77: in function 'run'
	./stash:10: in main chunk
	[C]: at 0x5c0dde82a3a0
```

The message points into `util.truncate`, which got `nil`. The mistake is one line down the
traceback: `format_row` at `commands.lua:36`. The message says what went wrong; the traceback says
how the program got there.

</details>

2. `stash show 1.5` prints `stash: no entry with id 1`, wrong twice: `%d` cuts `1.5` to `1`, and
   `1.5` is no id at all. Make `need_id` reject anything but whole numbers from 1 up, as a usage
   error.

<details><summary>Solution</summary>

```lua
local function need_id(opts)
  local id = tonumber(opts[1])
  if id == nil or id % 1 ~= 0 or id < 1 then
    errors.usage(opts[1] and "bad ID '%s'" or "missing ID", opts[1])
  end
  return id
end
```

```console
$ ./stash show 1.5; echo "exit $?"
stash show: bad ID '1.5'
usage: stash show ID
exit 2
$ ./stash show 0; echo "exit $?"
stash show: bad ID '0'
usage: stash show ID
exit 2
```

`id % 1` is the fractional part ([Chapter 2](02-values-and-types.md)): 0 for whole numbers.

</details>

3. Write `retry(times, fn)`: call `fn(attempt)` up to `times` times, return the first successful
   result, and if all fail, raise the last error unchanged.

<details><summary>Solution</summary>

```lua
local function retry(times, fn)
  local last
  for attempt = 1, times do
    local ok, result = pcall(fn, attempt)
    if ok then
      return result
    end
    last = result
  end
  error(last, 0)                       -- every attempt failed: raise the last error
end

print(retry(3, function(n)
  if n < 3 then error("flaky " .. n) end
  return "ok on try " .. n
end))
print(pcall(retry, 2, function(n) error("down " .. n) end))
```

```console
ok on try 3
false	retry.lua:17: down 2
```

Level 0 keeps the original `retry.lua:17:` position. Level 1 (the default) would add a second
prefix pointing at the `error` line in `retry`.

</details>

4. Why does `M.run` in `main.lua` return the exit code instead of calling `os.exit` itself?

<details><summary>Solution</summary>

`os.exit` ends the whole process. If `run` called it, no caller could continue afterwards: not a
test checking the exit code of `stash show 9`, nor a program embedding `stash`. Returning the code
leaves the decision to the caller; only the launcher, the outermost layer, exits.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-9--errors)
