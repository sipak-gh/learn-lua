# Chapter 12 — I/O and the OS

Until now `stash` forgot everything on exit. Here you learn the `io` library (files, standard
streams, pipes) and the `os` library (time, environment, files, shell commands). Then `stash` saves
bookmarks to a file, `add` reads titles from local HTML pages, and a new `export` command writes JSON.

Previous: [Chapter 11 — Coroutines](11-coroutines.md). Next: [Chapter 13 — FFI basics](13-ffi-basics.md).

## Opening, writing, reading

`io.open(path, mode)` returns a *file handle*. Call its methods with `:`: `f:write(...)`,
`f:read(...)`, `f:close()`.

`examples/ch12/files.lua`

```lua
-- Write a file, then read it back in different ways.

local path = "notes.txt"

-- Shows values with newlines visible, e.g. "a\n".
local function show(...)
  local out = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    out[i] = type(v) == "string" and '"' .. v:gsub("\n", "\\n") .. '"' or tostring(v)
  end
  print(table.concat(out, "  "))
end

-- io.open returns a file handle, or nil plus an error message.
local f = assert(io.open(path, "w"))         -- "w": create or truncate
f:write("first line\n", "second line\n")     -- any number of strings...
f:write(42, " ", 3.5, "\n")                  -- ...and numbers
f:write("last line, no newline")
f:close()

f = assert(io.open(path, "r"))               -- "r": read (the default)
show(f:read("*l"))                           -- one line, without the "\n"
show(f:read("*L"))                           -- one line, keeping the "\n"
show(f:read("*n", "*n"))                     -- two numbers
show(f:read(5))                              -- up to 5 bytes
show(f:read("*a"))                           -- everything that is left
show(f:read("*a"), f:read("*l"), f:read(1))  -- at the end of the file
f:close()

os.remove(path)
```

```console
$ luajit examples/ch12/files.lua
"first line"
"second line\n"
42  3.5
"\nlast"
" line, no newline"
""  nil  nil
```

`file:write` writes any number of strings and numbers as they are: no spaces, no newline. Numbers
look like `tostring` output.

`file:read` takes one or more *formats* and returns one value per format:

| format | reads | at end of file |
|---|---|---|
| `"*l"` | the next line, without the `"\n"` (the default) | `nil` |
| `"*L"` | the next line, with the `"\n"` | `nil` |
| `"*n"` | a number, skipping whitespace before it | `nil` |
| `"*a"` | the rest of the file | `""` (never `nil`) |
| a number `n` | up to `n` bytes | `nil` |

Notice:

- `"*n"` stopped right after `3.5`, so `f:read(5)` started at the leftover `"\n"`.
- `"*a"` at the end gives `""`, not `nil`. `while f:read("*a") do` never ends.
- In LuaJIT the `*` is optional (`f:read("a")`), as in Lua 5.3. This course writes `"*a"`, which
  works in every Lua version.

`f:close()` flushes buffered data and releases the OS file. The GC closes a lost handle eventually,
but that may be too late. Close files yourself.

### Open modes

The mode string is C's `fopen` mode:

`examples/ch12/modes.lua`

```lua
-- Open modes decide what you may do and where you start.

local path = "modes.txt"

local function show(label)
  local f = assert(io.open(path, "rb"))
  print(("%-3s %s"):format(label, (f:read("*a"):gsub("\n", "|"))))  -- "|" marks a newline
  f:close()
end

local f = assert(io.open(path, "w"))         -- w: truncate (or create)
f:write("hello\n")
f:close()
show("w")

f = assert(io.open(path, "a"))               -- a: every write goes to the end
f:write("more\n")
f:close()
show("a")

f = assert(io.open(path, "r+"))              -- r+: read and write, start at 0, no truncation
f:write("J")                                 -- overwrites the "h"
f:close()
show("r+")

f = assert(io.open(path, "w+"))              -- w+: truncate, then read and write
f:write("fresh")
f:seek("set")                                -- back to the start before reading
print("w+ " .. f:read("*a"))
f:close()

os.remove(path)

-- Failure is a normal return value, not an error:
print(io.open("no/such/file.txt"))
print(io.open("/", "w"))
```

```console
$ luajit examples/ch12/modes.lua
w   hello|
a   hello|more|
r+  Jello|more|
w+ fresh
nil	no/such/file.txt: No such file or directory	2
nil	/: Is a directory	21
```

| mode | read | write | starts at | creates | truncates |
|---|---|---|---|---|---|
| `"r"` | yes | no | start | no | no |
| `"w"` | no | yes | start | yes | yes |
| `"a"` | no | yes | end (always) | yes | no |
| `"r+"` | yes | yes | start | no | no |
| `"w+"` | yes | yes | start | yes | yes |
| `"a+"` | yes | yes | end for writes | yes | no |

- Add `b` (`"rb"`, `"wb"`) for "these exact bytes". On Linux and macOS it changes nothing. On
  Windows, text mode turns `"\n"` into `"\r\n"` on write, and back on read.
- In `+` modes, call `f:seek` before switching from writing to reading (as `w+` does above). C
  requires a seek or flush between the two.

### Reading line by line

`examples/ch12/lines.lua`

```lua
-- Loop over the lines of a file.

local path = "lines.txt"
local f = assert(io.open(path, "w"))
f:write("alpha\nbeta\n\ngamma")              -- an empty line, no final newline
f:close()

-- io.lines(path) opens the file, yields each line, and closes it at the end.
for line in io.lines(path) do
  print(("[%s]"):format(line))
end

-- file:lines() does the same on a handle you opened. You close it yourself.
f = assert(io.open(path))
local n = 0
for line in f:lines() do n = n + 1 end
f:close()
print("lines:", n)

os.remove(path)

-- io.lines on a missing file raises an error (unlike io.open).
local ok, msg = pcall(function()
  for line in io.lines("missing.txt") do print(line) end
end)
print(ok, msg)
```

```console
$ luajit examples/ch12/lines.lua
[alpha]
[beta]
[]
[gamma]
lines:	4
false	examples/ch12/lines.lua:24: bad argument #1 to 'lines' (missing.txt: No such file or directory)
```

- `io.lines(path)` closes the file at the end. If you `break` early, it stays open until the GC
  collects the handle.
- The last line had no `"\n"` but still came back. The empty line came back as `""`.
- For a missing file, `io.open` returns `nil`; `io.lines` raises an error.
- LuaJIT's `io.lines` and `file:lines` also take read formats: `io.lines(path, "*L")` keeps the
  newlines. Plain Lua 5.1 can't.

### Moving around: seek

`file:seek(whence, offset)` sets the position and returns it, in bytes from the start of the file.
`whence` is `"set"` (from the start), `"cur"` (from here, the default) or `"end"`.

`examples/ch12/seek.lua`

```lua
-- file:seek(whence, offset) moves the read/write position and returns it.

local path = "seek.txt"
local f = assert(io.open(path, "w+"))
f:write("0123456789")

print("size:", f:seek("end"))       -- end + 0 = the file size
print("pos:", f:seek("set", 3))     -- absolute position 3
print("read:", f:read(2))           -- "34", position is now 5
print("pos:", f:seek("cur"))        -- current position, unchanged
print("pos:", f:seek("cur", -4))    -- move back 4
print("read:", f:read("*a"))
print("pos:", f:seek("end", -2))
print("read:", f:read("*a"))
f:close()

-- A common helper: the size of a file without reading it.
local function file_size(p)
  local h = io.open(p, "rb")
  if not h then return nil end
  local size = h:seek("end")
  h:close()
  return size
end
print("file_size:", file_size(path), file_size("missing.txt"))
os.remove(path)
```

```console
$ luajit examples/ch12/seek.lua
size:	10
pos:	3
read:	34
pos:	5
pos:	1
read:	123456789
pos:	8
read:	89
file_size:	10	nil
```

