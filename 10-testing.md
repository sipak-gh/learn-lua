# Chapter 10 — Testing

So far we checked `stash` by running it and reading the output. That doesn't scale: any change
can break something you didn't look at. This chapter builds a test framework in about 130 lines of
plain Lua and writes 26 tests for `stash`. It uses most of Part I: functions as values, tables,
metatables, environments, error levels and tracebacks.
[Chapter 9](09-errors.md) set up error handling; [Chapter 11](11-coroutines.md) starts Part II.

## Why not just `assert`?

`assert` works to start with:

`examples/ch10/plain.lua`

```lua
-- Testing with plain assert: it works, but it stops at the first failure
-- and says nothing about the values.
local function slug(s)
  return (s:lower():gsub("%W+", "-"))
end

assert(slug("Hello") == "hello")
assert(slug("Hello, World") == "hello-world")
assert(slug("  trim me  ") == "trim-me")
print("all passed")              -- never reached
```

```console
$ luajit examples/ch10/plain.lua
luajit: examples/ch10/plain.lua:9: assertion failed!
stack traceback:
	[C]: in function 'assert'
	examples/ch10/plain.lua:9: in main chunk
	[C]: at 0x62e1ddc443a0
[exit 1]
```

Two problems:

- It stops at the **first** failure, so you don't know how much is broken.
- `assertion failed!` doesn't say what the value **was**; you have to add prints.

A test framework fixes both: it runs each test in its own `pcall`, keeps counting, and its
assertions show the values they compared.

## A test runner in 30 lines

Three ideas:

- `test(name, fn)` only **registers** a test, storing it in a list.
- The runner calls each with `pcall`, so one failure doesn't stop the rest.
- It ends with a summary and an exit code. Scripts and CI systems check the code, not the text.

`examples/ch10/mini.lua`

```lua
-- A test runner in 30 lines: register tests, run each one protected,
-- count, report, and set the exit code.
local tests = {}

local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function eq(actual, expected)
  if actual ~= expected then
    -- level 2: blame the line in the test that called eq
    error(("expected %q, got %q"):format(tostring(expected), tostring(actual)), 2)
  end
end

local function slug(s)
  return (s:lower():gsub("%W+", "-"))
end

test("lowercases", function() eq(slug("Hello"), "hello") end)
test("joins words", function() eq(slug("Hello, World"), "hello-world") end)
test("trims", function() eq(slug("  trim me  "), "trim-me") end)
test("empty string", function() eq(slug(""), "") end)

local failed = 0
for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if not ok then
    failed = failed + 1
    print("FAIL " .. t.name .. ": " .. err)
  end
end
print(("%d passed, %d failed"):format(#tests - failed, failed))
os.exit(failed == 0)                 -- true -> 0, false -> 1
```

```console
$ luajit examples/ch10/mini.lua
FAIL trims: examples/ch10/mini.lua:22: expected "trim-me", got "-trim-me-"
3 passed, 1 failed
[exit 1]
```

It found a real bug: `slug` turns the spaces around `trim me` into dashes. The message shows both
values, quoted so spaces are visible, and points at the test (line 22) because `eq` raises with
level 2.

Some frameworks use `describe` and `it` instead of `test`: `describe("slug", function()
it("trims", function() ... end) end)`. Same idea, one more level of grouping.

## Deep equality

`==` on tables compares **identity**: two separate tables are never equal, even with the same
contents. Tests almost always want contents, which takes a recursive function:

`examples/ch10/deep.lua`

```lua
-- == compares tables by identity. Tests usually want "same contents".
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not same(v, b[k]) then        -- recursion handles nested tables
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then              -- a key that only b has
      return false
    end
  end
  return true
end

print({ 1, 2 } == { 1, 2 })
print(same({ 1, 2 }, { 1, 2 }))
print(same({ tags = { "a" }, n = 1 }, { n = 1, tags = { "a" } }))
print(same({ 1, 2 }, { 1, 2, 3 }), same({ 1, 2, 3 }, { 1, 2 }))
print(same({ x = { 1 } }, { x = { 2 } }))
```