`f:seek()` only reports the position. `f:seek("end")` is the usual way to get a file's size. LuaJIT
uses 64-bit offsets, so files over 2 GB work.

## When things go wrong

`examples/ch12/errors.lua`

```lua
-- Most io and os functions report failure as: nil, message, errno.

local f, err, code = io.open("missing.txt")
print(f, err, code)

-- Pattern 1: check and handle.
if not f then
  print("could not open: " .. err)
end

-- Pattern 2: assert turns the failure into an error with that message.
print(pcall(function() return assert(io.open("missing.txt")) end))

-- io.type tells files apart from other values.
local h = assert(io.open(arg[0]))           -- arg[0] is this script
print(io.type(h), io.type(io.stdout), io.type("a string"))
h:close()
print(io.type(h))

-- Using a closed file is a real error, not a nil return.
print(pcall(h.read, h, "*l"))

-- os.remove and os.rename follow the same nil, message, errno convention.
print(os.remove("missing.txt"))
print(os.rename("missing.txt", "other.txt"))
```

```console
$ luajit examples/ch12/errors.lua
nil	missing.txt: No such file or directory	2
could not open: missing.txt: No such file or directory
false	missing.txt: No such file or directory
file	file	nil
closed file
false	attempt to use a closed file
nil	missing.txt: No such file or directory	2
nil	missing.txt: No such file or directory	2
```

Almost all `io` and `os` functions fail the same way: `nil`, a message with the file name, and the C
`errno` number (`2` is `ENOENT`, "no such file"). That is Lua's convention for errors you *expect*,
like a missing file. Unexpected errors, like using a closed file, are raised.

So you choose:

- Check the result when you can do something useful (use a default, try another path, tell the user).
- Wrap it in `assert(...)` when failure means a bug or the end of the program. `assert` raises the
  message.

`io.type(x)` returns `"file"`, `"closed file"`, or `nil` for anything else.

## Standard streams

Every program starts with three open files: `io.stdin`, `io.stdout` and `io.stderr`.

`examples/ch12/stdio.lua`

```lua
-- The three standard streams: io.stdin, io.stdout, io.stderr.

-- print adds tabs and a newline and calls tostring on everything.
print("print:", 1, nil, true)

-- io.write writes exactly what you give it (strings and numbers only).
io.write("io.write: ", 1, " ", 2.5, "\n")

-- io.write is short for io.output():write. io.stdout:write is the same here.
io.stdout:write("stdout:write\n")

-- Errors and diagnostics go to stderr, so they don't mix with real output.
io.stderr:write("stderr: something went wrong\n")

-- io.read reads from stdin. Here we read every line that was piped in.
local count = 0
for line in io.lines() do          -- io.lines() with no file = stdin
  count = count + 1
  io.write(("stdin %d: %s\n"):format(count, line))
end
print("lines on stdin:", count)
```

```console
$ printf "a\nb\n" | luajit examples/ch12/stdio.lua
print:	1	nil	true
io.write: 1 2.5
stdout:write
stderr: something went wrong
stdin 1: a
stdin 2: b
lines on stdin:	2
$ luajit examples/ch12/stdio.lua < /dev/null 2> /dev/null
print:	1	nil	true
io.write: 1 2.5
stdout:write
lines on stdin:	0
```

- `print` is for quick output: `tostring` on each value, tabs between, a newline at the end.
- `io.write(...)` writes exactly what you pass, like `file:write`. Use it when you control the format.
- Diagnostics belong on `io.stderr`. In the second run, `2> /dev/null` dropped stderr and the real
  output stayed clean. That's why `stash` prints errors with `io.stderr:write`.
- `io.read(...)` and `io.lines()` with no file name read stdin.

`io.write` and `io.read` use the *default* output and input files, initially stdout and stdin.
`io.output("log.txt")` or `io.input(file)` change them, but changing global state rarely pays off.
Writing to a handle you hold is clearer.

Output to a file or pipe is buffered: it collects in memory and goes out in chunks. `f:flush()`
sends it now. `f:setvbuf("no" | "line" | "full")` sets the mode. A terminal is line-buffered, so you
rarely notice.

## Running other programs: io.popen

`io.popen(command, mode)` runs a shell command and returns a handle connected to it. With `"r"` (the
default) you read its stdout; with `"w"` you write to its stdin.

`examples/ch12/popen.lua`

```lua
-- io.popen runs a shell command and connects a pipe to it.

-- Mode "r": read what the command prints.
local p = assert(io.popen("echo one; echo two", "r"))
for line in p:lines() do
  print("got: " .. line)
end
print("close:", p:close())   -- LuaJIT returns just true here, not the exit code

-- Mode "w": write to the command's stdin.
p = assert(io.popen("tr a-z A-Z", "w"))
p:write("shouted through a pipe\n")
p:close()

-- To get the exit status, have the shell print it.
p = assert(io.popen("ls missing-dir 2>/dev/null; echo \"[exit $?]\""))
print(p:read("*a"))
p:close()
```

```console
$ luajit examples/ch12/popen.lua
got: one
got: two
close:	true
SHOUTED THROUGH A PIPE
[exit 2]
```

In Lua 5.2+, `p:close()` returns the exit status. LuaJIT (without its 5.2 compatibility build
option) returns only `true`. The trick above works everywhere: have the shell print `$?` and read it
from the output. `stash`'s end-to-end tests do this.

The command goes through `/bin/sh`, so quoting matters. Never paste user input into a command
unquoted (see `shell_quote` in the project section).

## Time and dates

`examples/ch12/time.lua`

```lua
-- os.time, os.date, os.difftime, os.clock

-- os.time() with no argument: seconds since 1970-01-01 00:00 UTC (the "epoch").
local now = os.time()
print("now is a number:", type(now))

-- A fixed timestamp keeps this output the same on every run.
local t = 1767225600

-- os.date(format, time). A leading "!" means UTC; without it you get local time.
print(os.date("!%Y-%m-%d %H:%M:%S", t))
print(os.date("!%A, %d %B %Y", t))

-- "*t" (or "!*t") returns a table of fields instead of a string.
local d = os.date("!*t", t)
print(d.year, d.month, d.day, d.hour, d.min, d.sec, d.wday, d.yday)

-- os.time(table) goes the other way, but reads the table as LOCAL time.
-- Run with TZ=UTC so local time and UTC agree.
print(os.time({ year = 2026, month = 1, day = 1, hour = 0 }))

-- Fields may overflow; os.time normalizes them.
print(os.date("!%Y-%m-%d", os.time({ year = 2026, month = 1, day = 32, hour = 0 })))

-- os.difftime(t2, t1) = t2 - t1 in seconds (as a float).
print(os.difftime(t + 90, t))

-- os.clock(): CPU time used by this program, in seconds. Good for timing code.
local start = os.clock()
local x = 0
for i = 1, 1e7 do x = x + i end
print(("loop took %.3f s of CPU"):format(os.clock() - start))
```

```console
$ TZ=UTC luajit examples/ch12/time.lua
now is a number:	number
2026-01-01 00:00:00
Thursday, 01 January 2026
2026	1	1	0	0	0	5	1
1767225600
2026-02-01
90
loop took 0.005 s of CPU
```

The last line depends on your machine.

- `os.time()` is seconds since 1970-01-01 00:00 UTC. The number is the same everywhere on Earth, so
  it's a good thing to store.
- `os.date(format, t)` uses C's `strftime` codes: `%Y` year, `%m` month, `%d` day, `%H:%M:%S` time,
  `%A` weekday, `%B` month name. A leading `!` means UTC. Without it you get local time, and the same
  `t` prints differently on different machines.
- `os.date("*t", t)` returns a table: `year`, `month`, `day`, `hour`, `min`, `sec`, `wday`
  (1 = Sunday), `yday`, `isdst`.