```console
$ luajit examples/ch10/deep.lua
false
true
true
false	false
false
```

- Non-tables are compared with `==`.
- Every key of `a` needs an equal value in `b`; recursion handles nested tables.
- The second loop catches keys only `b` has.

It ignores metatables, and a table containing itself would recurse forever. Fine for test data.

## Pointing at the right line

For a helper assertion, level 2 in `error` blames the line that called it. That works for `eq`
above. But if `eq` calls a shared `fail` function, the test is one level further up.
`debug.getinfo(level, "Sl")` describes any stack level: `short_src` is the file, `currentline` the
line.

`examples/ch10/getinfo.lua`

```lua
-- debug.getinfo(level, "Sl"): where is the code at that level of the stack?
-- 1 = the running function, 2 = its caller, 3 = the caller's caller.
local function where(level)
  local info = debug.getinfo(level, "Sl")
  return info.short_src .. ":" .. info.currentline
end

local function check()
  print("level 1: " .. where(1 + 1))      -- +1: skip `where` itself
  print("level 2: " .. where(2 + 1))
  print("level 3: " .. where(3 + 1))
end

local function a_test()
  check()                                  -- line 15
end

a_test()                                   -- line 18
```

```console
$ luajit examples/ch10/getinfo.lua
level 1: examples/ch10/getinfo.lua:9
level 2: examples/ch10/getinfo.lua:15
level 3: examples/ch10/getinfo.lua:18
```

Level 1 is the running function, 2 its caller, and so on. Inside `where`, each level is one
higher, since `where` itself is level 1. `stash`'s runner uses this: `fail` asks for level 3,
skipping `fail` and the assertion to land on the test line.

## Testing code that does I/O

Pure functions (arguments in, values out) are easiest to test. Code that prints, reads files or
reads the clock is harder: the test must capture or fake the outside world. The simplest fix is
to pass the outside world in:

`examples/ch10/capture.lua`

```lua
-- Code that prints is hard to test. Code that calls an `out` function
-- it was given is easy: the test passes one that collects the lines.
local function greet_all(names, out)
  for i, name in ipairs(names) do
    out(("%d. hello, %s"):format(i, name))
  end
end

greet_all({ "Ada", "Bob" }, print)            -- the program passes print

local lines = {}
greet_all({ "Ada", "Bob" }, function(line) lines[#lines + 1] = line end)
print(#lines, lines[2])                       -- the test inspects the output
print(table.concat(lines, "\n") == "1. hello, Ada\n2. hello, Bob")
```

```console
$ luajit examples/ch10/capture.lua
1. hello, Ada
2. hello, Bob
2	2. hello, Bob
true
```

That's why `stash`'s commands write through `ctx.out` since [Chapter 8](08-modules.md): the program
passes `print`, a test passes a collector. The same works for the store (a test passes a
`MemoryStore` with known data) and, later, the clock.

## Fixtures, temporary files and golden output

- A **fixture** is a fixed input a test needs, such as a sample config file or a small database.
  `stash` keeps them in `test/fixtures/`; tests refer to them by path.
- Tests that **write** files need a scratch place, cleaned up afterwards. `os.tmpname()` returns a
  temporary file name. In LuaJIT on Linux and macOS it also creates the empty file under `/tmp`; on
  Windows it only returns a name. Either way, you remove the file. `stash`'s tests write files from
  [Chapter 12](12-io-and-os.md) on, using a `.test-tmp/` directory in the project instead: easy to
  inspect and delete.
- A **golden test** compares output with a stored "golden" copy. It suits long outputs, such as
  reports or help text, too unwieldy to write as strings in the test. When the output changes on
  purpose, replace the file and review the change.

`examples/ch10/report.lua`

```lua
-- The code under test: formats a small table report.
return function(rows)
  local lines = { ("%-10s %5s"):format("name", "count") }
  for _, row in ipairs(rows) do
    lines[#lines + 1] = ("%-10s %5d"):format(row.name, row.count)
  end
  return table.concat(lines, "\n") .. "\n"
end
```

`examples/ch10/golden/report.txt`

```text
name       count
lua           12
jit            3
```

`examples/ch10/golden.lua`

```lua
-- A golden test compares output with a file that holds the expected text.
-- (io.open and file reading are covered in Chapter 12.)
local report = dofile("examples/ch10/report.lua")

local function read_file(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  return text
end

local function lines(s)
  local result = {}
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    result[#result + 1] = line
  end
  return result
end

local function check_golden(actual, path)
  local expected = read_file(path)
  if actual == expected then
    return true
  end
  local a, e = lines(actual), lines(expected)
  for i = 1, math.max(#a, #e) do          -- point at the first line that differs
    if a[i] ~= e[i] then
      return false, ("%s line %d:\n  expected %q\n  actual   %q"):format(
        path, i, tostring(e[i]), tostring(a[i]))
    end
  end
end

local rows = { { name = "lua", count = 12 }, { name = "jit", count = 3 } }
print(check_golden(report(rows), "examples/ch10/golden/report.txt"))

rows[2].count = 30
print(check_golden(report(rows), "examples/ch10/golden/report.txt"))
```

```console
$ luajit examples/ch10/golden.lua
true
false	examples/ch10/golden/report.txt line 3:
  expected "jit            3"
  actual   "jit           30"
```

Reporting the first differing line, quoted with `%q` so edge spaces show, saves much squinting.

## Building stash: a test suite

`stash` gets a test runner, `test/run.lua`, and one test file per module:

```text
project/ch10/test/
├── run.lua               the runner and the assertions
├── util_test.lua         split, truncate, title_from_url
├── cli_test.lua          cli.parse
├── entry_test.lua        the Entry class
├── memstore_test.lua     the MemoryStore class
├── config_test.lua       config.load, using the fixtures
├── commands_test.lua     commands, with a captured ctx.out
└── fixtures/
    ├── config_ok.lua
    ├── config_type.lua
    └── config_typo.lua
```

`src/` doesn't change. Run the tests from the project root: `luajit test/run.lua`.

### The runner

Create `test/run.lua`:

`test/run.lua`