- `os.time(table)` turns such a table back into a number. It reads the table as *local* time (hence
  `TZ=UTC` above) and normalizes: January 32 becomes February 1.
- `os.difftime(t2, t1)` is `t2 - t1`. On POSIX you can just subtract.
- `os.clock()` is CPU time used. Use it to time code, not to tell the time.

## The os library

`examples/ch12/osfiles.lua`

```lua
-- os.getenv, os.rename, os.remove, os.execute, os.exit

print("HOME set?", os.getenv("HOME") ~= nil)
print("NOPE:", os.getenv("STASH_DOES_NOT_EXIST"))   -- nil when unset

-- Write to a temporary name, then rename over the real file.
-- On POSIX, rename within one filesystem replaces the target in one step.
local f = assert(io.open("data.txt.tmp", "w"))
f:write("new contents\n")
f:close()
print("rename:", os.rename("data.txt.tmp", "data.txt"))
print("remove:", os.remove("data.txt"))
print("again: ", os.remove("data.txt"))

-- os.execute runs a shell command. LuaJIT returns the raw wait status:
-- 0 for success, exit code * 256 otherwise.
print("true  ->", os.execute("true"))
print("exit 3->", os.execute("exit 3"))
print("shell? ->", os.execute())    -- no argument: nonzero if a shell exists

-- os.exit(code) ends the program right away. true = 0, false = 1.
os.exit(4)
print("never printed")
```

```console
$ luajit examples/ch12/osfiles.lua
HOME set?	true
NOPE:	nil
rename:	true
remove:	true
again: 	nil	data.txt: No such file or directory	2
true  ->	0
exit 3->	768
shell? ->	1
[exit 4]
```

- `os.getenv(name)` returns an environment variable's value, or `nil`. `stash` uses it for
  `STASH_HOME` and, from now on, `STASH_NOW`.
- `os.rename(from, to)` and `os.remove(path)` return `true`, or `nil, message, errno`. `os.remove`
  deletes files and empty directories.
- `os.execute(command)` runs a shell command. LuaJIT returns the raw status from C's `system()`: `0`
  for success, otherwise the exit code times 256 (`3 * 256 = 768`). Lua 5.2+ returns `true`/`nil`,
  `"exit"`, `code` instead. Compare with `0`; don't rely on the exact number.
- `os.exit(code)` ends the process at once. `os.exit(true)` = success (0), `os.exit(false)` =
  failure (1). C's `exit()` flushes open files, but `__gc` finalizers run only if you pass `true` as
  a second argument, which closes the Lua state first.
- `os.tmpname()` returns a fresh temporary file name. On Linux and macOS, LuaJIT creates an empty file
  like `/tmp/lua_XXXXXX` (with `mkstemp`); you must remove it yourself. It's a file, not a directory,
  and `/tmp` may be on a different file system from your data. `stash` needs neither, as you'll see.
- `os` has little else (`os.setlocale`). No `os.mkdir`, no directory listing: standard Lua offers
  only what ANSI C offers. For more, use the shell or, from the next chapter, the FFI.

## Persisting data as Lua code

The simplest file format for a Lua program is Lua itself. Write the table as a Lua expression with
`return` in front; loading the file gives the table back. Lua began as a data description language,
so this fits naturally.

`examples/ch12/persist.lua`

```lua
-- Save a Lua table as Lua source, then load it back.

local function serialize(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "string" then
    return ("%q"):format(v)               -- quoted and escaped so Lua can read it back
  elseif t == "number" then
    return ("%.17g"):format(v)            -- 17 digits: the exact same double comes back
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    local inner = indent .. "  "
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = { "{\n" }
    for _, k in ipairs(keys) do
      local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k
                  or "[" .. serialize(k) .. "]"
      out[#out + 1] = inner .. key .. " = " .. serialize(v[k], inner) .. ",\n"
    end
    out[#out + 1] = indent .. "}"
    return table.concat(out)
  end
  error("cannot serialize a " .. t)
end

local data = {
  name = "stash",
  version = 0.1,
  tags = { "lua", "jit" },
  ["odd key"] = 'say "hi"\n',
}

local f = assert(io.open("data.lua", "w"))
f:write("return ", serialize(data), "\n")
f:close()

for line in io.lines("data.lua") do print(line) end

-- loadfile compiles the file into a function without running it.
local chunk = assert(loadfile("data.lua"))
setfenv(chunk, {})                         -- an empty environment: no os, no io, no print
local copy = chunk()
print(copy.name, copy.version, copy.tags[2], copy["odd key"])

-- The empty environment stops a malicious data file from doing harm.
f = assert(io.open("data.lua", "w"))
f:write('return os.execute("echo pwned")\n')
f:close()
chunk = assert(loadfile("data.lua"))
setfenv(chunk, {})
print(pcall(chunk))

os.remove("data.lua")
```

```console
$ luajit examples/ch12/persist.lua
return {
  name = "stash",
  ["odd key"] = "say \"hi\"\
",
  tags = {
    [1] = "lua",
    [2] = "jit",
  },
  version = 0.10000000000000001,
}
stash	0.1	jit	say "hi"

false	data.lua:1: attempt to index global 'os' (a nil value)
```

- `("%q"):format(s)` writes a string literal that reads back as the same bytes, quotes and newlines
  included. A newline becomes `\` plus a real line break, which is valid Lua for `"\n"`.
- `("%.17g"):format(n)` writes enough digits to read back the exact same double. `0.1` has no exact
  binary form, so 17 digits show the stored value `0.10000000000000001`. `tostring` uses 14 digits
  and can lose information.
- Keys are sorted. `pairs` has no fixed order; sorting makes the same data give the same file, which
  makes diffs and tests easy.
- `loadfile(path)` compiles a file into a function without running it. `setfenv(chunk, {})` gives it
  an empty environment ([Chapter 8](08-modules.md)), so the data file can't reach `os`, `io` or
  anything else. A data file should only build data.

Limits of this version:

- It writes array items as `[1] = "lua"`. The project version writes the array part first, without keys.
- A table that contains itself (`t.self = t`) makes it recurse forever. Exercise 5 fixes that.

## Building stash: files, pages and JSON

What changes:

- Bookmarks are saved to `$STASH_HOME/entries.lua`, a Lua data file, after every change. A
  `MemoryStore` subclass, `FileStore`, loads the file at start and saves after `add` and `rm`. SQLite
  replaces it in [Chapter 15](15-wrapping-sqlite.md).
- Entries get a `created` time. `list` shows the date, `show` the date and time.
- `add` reads `file://` pages and takes the title from `<title>`. Real `http(s)` downloads come in
  [Chapter 16](16-callbacks-and-curl.md); until then those URLs get a title made from the URL.
- New command `export [FILE]` writes all bookmarks as JSON.
- `sample.lua` is gone. A fresh `STASH_HOME` starts empty.

New: `fs.lua`, `serialize.lua`, `filestore.lua`, `fetch.lua`, `html.lua`, `json.lua`, tests and three
HTML fixtures. Changed: `util.lua`, `entry.lua`, `commands.lua`, `main.lua`, `test/run.lua`,
`test/commands_test.lua`. Delete `src/stash/sample.lua`.

### src/stash/util.lua

Add three time helpers before `return M`:

```lua
-- The current time in seconds since 1970. STASH_NOW overrides it, so
-- tests and examples get the same dates on every run.
function M.now()
  return tonumber(os.getenv("STASH_NOW")) or os.time()
end

-- Dates are shown in UTC ("!" in the format), again so that output does
-- not depend on the machine's time zone.
function M.date(t)
  return os.date("!%Y-%m-%d", t)
end

function M.datetime(t)
  return os.date("!%Y-%m-%d %H:%M UTC", t)
end
```

`STASH_NOW` replaces the clock so tests get fixed dates. If it's missing or not a number, `tonumber`
returns `nil` and `os.time()` is used.