```lua
-- A tiny test runner. Run it from the project root:
--
--   luajit test/run.lua          run every test file
--   luajit test/run.lua cli      run only files whose name contains "cli"
--
-- Each test file calls test(name, fn) and the assertions below; they are
-- handed to the file through its environment, so they need no require.

package.path = "src/?.lua;" .. package.path
require("stash.strict")

-- Test files, in the order they run.
local FILES = {
  "util_test", "cli_test", "entry_test", "memstore_test", "config_test", "commands_test",
}

-- Formats a value for failure messages: strings are quoted.
local function show(v)
  if type(v) == "string" then
    return ("%q"):format(v)
  end
  return tostring(v)
end

-- Deep equality: tables are equal when they have equal keys and values.
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not same(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

-- A failed assertion raises a table, so the runner can tell it apart
-- from an unexpected error. debug.getinfo(3) describes the caller of the
-- assertion: the line in the test file.
local Failure = {}

local function fail(message)
  local info = debug.getinfo(3, "Sl")
  error(setmetatable({ text = ("%s:%d: %s"):format(info.short_src, info.currentline, message) },
                     Failure))
end

local assertions = {}

function assertions.eq(actual, expected)
  if actual ~= expected then
    fail(("expected %s, got %s"):format(show(expected), show(actual)))
  end
end

function assertions.same(actual, expected)
  if not same(actual, expected) then
    fail("tables differ")
  end
end

function assertions.ok(value, message)
  if not value then
    fail(message or "expected a true value")
  end
end

-- Calls fn and checks that it raises an error whose text contains `text`.
-- Returns the error value so the test can look at it further.
function assertions.raises(fn, text)
  local ok, err = pcall(fn)
  if ok then
    fail("expected an error")
  end
  if text and not tostring(err):find(text, 1, true) then
    fail(("error %s does not contain %s"):format(show(tostring(err)), show(text)))
  end
  return err
end

local passed, failed = 0, 0

local function run_file(name)
  local tests = {}
  local env = setmetatable({
    test = function(title, fn)
      tests[#tests + 1] = { title = title, fn = fn }
    end,
  }, { __index = function(_, key) return assertions[key] or _G[key] end })

  local chunk = assert(loadfile("test/" .. name .. ".lua"))
  setfenv(chunk, env)
  chunk()                                    -- registers the tests

  local file_failed = 0
  for _, t in ipairs(tests) do
    -- Failed assertions report their line; anything else gets a traceback.
    local ok, err = xpcall(t.fn, function(e)
      if getmetatable(e) == Failure then
        return e.text
      end
      -- Not `return debug.traceback(...)`: that tail call would replace
      -- this handler's frame, and level 2 would skip the failing test.
      local trace = debug.traceback(tostring(e), 2)
      return trace
    end)
    if ok then
      passed = passed + 1
    else
      failed, file_failed = failed + 1, file_failed + 1
      print(("FAIL %s: %s\n  %s"):format(name, t.title, tostring(err)))
    end
  end
  print(("%-16s %d tests, %d failed"):format(name, #tests, file_failed))
end

local filter = arg[1]
for _, name in ipairs(FILES) do
  if filter == nil or name:find(filter, 1, true) then
    run_file(name)
  end
end
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
```

How it works:

- **Setup.** Like the launcher, it adds `src/` to `package.path`, but relative to the current
  directory: run it from the project root. Strict mode catches the same global typos as in `stash`.
- **Assertions.** `eq` compares with `==`, `same` deeply, `ok` checks truth, and `raises` checks
  that a function raises an error containing some text. `raises` returns the error so a test can
  check its `kind`.
- **Failures are tables.** `fail` raises a `Failure` whose message is already prefixed with
  `file:line` (level 3, see above). The handler treats a `Failure` as an expected test failure,
  with no traceback. Anything else (a runtime error in the test or in `stash`) gets a full
  traceback: the same split `stash` makes between error objects and bugs. As in Chapter 9, the
  traceback goes into a local to avoid the tail call.
- **Environments.** Each test file is loaded with `loadfile`, and `setfenv` gives it an environment
  containing `test`, whose `__index` checks `assertions`, then `_G`. So test files call `eq` and
  `same` without `require`, and still see `require`, `table` and the rest. An accidental global
  lands in the file's environment, not `_G`.
- **Register, then run.** Running the chunk only registers tests; the loop then runs each in
  `xpcall`.
- **Filter and exit code.** `luajit test/run.lua cli` runs only files whose name contains `cli`.
  The exit code is 0 only if every test passed.

### The tests

`test/util_test.lua`:

`test/util_test.lua`

```lua
local util = require("stash.util")

test("split trims pieces and drops empty ones", function()
  same(util.split(" a, b,,c ", ","), { "a", "b", "c" })
  same(util.split("", ","), {})
end)

test("truncate keeps short strings and marks cuts", function()
  eq(util.truncate("short", 10), "short")
  eq(util.truncate("exactly10!", 10), "exactly10!")
  eq(util.truncate("a bit too long", 10), "a bit t...")
end)

test("title_from_url drops scheme, query and trailing slashes", function()
  eq(util.title_from_url("https://www.lua.org/"), "www.lua.org")
  eq(util.title_from_url("https://www.lua.org/pil/?x=1#top"), "www.lua.org/pil")
  eq(util.title_from_url("not a url"), "not a url")
end)
```

Each test checks the normal case and the edges: an empty string, a string exactly at the width
limit, a non-URL.

`test/cli_test.lua`:

`test/cli_test.lua`

```lua
local cli = require("stash.cli")

local spec = {
  ["-t"] = { "tags", "list" },
  ["-n"] = { "note", "value" },
  ["--limit"] = { "limit", "number" },
  ["--body"] = { "body", "flag" },
}

test("positional arguments keep their order", function()
  same(cli.parse({ "add", "a", "b" }, 2, spec), { "a", "b" })
end)

test("options of every kind", function()
  local opts = cli.parse({ "x", "-n", "hi", "--limit", "5", "--body", "url" }, 1, spec)
  same(opts, { "x", "url", note = "hi", limit = 5, body = true })
end)

test("list options repeat and split on commas", function()
  local opts = cli.parse({ "-t", "a,b", "-t", "c" }, 1, spec)
  same(opts.tags, { "a", "b", "c" })
end)

test("errors come back as nil plus a message", function()
  local opts, err = cli.parse({ "--limit" }, 1, spec)
  eq(opts, nil)
  eq(err, "--limit needs a value")
  eq(select(2, cli.parse({ "--limit", "many" }, 1, spec)), "--limit needs a number")
  eq(select(2, cli.parse({ "--verbose" }, 1, spec)), "unknown option --verbose")
end)

test("a lone dash is positional", function()
  same(cli.parse({ "-" }, 1, spec), { "-" })
end)
```

Its own `spec`, with every kind of option, keeps it independent of the real commands.
`select(2, ...)` picks the message out of `nil, message`.

`test/entry_test.lua`:

`test/entry_test.lua`

```lua
local Entry = require("stash.entry")

test("new copies and sorts the tags", function()
  local tags = { "b", "a" }
  local e = Entry.new({ url = "https://x.org/", tags = tags })
  same(e.tags, { "a", "b" })
  same(tags, { "b", "a" })                   -- the caller's table is untouched
end)

test("title defaults to one made from the URL", function()
  eq(Entry.new({ url = "https://x.org/a/" }).title, "x.org/a")
  eq(Entry.new({ url = "https://x.org/", title = "X" }).title, "X")
end)

test("has_tag and tag_string", function()
  local e = Entry.new({ url = "https://x.org/", tags = { "lua", "db" } })
  ok(e:has_tag("lua"))
  ok(not e:has_tag("go"))
  eq(e:tag_string(), "db,lua")
  eq(e:tag_string(", "), "db, lua")
end)

test("matches ignores case and treats the term literally", function()
  local e = Entry.new({ url = "https://x.org/", title = "C++ Notes (50%)" })
  ok(e:matches("c++"))
  ok(e:matches("50%"))
  ok(not e:matches("python"))
end)

test("tostring and < use the id", function()
  local a = Entry.new({ id = 1, url = "https://a.org/", title = "A" })
  local b = Entry.new({ id = 2, url = "https://b.org/", title = "B" })
  eq(tostring(a), "#1 A")
  ok(a < b)
  local list = { b, a }
  table.sort(list)
  eq(list[1], a)
end)
```

The first test checks that `Entry.new` **copies** the tags, a Chapter 7 detail. The `matches`
test uses `+`, `(` and `%`, so it catches `matches` switching from a plain `find` to patterns.

`test/memstore_test.lua`:

`test/memstore_test.lua`