### src/stash/entry.lua

`Entry.new` gets one more field, after `self.note`:

```lua
  self.created = fields.created or util.now()  -- seconds since 1970
```

And a new method, after `tag_string`:

```lua
-- A plain table with the same fields and no metatable: what we save to
-- disk or export as JSON.
function Entry:record()
  local tags = {}
  for i, tag in ipairs(self.tags) do
    tags[i] = tag
  end
  return { id = self.id, url = self.url, title = self.title, note = self.note,
           tags = tags, created = self.created }
end
```

Saving and exporting need plain data, not an object with a metatable. `record()` copies the fields
into a fresh table, `tags` included, so changing the record can't change the entry.

### src/stash/fs.lua (new)

Shared file helpers.

```lua
-- File system helpers.

local M = {}

-- Quotes a string for the shell: 'it'\''s' is how sh spells "it's".
local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Creates a directory and its parents, like `mkdir -p`.
-- Note: in LuaJIT os.execute returns the raw wait status (0 = success).
function M.mkdir_p(path)
  if os.execute("mkdir -p " .. shell_quote(path)) ~= 0 then
    return nil, "cannot create directory " .. path
  end
  return true
end

-- "a/b/c.lua" -> "a/b"; "c.lua" -> "."
function M.dirname(path)
  return path:match("^(.*)/[^/]*$") or "."
end

function M.exists(path)
  local file = io.open(path)
  if file then
    file:close()
  end
  return file ~= nil
end

function M.read_file(path)
  local file, err = io.open(path, "rb")
  if file == nil then
    return nil, err
  end
  local data = file:read("*a")
  file:close()
  return data
end

-- Opens a file, calls fn(file), and closes the file even when fn raises
-- an error -- Lua has no `finally`, so pcall plays that part.
function M.with_file(path, mode, fn)
  local file, err = io.open(path, mode)
  if file == nil then
    return nil, err
  end
  local ok, result = pcall(fn, file)
  file:close()
  if not ok then
    error(result, 0)                         -- re-raise, unchanged
  end
  return true, result
end

-- Writes data to path via a temporary file and a rename, so a crash
-- never leaves a half-written file behind.
function M.write_atomic(path, data)
  local tmp = path .. ".tmp"
  local ok, err = M.with_file(tmp, "wb", function(file)
    assert(file:write(data))
  end)
  if not ok then
    return nil, err
  end
  return os.rename(tmp, path)
end

return M
```

- **`mkdir_p`.** Standard Lua can't create directories, so we ask the shell. Inside single quotes
  `sh` takes every character literally except `'`, which we write as `'\''` (close quote, escaped
  `'`, reopen). Unquoted, a `STASH_HOME` with a space would break the command, and one containing
  `; rm -rf ~` would run it. [Chapter 13](13-ffi-basics.md) replaces this with C's `mkdir`.
- **`with_file`.** Lua has no `try`/`finally`; `pcall` stands in. Whatever `fn` does, the file gets
  closed, then the error is re-raised unchanged (`error(result, 0)` adds no position). Returns `true`
  plus `fn`'s result, or `nil` plus the open error.
- **`write_atomic`.** A crash halfway through writing `entries.lua` would lose all bookmarks. So we
  write a temporary file next to it, then `os.rename` it over the real one. On POSIX, `rename` within
  one file system is atomic: readers see the old file or the new one, never a mix. The temporary file
  must be in the same directory, so `os.tmpname()` won't do (exercise 4).

### src/stash/serialize.lua (new)