```lua
local Entry = require("stash.entry")
local MemoryStore = require("stash.memstore")

local function sample_store()
  return MemoryStore.new({
    { url = "https://a.org/", title = "Alpha", tags = { "x", "y" } },
    { url = "https://b.org/", title = "Beta", tags = { "y" }, note = "second" },
    { url = "https://c.org/", title = "Gamma" },
  })
end

test("add assigns increasing ids", function()
  local store = MemoryStore.new()
  eq(store:add(Entry.new({ url = "https://a.org/" })).id, 1)
  eq(store:add(Entry.new({ url = "https://b.org/" })).id, 2)
end)

test("get and remove", function()
  local store = sample_store()
  eq(store:get(2).title, "Beta")
  eq(store:remove(2).title, "Beta")
  eq(store:get(2), nil)
  eq(store:remove(2), nil)
end)

test("ids are not reused after remove", function()
  local store = sample_store()
  store:remove(3)
  eq(store:add(Entry.new({ url = "https://d.org/" })).id, 4)
end)

test("list filters by tag and stops at the limit", function()
  local store = sample_store()
  local function titles(list)
    local result = {}
    for i, e in ipairs(list) do result[i] = e.title end
    return result
  end
  same(titles(store:list({})), { "Alpha", "Beta", "Gamma" })
  same(titles(store:list({ tag = "y" })), { "Alpha", "Beta" })
  same(titles(store:list({ limit = 1 })), { "Alpha" })
end)

test("search looks at the note too", function()
  local found = sample_store():search("SECOND")
  eq(#found, 1)
  eq(found[1].title, "Beta")
end)

test("tags are counted, most used first", function()
  same(sample_store():tags(), { { tag = "y", count = 2 }, { tag = "x", count = 1 } })
end)
```

`sample_store()` builds a fresh store per test. Tests must not share data one of them might
change, or results depend on the run order.

`test/config_test.lua` and its fixtures:

`test/config_test.lua`

```lua
local config = require("stash.config")

test("a missing file gives the defaults", function()
  local settings = config.load("test/fixtures/no-such-file.lua")
  eq(settings.list_limit, 20)
  same(settings.aliases, {})
end)

test("settings come from the file", function()
  local settings = config.load("test/fixtures/config_ok.lua")
  eq(settings.list_limit, 5)
  eq(settings.aliases.ls, "list")
end)

test("unknown settings and wrong types are reported", function()
  local settings, err = config.load("test/fixtures/config_typo.lua")
  eq(settings, nil)
  eq(err, "test/fixtures/config_typo.lua: unknown setting 'list_limt'")
  eq(select(2, config.load("test/fixtures/config_type.lua")),
     "test/fixtures/config_type.lua: 'list_limit' must be a number")
end)
```

`test/fixtures/config_ok.lua`

```lua
list_limit = 5
aliases = { ls = "list" }
```

`test/fixtures/config_type.lua`

```lua
list_limit = "five"
```

`test/fixtures/config_typo.lua`

```lua
list_limt = 5
```

The fixtures are tiny on purpose: each has exactly the problem its test is about.

`test/commands_test.lua`:

`test/commands_test.lua`

```lua
local cli = require("stash.cli")
local commands = require("stash.commands")
local config = require("stash.config")
local MemoryStore = require("stash.memstore")

-- Runs a command against a store and returns its output as one string.
-- ctx.out collects lines in a table instead of printing them.
local function run(store, args)
  local lines = {}
  local ctx = {
    store = store,
    config = config.defaults,
    out = function(line) lines[#lines + 1] = line end,
  }
  local command = commands[args[1]]
  command.run(ctx, assert(cli.parse(args, 2, command.options)))
  return table.concat(lines, "\n")
end

local function sample_store()
  return MemoryStore.new({
    { url = "https://www.lua.org/", title = "Lua", tags = { "lua" } },
    { url = "https://luajit.org/", title = "LuaJIT", tags = { "lua", "jit" }, note = "fast" },
  })
end

test("list prints one aligned row per entry", function()
  eq(run(sample_store(), { "list" }), table.concat({
    "  1  Lua                                   lua",
    "  2  LuaJIT                                jit,lua",
  }, "\n"))
end)

test("add stores the entry", function()
  local store = sample_store()
  eq(run(store, { "add", "https://sqlite.org/", "-t", "DB" }), "added #3 sqlite.org")
  eq(store:get(3).tags[1], "db")
end)

test("show prints the fields", function()
  eq(run(sample_store(), { "show", "2" }), [[
id:    2
title: LuaJIT
url:   https://luajit.org/
tags:  jit, lua
note:  fast]])
end)

test("errors carry a kind", function()
  local err = raises(function() run(sample_store(), { "show", "7" }) end, "no entry with id 7")
  eq(err.kind, "not_found")
  err = raises(function() run(sample_store(), { "add", "lua.org" }) end, "does not look like a URL")
  eq(err.kind, "usage")
end)
```

The local `run` builds a `ctx` like `main.lua`, but with a known store, the default settings,
and an `out` that collects lines. The last test checks Chapter 9's error **objects**: their `kind`
decides the exit code, so it's worth testing.

### Checkpoint

Run all tests, then only `cli`. Then add two broken tests to `util_test.lua` (a failed assertion
and a runtime error) to see both reports, and restore the file:

```console
$ luajit test/run.lua
util_test        3 tests, 0 failed
cli_test         5 tests, 0 failed
entry_test       5 tests, 0 failed
memstore_test    6 tests, 0 failed
config_test      3 tests, 0 failed
commands_test    4 tests, 0 failed

26 passed, 0 failed
$ luajit test/run.lua cli
cli_test         5 tests, 0 failed

5 passed, 0 failed
$ cp test/util_test.lua test/util_test.lua.orig
$ echo 'test("a failing assertion", function() eq(1 + 1, 3) end)' >> test/util_test.lua
$ echo 'test("a runtime error", function() local t = nil; return t.x end)' >> test/util_test.lua
$ luajit test/run.lua util
FAIL util_test: a failing assertion
  test/util_test.lua:19: expected 3, got 2
FAIL util_test: a runtime error
  test/util_test.lua:20: attempt to index local 't' (a nil value)
stack traceback:
	test/util_test.lua:20: in function <test/util_test.lua:20>
	[C]: in function 'xpcall'
	test/run.lua:104: in function 'run_file'
	test/run.lua:126: in main chunk
	[C]: at 0x653eea6df3a0
util_test        5 tests, 2 failed

3 passed, 2 failed
[exit 1]
$ mv test/util_test.lua.orig test/util_test.lua
$ luajit test/run.lua util
util_test        3 tests, 0 failed

3 passed, 0 failed
```

- The failed assertion reports the test line, `test/util_test.lua:19`, with both values.
- The runtime error gets a traceback, whose first line is again in the test file. The
  `[C]: at 0x...` address varies.
- A failing run exits with status 1.

From now on, every chapter adds tests for what it builds.

The complete project at this point is in `project/ch10/`.

## Summary

- A test framework runs each test in `pcall` (or `xpcall`), counts failures, sets the exit code.
  Assertions report values, not just "failed".
- `test(name, fn)` registers; running comes later. `describe`/`it` adds grouping.
- Deep equality is a short recursive function; `==` on tables compares identity.
- Error levels and `debug.getinfo(level, "Sl")` point failures at the test line.
- Raise failures as tables to separate them from unexpected errors, which get a traceback.
- `setfenv` hands test files their assertions without `require` or globals.
- Pass the outside world in (`ctx.out`, a store) to test without real I/O. Use fixtures for
  inputs, a scratch directory for written files, golden files for long outputs.