The serializer from [Persisting data](#persisting-data-as-lua-code), grown up:

```lua
-- Turns plain data (tables, strings, numbers, booleans) into Lua source
-- code that rebuilds it. Reading the data back is just loading that code.

local M = {}

local function is_identifier(key)
  return type(key) == "string" and key:find("^[%a_][%w_]*$") ~= nil
end

local function write(value, indent, out)
  local kind = type(value)
  if kind == "string" then
    out[#out + 1] = ("%q"):format(value)
  elseif kind == "number" then
    out[#out + 1] = ("%.17g"):format(value)  -- 17 digits: reads back exactly
  elseif kind == "boolean" then
    out[#out + 1] = tostring(value)
  elseif kind == "table" then
    -- Array part first, then the other keys in sorted order, so the same
    -- data always gives the same text.
    local inner = indent .. "  "
    out[#out + 1] = "{\n"
    for _, v in ipairs(value) do
      out[#out + 1] = inner
      write(v, inner, out)
      out[#out + 1] = ",\n"
    end
    local keys = {}
    for k in pairs(value) do
      if not (type(k) == "number" and k >= 1 and k <= #value and k % 1 == 0) then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      out[#out + 1] = inner
      if is_identifier(k) then
        out[#out + 1] = k
      else
        out[#out + 1] = "["
        write(k, inner, out)
        out[#out + 1] = "]"
      end
      out[#out + 1] = " = "
      write(value[k], inner, out)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = indent .. "}"
  else
    error("cannot serialize a " .. kind)
  end
end

function M.serialize(value)
  local out = {}
  write(value, "", out)
  return table.concat(out)
end

-- Loads data written by serialize. The chunk runs with an empty
-- environment: a data file cannot call any function.
function M.load(path)
  local chunk, err = loadfile(path)
  if chunk == nil then
    return nil, err
  end
  setfenv(chunk, {})
  local ok, value = pcall(chunk)
  if not ok then
    return nil, value
  end
  return value
end

return M
```

- `write` appends pieces to one `out` table; `serialize` joins them once at the end. That's the buffer
  pattern from [Chapter 6](06-strings.md): no long intermediate strings.
- The array part (`1..#value`) comes first, in order, without keys; other keys follow, sorted.
  `k % 1 == 0` keeps `1.5` out of the array part.
- `load` returns `nil, message` for a missing or broken file, and the caller decides. A syntax error
  includes file and line, such as `entries.lua:1: ...`.

### src/stash/filestore.lua (new)

```lua
-- FileStore: a MemoryStore that saves itself to a Lua data file after
-- every change. It inherits everything else from MemoryStore.
--
-- The file looks like:   return { next_id = 3, entries = { {...}, {...} } }

local Entry = require("stash.entry")
local MemoryStore = require("stash.memstore")
local errors = require("stash.errors")
local fs = require("stash.fs")
local serialize = require("stash.serialize")

-- Methods not found in FileStore are looked up in MemoryStore.
local FileStore = setmetatable({}, { __index = MemoryStore })
FileStore.__index = FileStore

-- Opens the store in `path`; a missing file means an empty store.
-- Returns the store, or nil and an error message.
function FileStore.open(path)
  local self = setmetatable(MemoryStore.new(), FileStore)
  self.path = path
  if not fs.exists(path) then
    return self
  end
  local data, err = serialize.load(path)
  if data == nil then
    return nil, err
  end
  for _, fields in ipairs(data.entries) do
    local entry = Entry.new(fields)
    self.by_id[entry.id] = entry             -- keep the saved ids
  end
  self.next_id = data.next_id
  return self
end

function FileStore:save()
  local records = {}
  for entry in self:entries() do
    records[#records + 1] = entry:record()
  end
  local text = "return " .. serialize.serialize({ next_id = self.next_id, entries = records }) .. "\n"
  local ok, err = fs.mkdir_p(fs.dirname(self.path))
  if ok then
    ok, err = fs.write_atomic(self.path, text)
  end
  if not ok then
    errors.fail("cannot save %s: %s", self.path, err)
  end
end

-- Overrides: do what MemoryStore does, then save.
function FileStore:add(entry)
  MemoryStore.add(self, entry)
  self:save()
  return entry
end

function FileStore:remove(id)
  local entry = MemoryStore.remove(self, id)
  if entry then
    self:save()
  end
  return entry
end

return FileStore
```

- This is inheritance ([Chapter 7](07-metatables-and-objects.md)). `FileStore`'s metatable sends
  missing keys to `MemoryStore`, so `get`, `list`, `entries` and the rest work unchanged.
- `FileStore` overrides only `add` and `remove`. They call `MemoryStore.add(self, entry)` (Lua's
  `super.add`), then save.
- Loading writes into `self.by_id` directly instead of calling `add`. That keeps saved ids and
  avoids saving once per entry while loading.
- Every save writes everything. Fine for hundreds of bookmarks; one reason a database takes over in
  Chapter 15.

### src/stash/fetch.lua (new)

```lua
-- Fetching pages. For now only file:// URLs, read with the io library.

local fs = require("stash.fs")

local M = {}

-- "file:///tmp/my%20page.html" -> "/tmp/my page.html"
local function file_path(url)
  local path = url:match("^file://(/.*)$")
  if path == nil then
    return nil
  end
  return (path:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

function M.can_fetch(url)
  return file_path(url) ~= nil
end

-- Returns the body of the page, or nil and an error message.
function M.get(url)
  local path = file_path(url)
  if path == nil then
    return nil, "cannot fetch " .. url
  end
  return fs.read_file(path)
end

return M
```

URLs write spaces and some other characters as `%` plus two hex digits (`%20` is a space). `gsub`
with a function decodes them: `tonumber(hex, 16)` reads hex, `string.char` makes the byte. The extra
parentheses around `gsub` drop its second result, the count.

### src/stash/html.lua (new)

```lua
-- Just enough HTML handling for stash: Lua patterns, not a real parser.

local M = {}

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }

-- Replaces &amp; &lt; ... and numeric &#65; / &#x41; references (ASCII only).
function M.decode_entities(s)
  return (s:gsub("&(#?)([xX]?)(%w+);", function(hash, x, name)
    if hash == "" then
      return ENTITIES[name]                  -- nil keeps the original text
    end
    local code = tonumber(name, x == "" and 10 or 16)
    if code and code < 128 then
      return string.char(code)
    end
  end))
end

-- Collapses runs of whitespace into one space and trims the ends.
function M.squeeze(s)
  return (s:gsub("%s+", " "):match("^ ?(.-) ?$"))
end

-- Lua patterns have no "ignore case" flag; [tT][iI]... does the job.
local function nocase(word)
  return (word:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end))
end

local TITLE = "<" .. nocase("title") .. "[^>]*>(.-)</" .. nocase("title") .. "%s*>"

-- The text of the <title> element, or nil.
function M.title(html)
  local title = html:match(TITLE)
  if title == nil then
    return nil
  end
  title = M.squeeze(M.decode_entities(title))
  if title == "" then
    return nil
  end
  return title
end

return M
```

Patterns can't parse HTML properly, but "the text between `<title>` and `</title>`" is simple enough.

- `nocase("title")` builds `[tT][iI][tT][lL][eE]`, since patterns have no case-insensitive flag.
- `[^>]*` skips attributes such as `<title lang="en">`. `(.-)` is the shortest match, so it stops at
  the first `</title>`.
- `decode_entities` turns `&amp;` into `&` and numeric references such as `&#65;` into bytes.
  Returning `nil` from the `gsub` function keeps the original text, so unknown entities and non-ASCII
  codes stay as they are.
- `squeeze` turns the line break in the `lua.html` title into one space.

### src/stash/json.lua (new)

Other programs understand JSON, so `export` writes it. Lua has no built-in JSON library, but an
encoder is short. Strings and tables need care.

```lua
-- A small JSON encoder.
--
-- Lua has one structure, JSON has two: a table becomes a JSON array when
-- its keys are exactly 1..n, otherwise an object. An empty table is
-- written as [] (we cannot tell which one was meant).

local M = {}

local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function escape_char(c)
  return ESCAPES[c] or ("\\u%04x"):format(c:byte())
end

local function encode_string(s)
  -- %c matches control characters. Bytes >= 128 (UTF-8) pass unchanged.
  return '"' .. s:gsub('[%c"\\]', escape_char) .. '"'
end

local function is_array(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then
      return false
    end
  end
  return true
end

local encode

local function encode_table(t, out)
  if is_array(t) then
    out[#out + 1] = "["
    for i, v in ipairs(t) do
      if i > 1 then out[#out + 1] = "," end
      encode(v, out)
    end
    out[#out + 1] = "]"
    return
  end
  -- Objects: keys sorted, so equal data always gives equal text.
  local keys = {}
  for k in pairs(t) do
    if type(k) ~= "string" then
      error("JSON object keys must be strings, got " .. type(k))
    end
    keys[#keys + 1] = k
  end
  table.sort(keys)
  out[#out + 1] = "{"
  for i, k in ipairs(keys) do
    if i > 1 then out[#out + 1] = "," end
    out[#out + 1] = encode_string(k)
    out[#out + 1] = ":"
    encode(t[k], out)
  end
  out[#out + 1] = "}"
end

function encode(value, out)
  local kind = type(value)
  if kind == "string" then
    out[#out + 1] = encode_string(value)
  elseif kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("JSON cannot represent " .. tostring(value))
    end
    if value % 1 == 0 and math.abs(value) < 2^53 then
      out[#out + 1] = ("%d"):format(value)
    else
      out[#out + 1] = ("%.17g"):format(value)
    end
  elseif kind == "boolean" then
    out[#out + 1] = tostring(value)
  elseif kind == "nil" then
    out[#out + 1] = "null"
  elseif kind == "table" then
    encode_table(value, out)
  else
    error("JSON cannot represent a " .. kind)
  end
end

function M.encode(value)
  local out = {}
  encode(value, out)
  return table.concat(out)
end

-- Streams a JSON array, one element per line, pulling the elements from
-- an iterator and handing each finished line to emit(line). Nothing but
-- the current element is kept in memory. Returns the number of elements.
function M.write_array(it, emit)
  emit("[")
  local count = 0
  local pending                              -- held back: is it the last one?
  for value in it do
    if pending then
      emit("  " .. pending .. ",")
    end
    pending = M.encode(value)
    count = count + 1
  end
  if pending then
    emit("  " .. pending)
  end
  emit("]")
  return count
end

return M
```

- **Escaping.** JSON strings must escape `"`, `\` and every control character (bytes 0–31).
  `[%c"\\]` matches exactly those. Common ones get short forms like `\n`, the rest `\u00XX`. Bytes 128+
  pass unchanged, so UTF-8 text survives.
- **Array or object?** `is_array` counts all keys (`n`), then checks that `1..n` are all present. If
  so, the keys are exactly `1..n`: an array. Anything else is an object, which needs string keys.
  `{ [1] = "a", [3] = "c" }` is neither: an error.
- **The empty table** is both an empty array and an empty object. We write `[]`, since in `stash` it's
  always an empty tag list.
- **Numbers.** Whole numbers below 2^53 use `%d`, so `1767225600` doesn't become `1.767225600e+09`.
  Others use `%.17g`. JSON has no `NaN` or infinity, so those are errors (`value ~= value` is true
  only for NaN).
- **Sorted keys** again, so `export` output never changes between runs.
- **`write_array`** streams one line per element from an iterator. JSON forbids a comma after the last
  element, and we only know it's the last when the iterator ends. So each encoded element waits in
  `pending` until the next arrives.

### src/stash/commands.lua

Require the new modules at the top:

```lua
local Entry = require("stash.entry")
local errors = require("stash.errors")
local fetch = require("stash.fetch")
local fs = require("stash.fs")
local html = require("stash.html")
local json = require("stash.json")
local util = require("stash.util")
```

`format_row` gets a tags column and a date:

```lua
local function format_row(entry)
  return ("%3d  %-36s  %-16s  %s"):format(entry.id, util.truncate(entry.title, 36),
                                         util.truncate(entry:tag_string(), 16),
                                         util.date(entry.created))
end
```

`add` reads the page, if it can, before creating the entry. Replace the `ctx.store:add` line with:

```lua
    -- Read the page when we can, for its title.
    local title
    if fetch.can_fetch(url) then
      local body, err = fetch.get(url)
      if body == nil then
        errors.fail("cannot fetch %s: %s", url, err)
      end
      title = html.title(body)
    end
    local entry = ctx.store:add(Entry.new({ url = url, title = title, tags = tags,
                                            note = opts.note, created = util.now() }))
```

If the page can't be read, `errors.fail` stops here and nothing is saved. The fetch error already
has the path and reason (`io.open`'s message).

In `show`, add a line after `tags:`:

```lua
    ctx.out(("%-6s %s"):format("added:", util.datetime(entry.created)))
```

And the new command, before `help`:

```lua
command "export" {
  usage = "export [FILE]",
  help = "write all bookmarks as JSON",
  run = function(ctx, opts)
    -- A pipeline: entries -> plain records -> JSON lines -> output.
    local records = coroutine.wrap(function()
      for entry in ctx.store:entries() do
        coroutine.yield(entry:record())
      end
    end)
    local path = opts[1]
    if path == nil or path == "-" then
      json.write_array(records, ctx.out)
      return
    end
    local ok, result = fs.with_file(path, "w", function(file)
      return json.write_array(records, function(line) file:write(line, "\n") end)
    end)
    if not ok then
      errors.fail("cannot export: %s", result)
    end
    ctx.out(("exported %d entries to %s"):format(result, path))
  end,
}
```

`export` is a pipeline: entries → records (a `coroutine.wrap` generator from
[Chapter 11](11-coroutines.md)) → JSON lines → output. With no file or `-`, lines go to `ctx.out`.
With a file, `with_file` closes it even if encoding fails. `write_array`'s count comes back through
`with_file` as `result`.

### src/stash/main.lua

Replace the two `require` lines for `MemoryStore` and `sample` with:

```lua
local FileStore = require("stash.filestore")
```

Delete the two "(covered in Chapter 12)" comments. Then open the store in `dispatch`, after the
options are parsed:

```lua
  local store, serr = FileStore.open(M.home() .. "/entries.lua")
  if store == nil then
    errors.fail("%s", serr)
  end
  local ctx = {
    store = store,
    config = settings,
    out = print,
  }
```

The store opens after argument checks, so a usage error never touches the disk.

Delete `src/stash/sample.lua`.

### Tests

The runner gives tests a scratch directory. In `test/run.lua`, register the new files and add `TMP`
after `FILES`:

```lua
local FILES = {
  "util_test", "cli_test", "entry_test", "iter_test", "memstore_test", "config_test",
  "commands_test", "json_test", "html_test", "filestore_test", "e2e_test",
}

-- Scratch space. os.tmpname() would give us a file, not a directory, so
-- the runner keeps its own directory and deletes it at the end.
local TMP = ".test-tmp"
os.execute("rm -rf " .. TMP .. " && mkdir " .. TMP)
```

Add a `tmpdir` assertion next to the others, before `local passed, failed = 0, 0`:

```lua
-- Returns a fresh, empty directory for one test.
function assertions.tmpdir(name)
  local path = TMP .. "/" .. name
  assert(os.execute("rm -rf " .. path .. " && mkdir " .. path) == 0)
  return path
end
```

Remove it at the end, just before the summary line:

```lua
os.execute("rm -rf " .. TMP)
print(("\n%d passed, %d failed"):format(passed, failed))
```

`os.execute` returns 0 for success in LuaJIT, so `assert(... == 0)` catches a failed `mkdir`.
`.test-tmp` is a fixed name inside the project: tests can't collide with other files, and a crashed
run leaves its files where you can inspect them.

`test/commands_test.lua` needs dates. Add a fixed time to the sample store:

```lua
local NOW = 1767225600                       -- 2026-01-01 00:00 UTC

local function sample_store()
  return MemoryStore.new({
    { url = "https://www.lua.org/", title = "Lua", tags = { "lua" }, created = NOW },
    { url = "https://luajit.org/", title = "LuaJIT", tags = { "lua", "jit" }, note = "fast",
      created = NOW },
  })
end
```

The `list` test gains the tags and date columns; the `show` test gains the `added:` line:

```lua
test("list prints one aligned row per entry", function()
  eq(run(sample_store(), { "list" }), table.concat({
    "  1  Lua                                   lua               2026-01-01",
    "  2  LuaJIT                                jit,lua           2026-01-01",
  }, "\n"))
end)
```

```lua
test("show prints the fields", function()
  eq(run(sample_store(), { "show", "2" }), [[
id:    2
title: LuaJIT
url:   https://luajit.org/
tags:  jit, lua
added: 2026-01-01 00:00 UTC
note:  fast]])
end)
```

Add the export test at the end:

```lua
test("export writes a JSON array", function()
  eq(run(sample_store(), { "export" }), table.concat({
    "[",
    [[  {"created":1767225600,"id":1,"note":"","tags":["lua"],"title":"Lua","url":"https://www.lua.org/"},]],
    [[  {"created":1767225600,"id":2,"note":"fast","tags":["jit","lua"],"title":"LuaJIT","url":"https://luajit.org/"}]],
    "]",
  }, "\n"))
end)
```

`test/json_test.lua` (new):

```lua
local json = require("stash.json")
local iter = require("stash.iter")

test("scalars", function()
  eq(json.encode(42), "42")
  eq(json.encode(-0.5), "-0.5")
  eq(json.encode(true), "true")
  eq(json.encode(nil), "null")
end)

test("strings are escaped", function()
  eq(json.encode('say "hi"\n'), [["say \"hi\"\n"]])
  eq(json.encode("tab\tbell\7"), [["tab\tbell\u0007"]])
  eq(json.encode("back\\slash"), [["back\\slash"]])
end)

test("arrays and objects", function()
  eq(json.encode({ 1, 2, 3 }), "[1,2,3]")
  eq(json.encode({}), "[]")
  eq(json.encode({ b = 1, a = { "x" } }), [[{"a":["x"],"b":1}]])
end)

test("tables with holes are not arrays", function()
  raises(function() json.encode({ [1] = "a", [3] = "c" }) end, "keys must be strings")
end)

test("values JSON cannot hold are errors", function()
  raises(function() json.encode(math.huge) end, "cannot represent inf")
  raises(function() json.encode(print) end, "cannot represent a function")
end)

test("write_array streams one element per line", function()
  local lines = {}
  local n = json.write_array(iter.values({ 1, { a = 2 } }), function(l) lines[#lines + 1] = l end)
  eq(n, 2)
  same(lines, { "[", "  1,", [[  {"a":2}]], "]" })
  lines = {}
  json.write_array(iter.values({}), function(l) lines[#lines + 1] = l end)
  same(lines, { "[", "]" })
end)
```

`test/html_test.lua` (new):

```lua
local html = require("stash.html")

test("title is found in any case and squeezed", function()
  eq(html.title("<html><TITLE>\n  Hello\n  World </Title>"), "Hello World")
  eq(html.title('<title lang="en">Hi</title>'), "Hi")
end)

test("missing or empty titles give nil", function()
  eq(html.title("<p>no title</p>"), nil)
  eq(html.title("<title>  </title>"), nil)
end)

test("entities are decoded", function()
  eq(html.decode_entities("a &amp; b &lt;c&gt; &#65;&#x42;"), "a & b <c> AB")
  eq(html.decode_entities("&bogus; &#233;"), "&bogus; &#233;")
end)

test("fixture pages", function()
  local fs = require("stash.fs")
  eq(html.title(assert(fs.read_file("test/fixtures/lua.html"))), "The Programming Language Lua")
  eq(html.title(assert(fs.read_file("test/fixtures/luajit.html"))),
     "LuaJIT: a Just-In-Time Compiler & FFI")
end)
```

`test/filestore_test.lua` (new). The first test is a round trip: serialize, load, compare.

```lua
local Entry = require("stash.entry")
local FileStore = require("stash.filestore")
local serialize = require("stash.serialize")

test("serialize output loads back as the same data", function()
  local data = { 1, "two", { three = 3 }, flag = true, ["odd key"] = "x\n\"y\"" }
  local text = serialize.serialize(data)
  local loaded = loadstring("return " .. text)()
  same(loaded, data)
end)

test("serialize refuses functions", function()
  raises(function() serialize.serialize({ f = print }) end, "cannot serialize a function")
end)

test("a missing file is an empty store", function()
  local store = assert(FileStore.open(tmpdir("fs-empty") .. "/entries.lua"))
  eq(#store:list({}), 0)
end)

test("entries survive a reopen, ids included", function()
  local path = tmpdir("fs-reopen") .. "/sub/dir/entries.lua"
  local store = assert(FileStore.open(path))
  store:add(Entry.new({ url = "https://a.org/", tags = { "x" }, created = 5 }))
  store:add(Entry.new({ url = "https://b.org/", created = 6 }))
  store:remove(1)

  local again = assert(FileStore.open(path))
  eq(again:get(1), nil)
  eq(again:get(2).url, "https://b.org/")
  eq(again:get(2).created, 6)
  eq(again:add(Entry.new({ url = "https://c.org/" })).id, 3)
end)

test("a broken file is reported", function()
  local path = tmpdir("fs-broken") .. "/entries.lua"
  local file = assert(io.open(path, "w"))
  file:write("return {")
  file:close()
  local store, err = FileStore.open(path)
  eq(store, nil)
  ok(err:find("entries.lua:1:", 1, true), err)
end)
```

`test/e2e_test.lua` (new) runs the real `./stash` through `io.popen`, with the `$?` trick. `2>&1`
sends stderr into the pipe too, so error messages can be checked.

```lua
-- End-to-end tests: run the real program in a shell and check its output
-- and exit code.

local HOME = tmpdir("e2e")
local PAGES = "file://" .. os.getenv("PWD") .. "/test/fixtures"

-- Runs `stash ARGS` and returns its output (stdout and stderr) and exit code.
-- io.popen's close() does not report the exit code in LuaJIT, so the
-- shell prints it after the output.
local function stash(args)
  local command = ("STASH_HOME=%s STASH_NOW=1767225600 ./stash %s 2>&1; echo \"[exit $?]\"")
                  :format(HOME, args)
  local pipe = assert(io.popen(command))
  local output = pipe:read("*a")
  pipe:close()
  local text, code = output:match("^(.-)%[exit (%d+)%]\n$")
  return text, tonumber(code)
end

test("add, list, rm round trip", function()
  eq(stash("add " .. PAGES .. "/lua.html -t lua"), "added #1 The Programming Language Lua\n")
  eq(stash("add https://example.com/ -t web"), "added #2 example.com\n")
  eq(stash("list -t lua"),
     "  1  The Programming Language Lua          lua               2026-01-01\n")
  eq(stash("rm 1"), "removed #1 The Programming Language Lua\n")
  local text, code = stash("show 1")
  eq(text, "stash: no entry with id 1\n")
  eq(code, 1)
end)

test("usage errors exit with 2", function()
  local text, code = stash("list --limit")
  eq(code, 2)
  ok(text:find("usage: stash list", 1, true), text)
end)

test("a missing page is an error and nothing is saved", function()
  local _, code = stash("add file:///no/such/page.html")
  eq(code, 2)
  eq(select(2, stash("show 3")), 1)
end)
```

The fixtures are three small pages in `test/fixtures/`. `lua.html` has a line break in its title;
`luajit.html` has an `&amp;`:

```html
<!DOCTYPE html>
<html>
<head>
  <title>The Programming Language
    Lua</title>
</head>
<body>
  <h1>Lua</h1>
  <p>Lua is a small, fast scripting language built to be embedded.
  Its only data structure is the table.</p>
</body>
</html>
```

```html
<!DOCTYPE html>
<html>
<head><title>LuaJIT: a Just-In-Time Compiler &amp; FFI</title></head>
<body>
  <p>LuaJIT runs Lua code very fast with a tracing JIT compiler.</p>
  <p>Its FFI library calls C functions and uses C data structures
  from plain Lua code.</p>
</body>
</html>
```

```html
<!DOCTYPE html>
<html>
<head><title>SQLite FTS5 Extension</title></head>
<body>
  <p>FTS5 is an SQLite virtual table module that provides
  full-text search.</p>
  <script>console.log("not searchable");</script>
</body>
</html>
```

### Checkpoint

Run from the project root. `demo` is a fresh data directory; `STASH_NOW` fixes the date. `$PWD`
makes the `file://` URLs absolute: where the output shows `/path/to/project/ch12`, you'll see your
own path.

```console
$ luajit test/run.lua
util_test        3 tests, 0 failed
cli_test         5 tests, 0 failed
entry_test       5 tests, 0 failed
iter_test        4 tests, 0 failed
memstore_test    7 tests, 0 failed
config_test      3 tests, 0 failed
commands_test    5 tests, 0 failed
json_test        6 tests, 0 failed
html_test        4 tests, 0 failed
filestore_test   5 tests, 0 failed
e2e_test         3 tests, 0 failed

50 passed, 0 failed
$ export STASH_HOME=demo STASH_NOW=1767225600
$ PAGES=file://$PWD/test/fixtures
$ ./stash add $PAGES/lua.html -t lua,lang -n "official site"
added #1 The Programming Language Lua
$ ./stash add $PAGES/luajit.html -t lua,jit
added #2 LuaJIT: a Just-In-Time Compiler & FFI
$ ./stash add https://sqlite.org/fts5.html -t db,search
added #3 sqlite.org/fts5.html
$ ./stash list
  1  The Programming Language Lua          lang,lua          2026-01-01
  2  LuaJIT: a Just-In-Time Compiler &...  jit,lua           2026-01-01
  3  sqlite.org/fts5.html                  db,search         2026-01-01
$ ./stash show 1
id:    1
title: The Programming Language Lua
url:   file:///path/to/project/ch12/test/fixtures/lua.html
tags:  lang, lua
added: 2026-01-01 00:00 UTC
note:  official site
$ cat demo/entries.lua | head -14
return {
  entries = {
    {
      created = 1767225600,
      id = 1,
      note = "official site",
      tags = {
        "lang",
        "lua",
      },
      title = "The Programming Language Lua",
      url = "file:///path/to/project/ch12/test/fixtures/lua.html",
    },
    {
$ ./stash export | cut -c1-60
[
  {"created":1767225600,"id":1,"note":"official site","tags"
  {"created":1767225600,"id":2,"note":"","tags":["jit","lua"
  {"created":1767225600,"id":3,"note":"","tags":["db","searc
]
$ ./stash export demo/stash.json
exported 3 entries to demo/stash.json
$ ./stash rm 3
removed #3 sqlite.org/fts5.html
$ ./stash list
  1  The Programming Language Lua          lang,lua          2026-01-01
  2  LuaJIT: a Just-In-Time Compiler &...  jit,lua           2026-01-01
$ ./stash add $PAGES/missing.html; echo "exit $?"
stash: cannot fetch file:///path/to/project/ch12/test/fixtures/missing.html: /path/to/project/ch12/test/fixtures/missing.html: No such file or directory
exit 2
```

Look at `demo/entries.lua` after each command: plain Lua you can read and even edit by hand.
`https://sqlite.org/fts5.html` was saved without a fetch, so its title comes from the URL. Run
`rm -rf demo` when you're done.

The complete project at this point is in `project/ch12/`.

## Summary

- `io.open(path, mode)` returns a handle or `nil, message, errno`. Modes are C's `fopen` modes; add
  `b` for exact bytes.
- `f:read` formats: `"*l"`, `"*L"`, `"*n"`, `"*a"`, or a byte count. At the end, `"*a"` gives `""`,
  the others `nil`.
- `io.lines(path)` and `f:lines()` loop over lines. `f:seek(whence, offset)` moves and reports the
  position. Close what you open.
- `io.stdout`/`io.write` for output, `io.stderr` for messages. `io.popen` runs a command with a pipe;
  in LuaJIT, get exit codes via `echo $?`.
- `os.time()`: seconds since 1970 (UTC). `os.date("!...")` for UTC, `os.date("*t")` for a table,
  `os.clock()` for CPU time.
- `os.getenv`, `os.rename`, `os.remove`, `os.execute` (0 = success in LuaJIT), `os.exit(code)`.
- Persist tables as Lua code with `%q` and `%.17g`; load with `loadfile` and an empty environment.
  Write atomically: temporary file in the same directory, then `os.rename`.
- JSON: escape `"`, `\` and control characters. A table is an array if its keys are exactly `1..n`.
- `stash` saves to `entries.lua`, reads titles from `file://` pages, and exports JSON.

## Exercises

1. Write `wc(path)` that returns the number of lines, words and bytes in a file, like the
   `wc` command. Read it line by line, not all at once.

<details><summary>Solution</summary>

`"*L"` keeps each newline, so `#line` counts every byte.

```lua
local function wc(path)
  local lines, words, bytes = 0, 0, 0
  for line in io.lines(path, "*L") do
    lines = lines + 1
    bytes = bytes + #line
    for _ in line:gmatch("%S+") do words = words + 1 end
  end
  return lines, words, bytes
end

local f = assert(io.open("sample.txt", "w"))
f:write("one two\nthree\n\nfour five six\n")
f:close()
print(wc("sample.txt"))
os.remove("sample.txt")
```

```console
4	6	29
```

`wc` prints the same numbers for this text. One difference: `wc` counts newline characters, so a last
line without `"\n"` doesn't count there, but does here.

</details>

2. Write `tail(path, n)` that returns the last `n` lines of a file as an array. It should not read
   the whole file: seek near the end and read backwards in blocks until you have enough lines.

<details><summary>Solution</summary>

```lua
-- Returns the last n lines of a file. Reads backwards in blocks, so a
-- huge file costs no more than a small one.
local function tail(path, n, block)
  block = block or 4096
  local f = assert(io.open(path, "rb"))
  local pos = f:seek("end")
  local data = ""
  -- n lines need n + 1 newlines in view (or the start of the file).
  while pos > 0 and select(2, data:gsub("\n", "")) <= n do
    local start = math.max(0, pos - block)
    f:seek("set", start)
    data = f:read(pos - start) .. data
    pos = start
  end
  f:close()
  local lines = {}
  for line in data:gmatch("[^\n]*\n") do
    lines[#lines + 1] = line:sub(1, -2)
  end
  if pos > 0 then
    table.remove(lines, 1)                   -- probably cut in half
  end
  local result = {}
  for i = math.max(1, #lines - n + 1), #lines do
    result[#result + 1] = lines[i]
  end
  return result
end

local f = assert(io.open("big.txt", "w"))
for i = 1, 10000 do f:write("line ", i, "\n") end
f:close()
print(table.concat(tail("big.txt", 3), " | "))
print(table.concat(tail("big.txt", 3, 7), " | "))
print(#tail("big.txt", 20000))
os.remove("big.txt")
```

```console
line 9998 | line 9999 | line 10000
line 9998 | line 9999 | line 10000
10000
```

The 7-byte block in the second call proves that lines cut across blocks come out whole. The loop
needs `n + 1` newlines in view because the text before the first may be part of a longer line.

</details>

3. Add `html.text(body)` to `stash.html`. It returns the visible text of a page: tags removed,
   `<script>`, `<style>` and `<!-- comments -->` removed with their contents, entities decoded and
   whitespace squeezed. For `test/fixtures/sqlite.html` it should return
   `"SQLite FTS5 Extension FTS5 is an SQLite virtual table module that provides full-text search."`

<details><summary>Solution</summary>

Remove the parts with content first, then all other tags. Each removal leaves a space so words on
both sides don't run together; `squeeze` cleans up.

```lua
-- The visible text of a page: no tags, scripts, styles or comments.
function M.text(html)
  html = html:gsub("<!%-%-.-%-%->", " ")
  for _, name in ipairs({ "script", "style" }) do
    html = html:gsub("<" .. nocase(name) .. "[^>]*>.-</" .. nocase(name) .. "%s*>", " ")
  end
  html = html:gsub("<[^>]*>", " ")
  return M.squeeze(M.decode_entities(html))
end
```

A test for `test/html_test.lua`:

```lua
test("text drops tags, scripts and comments", function()
  eq(html.text("<p>a &amp; <b>b</b></p><!-- x --><SCRIPT>var s='<p>';</script> c"), "a & b c")
  eq(html.text(assert(require("stash.fs").read_file("test/fixtures/sqlite.html"))),
     "SQLite FTS5 Extension FTS5 is an SQLite virtual table module that provides full-text search.")
end)
```

`-` is a pattern character, so comment markers are written `%-%-`. The `'<p>'` inside the script
can't confuse the tag pattern, because scripts go first. `html_test` now has 5 tests.

</details>

4. `fs.write_atomic` writes to `path .. ".tmp"`. Why not use `os.tmpname()` for the temporary file?
   Give two reasons.

<details><summary>Solution</summary>

1. `rename` works only within one file system. `os.tmpname()` gives a name in `/tmp`, often a
   separate file system (on many Linux systems a RAM disk, `tmpfs`). Renaming from there into
   `~/.local/share/stash` fails with `EXDEV` ("Invalid cross-device link"). A file in the target's
   directory is always on the same file system.
2. After a crash between writing and renaming, the leftover `entries.lua.tmp` sits next to the data,
   where you can find it. A file in `/tmp` would be lost or forgotten.

</details>

5. `serialize.serialize` loops forever on a table that contains itself, until the stack overflows.
   Make it raise `"cannot serialize a cycle"` instead. A table that appears twice but not inside
   itself, such as `{ a = shared, b = shared }`, must still work (it is written twice).

<details><summary>Solution</summary>

Pass a `seen` set down the recursion. Mark a table on entry, unmark it on exit. `seen` then holds only
the tables on the current path: a repeat means a cycle, while a table shared by two branches is fine.

```lua
local function write(value, indent, out, seen)
  local kind = type(value)
  if kind == "string" then
    out[#out + 1] = ("%q"):format(value)
  elseif kind == "number" then
    out[#out + 1] = ("%.17g"):format(value)  -- 17 digits: reads back exactly
  elseif kind == "boolean" then
    out[#out + 1] = tostring(value)
  elseif kind == "table" then
    if seen[value] then
      error("cannot serialize a cycle")
    end
    seen[value] = true
    -- ... the rest as before, with `seen` passed to every write(...) call ...
    out[#out + 1] = indent .. "}"
    seen[value] = nil
  else
    error("cannot serialize a " .. kind)
  end
end

function M.serialize(value)
  local out = {}
  write(value, "", out, {})
  return table.concat(out)
end
```

A test for `test/filestore_test.lua`:

```lua
test("cycles are refused, shared tables are fine", function()
  local t = {}
  t.self = t
  raises(function() serialize.serialize(t) end, "cannot serialize a cycle")
  local shared = { 1 }
  local text = serialize.serialize({ a = shared, b = shared })
  same(loadstring("return " .. text)(), { a = { 1 }, b = { 1 } })
end)
```

After loading, `a` and `b` are separate tables: the serializer writes values, not identity.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-12--io-and-the-os)