- For bigger projects, established frameworks exist: [busted](https://lunarmodules.github.io/busted/)
  (`describe`/`it`) and [LuaUnit](https://github.com/bluebird75/luaunit) (xUnit style). Both run on
  LuaJIT.

## Exercises

1. In `fail`, change `debug.getinfo(3, "Sl")` to `debug.getinfo(2, "Sl")` and add a failing
   test. Which line does the report point at now? Why?

<details><summary>Solution</summary>

```console
$ echo 'test("a failing assertion", function() eq(1 + 1, 3) end)' >> test/util_test.lua
$ luajit test/run.lua util
FAIL util_test: a failing assertion
  test/run.lua:58: expected 3, got 2
util_test        4 tests, 1 failed

3 passed, 1 failed
```

Line 58 of `run.lua` is the `fail(...)` call in `eq`. Inside `fail`, level 1 is `fail`, 2 is
`eq`, 3 is the test calling `eq`. Every assertion calls `fail` directly, so 3 suits them all.

</details>

2. Write `test/errors_test.lua` for `stash.errors`: helpers raise error objects with the right
   `kind` and message, `is_error` rejects strings and look-alike tables, and every kind has an exit
   code. Add it to `FILES`.

<details><summary>Solution</summary>

```lua
local errors = require("stash.errors")

test("helpers raise error objects with a kind", function()
  local err = raises(function() errors.not_found("no entry with id %d", 7) end)
  ok(errors.is_error(err))
  eq(err.kind, "not_found")
  eq(err.message, "no entry with id 7")
  eq(tostring(err), "no entry with id 7")
  eq(raises(function() errors.usage("x") end).kind, "usage")
  eq(raises(function() errors.fail("x") end).kind, "failed")
end)

test("plain strings are not error objects", function()
  ok(not errors.is_error("boom"))
  ok(not errors.is_error({ kind = "usage", message = "fake" }))
end)

test("every kind has an exit code", function()
  same(errors.EXIT, { not_found = 1, usage = 2, failed = 2, bug = 2 })
end)
```

In `test/run.lua`:

```lua
local FILES = {
  "util_test", "cli_test", "entry_test", "memstore_test", "config_test", "commands_test",
  "errors_test",
}
```

```console
$ luajit test/run.lua
util_test        3 tests, 0 failed
cli_test         5 tests, 0 failed
entry_test       5 tests, 0 failed
memstore_test    6 tests, 0 failed
config_test      3 tests, 0 failed
commands_test    4 tests, 0 failed
errors_test      3 tests, 0 failed

29 passed, 0 failed
```

The look-alike has the right fields but not the `Error` metatable, which is what `is_error`
checks.

</details>

3. `same` only says `tables differ`. Make it say **where**: `tables differ at value.tags[2]:
   expected "b", got "c"`.

<details><summary>Solution</summary>

Replace `assertions.same` in `test/run.lua` (you can then delete the unused `same` function):

```lua
local function key_path(path, k)
  if type(k) == "string" and k:match("^[%a_][%w_]*$") then
    return path .. "." .. k
  end
  return path .. "[" .. show(k) .. "]"
end

-- nil if equal, else a description of the first difference found.
local function difference(actual, expected, path)
  if type(actual) ~= "table" or type(expected) ~= "table" then
    if actual ~= expected then
      return ("at %s: expected %s, got %s"):format(path, show(expected), show(actual))
    end
    return nil
  end
  for k, v in pairs(expected) do
    local d = difference(actual[k], v, key_path(path, k))
    if d then
      return d
    end
  end
  for k, v in pairs(actual) do
    if expected[k] == nil then
      return ("at %s: unexpected %s"):format(key_path(path, k), show(v))
    end
  end
  return nil
end

function assertions.same(actual, expected)
  local d = difference(actual, expected, "value")
  if d then
    fail("tables differ " .. d)
  end
end
```

With two demo tests added to `util_test.lua`:

```console
FAIL util_test: demo: nested difference
  test/util_test.lua:20: tables differ at value.tags[2]: expected "b", got "c"
FAIL util_test: demo: extra element
  test/util_test.lua:23: tables differ at value[3]: unexpected 3
```

`assertions.same` still calls `fail` directly, so level 3 still points at the test. If two keys
differ, `pairs` order decides which is reported; either helps.

</details>

4. `commands_test.lua` builds `ctx.config` from `config.defaults`. Why not call
   `config.load(main.home() .. "/config.lua")`, like `stash` does?

<details><summary>Solution</summary>

The result would depend on the machine: with a `~/.local/share/stash/config.lua` or `STASH_HOME`
set, `list_limit` or the aliases could differ, so tests could pass for one person and fail for
another. Tests should control all their inputs. The defaults are known; a test needing other
settings builds the table itself or uses a fixture.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-10--testing)
