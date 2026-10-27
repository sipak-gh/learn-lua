# Appendix A — Cheat Sheet

Lua 5.1 syntax plus the LuaJIT 2.1 extensions, on one page. Below, `expr --> result` means
`print(expr)` prints `result`; several values are separated by two spaces (print uses tabs).
Chapter links lead to the full story. The FFI has its own page:
[Appendix B](appendix-b-ffi-reference.md).

## Running code

| Command | Does |
|---------|------|
| `luajit` | interactive prompt (REPL) |
| `luajit file.lua a b` | run a file; `arg[0]` is `"file.lua"`, `arg[1]` is `"a"`, `...` holds `"a", "b"` |
| `luajit -e 'print(1)'` | run a string |
| `luajit -l mod file.lua` | `require("mod")` first |
| `luajit -i file.lua` | run the file, then enter the prompt |
| `luajit -` | read the program from stdin |
| `luajit -v` | print the version |
| `luajit -b in.lua out.o` | compile to bytecode ([Chapter 20](20-embedding-luajit.md)) |

A first line starting with `#` is skipped, so `#!/usr/bin/env luajit` works.

## Lexical basics

```lua
-- a line comment
--[[ a block
     comment ]]
--[==[ a block comment that may contain ]] ]==]

local s1 = "double quotes"
local s2 = 'single quotes'
local s3 = [[long string: no escapes,
and a newline right after [[ is dropped]]
local s4 = [==[may contain ]] ]==]
```

Names are letters, digits and `_`, not starting with a digit. Case matters. Names like `_VERSION`
(underscore plus capitals) are reserved for Lua itself.

The 22 keywords:

```text
and  break  do  else  elseif  end  false  for  function  goto  if  in
local  nil  not  or  repeat  return  then  true  until  while
```

`goto` is a keyword in LuaJIT and Lua 5.2+, an ordinary name in PUC Lua 5.1.

String escapes:

| Escape | Means |
|--------|-------|
| `\n` `\t` `\r` `\\` `\"` `\'` | newline, tab, carriage return, backslash, quotes |
| `\a` `\b` `\f` `\v` | bell, backspace, form feed, vertical tab |
| `\ddd` | byte with decimal value `ddd` (up to 3 digits): `"\65"` is `"A"` |
| `\xhh` | byte with hex value `hh`: `"\x41"` is `"A"` (LuaJIT, 5.2+) |
| `\u{hhhh}` | the UTF-8 bytes of a code point: `"\u{e9}"` is `"é"` (LuaJIT, 5.3+) |
| `\z` | skip the following spaces and newlines (LuaJIT, 5.2+) |
| `\` + newline | a newline |

Number literals:

```lua
42, 3.14, 1e3, 2.5e-3   --> 42  3.14  1000  0.0025
0xff, 0x1p4             --> 255  16
1LL, 2ULL, 1i           --> 1LL  2ULL  0+1i
```

Plain numbers are doubles, exact for integers up to 2^53. `1LL` (int64), `2ULL` (uint64) and `1i`
(complex) are LuaJIT FFI literals that make cdata ([Chapter 14](14-c-data.md)).

## Types and truth

```lua
type(nil), type(true), type(1), type("s")      --> nil  boolean  number  string
type({}), type(print), type(io.stdout)         --> table  function  userdata
type(coroutine.create(print)), type(1LL)       --> thread  cdata
```

Only `nil` and `false` are false. `0` and `""` are true ([Chapter 2](02-values-and-types.md)).

## Operators

From lowest to highest precedence:

| Level | Operators | Notes |
|-------|-----------|-------|
| 1 | `or` | returns the first true operand, or the last one |
| 2 | `and` | returns the first false operand, or the last one |
| 3 | `<` `>` `<=` `>=` `~=` `==` | `~=` means "not equal" |
| 4 | `..` | concatenation, right associative |
| 5 | `+` `-` | |
| 6 | `*` `/` `%` | `/` always gives a float result; `%` takes the divisor's sign |
| 7 | `not` `#` `-` (unary) | `#` is length |
| 8 | `^` | power, right associative; binds tighter than unary minus |

```lua
7 / 2, math.floor(7 / 2), 7 % 3, -7 % 3   --> 3.5  3  1  2
2 ^ 10, -2 ^ 2, 2 ^ 3 ^ 2                 --> 1024  -4  512
"10" + 5, 1 .. 2, "a" .. "b" .. "c"       --> 15  12  abc
10 == "10", 1 == 1.0, 0.1 + 0.2 == 0.3    --> false  true  false
nil or "default", false and 1, 1 and 2    --> default  false  2
not nil, not 0                            --> true  false
#"héllo", #{ 10, 20, 30 }                 --> 6  3
```

- `==` never converts types. `<` between a number and a string is an error:
  `attempt to compare number with string`.
- There is no `//`, `+=` or `++`, and no bitwise operators: use `math.floor(a / b)`, `x = x + 1`
  and the `bit` library. (LuaJIT 2.1 builds from July 2026 on accept bitwise operators, `+=` and
  more, but not `//`; see [Appendix C](appendix-c-lua-versions.md).)
- `a and b or c` works like `a ? b : c` only when `b` is never `false` or `nil`.
- `#` counts bytes in a string. On a table it is reliable only for a sequence (no holes).

## Statements

```lua
local a, b = 1, 2             -- extra values are dropped, missing ones are nil
a, b = b, a                   -- swap

if a > b then
  print("bigger")
elseif a < b then
  print("smaller")
else
  print("same")
end

while a > 0 do a = a - 1 end

repeat
  local done = true
until done                    -- the body's locals are visible here

for i = 1, 3 do end           -- 1, 2, 3 (limit included)
for i = 10, 1, -2 do end      -- 10, 8, 6, 4, 2
for i, v in ipairs({ "x", "y" }) do end   -- 1..n, stops at the first nil
for k, v in pairs({ k = 1 }) do end       -- every key, in no fixed order

do
  local tmp = 1               -- a block just for scope
end

for i = 1, 3 do
  if i == 2 then goto continue end
  print(i)
  ::continue::
end
```

- The `for` variable is a fresh local in each iteration; start, limit and step are evaluated
  once.
- `break` leaves the innermost loop. `return` must be the last statement in its block; write
  `do return end` to return from the middle.
- See [Chapter 3](03-control-flow.md).

## Functions

```lua
local function add(a, b) return a + b end
local square = function(x) return x * x end

local M = {}
function M.hello(name) return "hi " .. name end   -- M.hello = function(name) ... end
function M:greet() return self end                -- M.greet = function(self) ... end
-- M:greet() is short for M.greet(M)

print "one string argument"                       -- no parentheses needed
print(type { "one table argument" })
```

```lua
select("#", nil, nil), select(2, "a", "b", "c")   --> 2  b  c
select(-1, "a", "b", "c")                         --> c
(function(...) return ... end)(1, 2)              --> 1  2
(function() return 1, 2 end)(), "x"               --> 1  x
((function() return 1, 2 end)())                  --> 1
unpack({ 1, 2, 3 }), unpack({ 1, 2, 3 }, 2)       --> 1  2  3
```

- A call expands to all its results only as the last item in a list. Elsewhere, and inside
  extra parentheses, it gives only its first result.
- `...` holds the variable arguments. `{ ... }` packs them (a `nil` makes a hole), and
  `select("#", ...)` counts them, `nil`s included.
- Functions are closures: they capture local variables, not values ([Chapter 4](04-functions.md)).

## Tables

```lua
local t = { 10, 20, 30, x = 1, ["two words"] = 2, [100] = 3 }
t.x, t["x"], t["two words"], t[100]       --> 1  1  2  3
t[#t + 1] = 40                            -- append
table.insert(t, 50)                       -- append
table.insert(t, 1, 0)                     -- insert at the front
table.remove(t), table.remove(t, 1), #t   --> 50  0  4
table.concat(t, ",")                      --> 10,20,30,40
```

- Arrays start at 1. Any value except `nil` and NaN can be a key. `1` and `1.0` are the same key;
  `1` and `"1"` are not.
- Setting a field to `nil` removes it. Test a field with `t.k ~= nil` when `false` is a valid value.
- `pairs` order is unspecified; to sort keys, collect them and call `table.sort`.
- See [Chapter 5](05-tables.md).

## Metatables

```lua
local V = {}
V.__index = V
V.__add = function(a, b) return setmetatable({ x = a.x + b.x }, V) end
V.__tostring = function(v) return "V(" .. v.x .. ")" end
function V.new(x) return setmetatable({ x = x }, V) end
function V:double() return V.new(self.x * 2) end

tostring(V.new(1) + V.new(2)), tostring(V.new(5):double())   --> V(3)  V(10)
```

| Key | Used for |
|-----|----------|
| `__index` | reading a missing key: a table to look in, or `function(t, k)` |
| `__newindex` | writing a missing key: a table, or `function(t, k, v)` |
| `__call` | calling the value like a function: `function(self, ...)` |
| `__tostring` | `tostring(v)` and `print(v)` |
| `__add` `__sub` `__mul` `__div` `__mod` `__pow` `__unm` `__concat` | `+ - * / % ^`, unary `-`, `..` |
| `__eq` `__lt` `__le` | `==`, `<`, `<=`; `a > b` runs `b < a` |
| `__len` | `#v`; userdata and cdata only in LuaJIT (ignored on tables) |
| `__gc` | finalizer; userdata and cdata only in LuaJIT (ignored on tables) |
| `__mode` | weak table: `"k"`, `"v"` or `"kv"` |
| `__metatable` | value returned by `getmetatable`; also blocks `setmetatable` |

`rawget`, `rawset` and `rawequal` skip the metamethods ([Chapter 7](07-metatables-and-objects.md)).

## Basic functions

| Function | Does |
|----------|------|
| `print(...)` | write values to stdout, tab separated |
| `type(v)` | type name as a string |
| `tostring(v)`, `tonumber(s [, base])` | convert; `tonumber` returns `nil` on failure |
| `assert(v [, msg])` | error with `msg` if `v` is false or nil, else return all arguments |
| `error(msg [, level])` | raise an error; `level` 2 blames the caller, 0 adds no position |
| `pcall(f, ...)` | call `f` in protected mode: `true, results...` or `false, err` |
| `xpcall(f, handler, ...)` | like `pcall`; `handler(err)` runs before the stack unwinds |
| `select(n, ...)`, `select("#", ...)` | arguments from the `n`th on; the count |
| `unpack(t [, i [, j]])` | `t[i], ..., t[j]` (`table.unpack` in 5.2+) |
| `pairs(t)`, `ipairs(t)`, `next(t [, k])` | iterate; `next(t) == nil` tests for empty |
| `setmetatable(t, mt)`, `getmetatable(v)` | set and get metatables |
| `rawget(t, k)`, `rawset(t, k, v)`, `rawequal(a, b)` | skip metamethods |
| `require(name)` | load a module once, cache it in `package.loaded` |
| `load(s [, name, mode, env])`, `loadstring(s [, name])` | compile a string to a function |
| `loadfile(path)`, `dofile(path)` | compile a file; compile and run it |
| `setfenv(f, env)`, `getfenv(f)` | set and get a function's globals table (5.1 and LuaJIT only) |
| `collectgarbage("collect" \| "count" \| "step")` | run the GC; memory in use in KB |

```lua
tonumber("0x10"), tonumber("10", 2), tonumber("z", 36), tonumber("12a")   --> 16  2  35  nil
pcall(error, { code = 1 })                --> false  table: (address)
pcall(error, "boom", 0)                   --> false  boom
select(2, pcall(error, "boom"))           --> boom
```

The address differs on each run. `error("boom")` called from a C function like `pcall` adds no
position; called from Lua code it adds `file:line:` ([Chapter 9](09-errors.md)).

## `string`

All string functions also work as methods: `s:upper()` is `string.upper(s)`. Positions start at
1; negative positions count from the end.

| Function | Does |
|----------|------|
| `len(s)`, `lower(s)`, `upper(s)`, `reverse(s)` | as named |
| `sub(s, i [, j])` | substring from `i` to `j` |
| `rep(s, n [, sep])` | `s` repeated `n` times, joined by `sep` |
| `byte(s [, i [, j]])`, `char(...)` | bytes to numbers and back |
| `format(fmt, ...)` | printf-style formatting (below) |
| `find(s, pat [, init [, plain]])` | start and end of the first match, plus captures |
| `match(s, pat [, init])` | the captures of the first match (or the whole match) |
| `gmatch(s, pat)` | iterator over all matches |
| `gsub(s, pat, repl [, n])` | replace matches; returns the new string and the count |
| `dump(f)` | a function's bytecode as a string |

```lua
("hello"):sub(2, 3), ("hello"):sub(-3)    --> el  llo
("ab"):rep(3, ","), ("abc"):upper()       --> ab,ab,ab  ABC
("A"):byte(), string.char(72, 105)        --> 65  Hi
("a.b"):find(".", 1, true)                --> 2  2
("key = val"):match("^(%w+)%s*=%s*(%w+)$")   --> key  val
("hello world"):gsub("o", "0")            --> hell0 w0rld  2
("x=1, y=2"):gsub("(%w+)=(%w+)", "%2=%1") --> 1=x, 2=y  2
("$a $b"):gsub("%$(%w+)", { a = "A" })    --> A $b  2
("abc"):gsub("%w", string.upper)          --> ABC  3
("  trim me  "):match("^%s*(.-)%s*$")     --> trim me
```

`string.buffer` (LuaJIT): `local buffer = require("string.buffer")` gives a fast, growable byte
buffer: `buffer.new()`, `b:put(...)`, `b:putf(fmt, ...)`, `b:get(n)`, `b:tostring()`, `b:reset()`,
and `buffer.encode(v)` / `buffer.decode(s)` to serialize Lua values.

## Patterns

| Item | Matches |
|------|---------|
| `.` | any byte |
| `%a` `%d` `%l` `%u` `%s` `%w` `%x` `%p` `%c` | letter, digit, lowercase, uppercase, space, alphanumeric, hex digit, punctuation, control |
| `%g` | printable except space (LuaJIT, 5.2+) |
| `%A` `%D` `%S` ... | the opposite (any byte *not* in the class) |
| `%.` `%%` `%(` ... | a magic character literally; magic characters are `^ $ ( ) % . [ ] * + - ?` |
| `[abc]` `[a-z]` `[^%s,]` | a set, a range, a negated set |
| `*` `+` `-` `?` | 0 or more (longest), 1 or more, 0 or more (shortest), 0 or 1 |
| `^` `$` | anchor at the start, at the end |
| `( )` | capture; `()` captures the position |
| `%1` ... `%9` | the text of an earlier capture |
| `%bxy` | a balanced pair: `%b()` matches `(a(b)c)` |
| `%f[set]` | frontier: the place where the previous byte is not in `set` and the next one is |

Patterns are not regular expressions: there is no `|` alternation, and quantifiers apply to a
single item. In a `gsub` replacement string, `%0` is the whole match and `%%` is a `%`
([Chapter 6](06-strings.md)).

```lua
("x(a(b)c)y"):match("%b()")               --> (a(b)c)
("THE (quick) fox"):match("%f[%a]%a+", 5) --> quick
("2026-08-03"):match("(%d+)-(%d+)-(%d+)") --> 2026  08  03
("hello"):match("()ll()")                 --> 3  5
("<b>x</b>"):match("<(%w+)>.-</%1>")      --> b
```

## `string.format`

| Spec | Example | Result |
|------|---------|--------|
| `%d` `%5d` `%-5d` `%05d` `%+d` | `("%05d"):format(42)` | `00042` |
| `%f` `%.2f` `%8.3f` | `("%.2f"):format(3.14159)` | `3.14` |
| `%e` `%g` | `("%g"):format(0.0001)` | `0.0001` |
| `%x` `%X` `%o` | `("%x"):format(255)` | `ff` |
| `%c` | `("%c"):format(65)` | `A` |
| `%s` `%10s` `%-10s` `%.3s` | `("%.3s"):format("abcdef")` | `abc` |
| `%q` | `("%q"):format('a"b')` | `"a\"b"` |
| `%a` | `("%a"):format(1)` | `0x1p+0` |
| `%%` | `("100%%"):format()` | `100%` |

`%s` calls `tostring`, so it works for any value. In LuaJIT `%d` cuts off a fraction (`1.5`
gives `1`); Lua 5.3+ raises an error instead.

## `table`

| Function | Does |
|----------|------|
| `insert(t, [pos,] v)` | insert at `pos` (default: the end) |
| `remove(t [, pos])` | remove and return the item at `pos` (default: the last) |
| `concat(t [, sep [, i [, j]]])` | join strings and numbers |
| `sort(t [, less])` | sort in place; `less(a, b)` must be a strict order |
| `move(a1, f, e, t [, a2])` | copy `a1[f..e]` to `a2[t..]` (LuaJIT, 5.3+) |
| `maxn(t)` | the largest positive numeric key (5.1, LuaJIT) |
| `require("table.new")(narr, nhash)` | a pre-sized empty table (LuaJIT) |
| `require("table.clear")(t)` | remove every key, keep the allocated space (LuaJIT) |

```lua
local list = { 3, 1, 2 }
table.sort(list)
table.concat(list, " ")                   --> 1 2 3
table.sort(list, function(a, b) return a > b end)
table.concat(list, " ")                   --> 3 2 1
```

## `math`

| Function | Does |
|----------|------|
| `floor(x)`, `ceil(x)`, `abs(x)` | round down, round up, absolute value |
| `max(...)`, `min(...)` | largest, smallest |
| `fmod(x, y)`, `modf(x)` | remainder with the sign of `x`; integer and fractional parts |
| `sqrt(x)`, `exp(x)`, `log(x [, base])`, `log10(x)`, `pow(x, y)` | as named |
| `sin` `cos` `tan` `asin` `acos` `atan` `atan2` `sinh` `cosh` `tanh` `deg` `rad` | trigonometry, radians |
| `frexp(x)`, `ldexp(m, e)` | split into and build from mantissa and exponent |
| `random()`, `random(n)`, `random(m, n)` | float in [0, 1), integer in [1, n], integer in [m, n] |
| `randomseed(x)` | seed the generator |
| `huge`, `pi` | infinity, π |

```lua
math.floor(-3.5), math.ceil(-3.5), math.fmod(-7, 3), math.modf(3.75)   --> -4  -3  -1  3  0.75
math.max(1, 5, 3), math.huge, -math.huge                               --> 5  inf  -inf
2 ^ 53, 1e15, 1e16                        --> 9.007199254741e+15  1e+15  1e+16
```

`tostring` prints at most 14 significant digits. `("%.17g"):format(x)` shows a double exactly;
`("%d"):format(x)` shows a large integer value.

## `io` and files

| Function | Does |
|----------|------|
| `io.open(path [, mode])` | open a file: `"r"`, `"w"`, `"a"`, `"r+"`, `"rb"`, `"wb"`...; `nil, err` on failure |
| `io.lines(path)` | iterate over a file's lines, then close it |
| `io.read(...)`, `io.write(...)` | read stdin, write stdout |
| `io.popen(cmd [, mode])` | run a shell command, read its output (or write its input) |
| `io.stdin`, `io.stdout`, `io.stderr` | the standard files |
| `io.type(v)` | `"file"`, `"closed file"` or `nil` |
| `f:read(fmt)` | `"*l"` line, `"*L"` line with newline, `"*a"` all, `"*n"` number, `n` bytes |
| `f:lines([fmt])` | iterate over lines (does not close `f`) |
| `f:write(...)` | write strings and numbers |
| `f:seek([whence [, offset]])` | `"set"`, `"cur"`, `"end"`; returns the position |
| `f:setvbuf(mode)` | `"no"`, `"full"`, `"line"` buffering |
| `f:flush()`, `f:close()` | as named |

LuaJIT also accepts the read formats without the `*`: `"l"`, `"a"`, `"n"` ([Chapter 12](12-io-and-os.md)).

```lua
local f = assert(io.open("notes.txt", "w"))
f:write("one\n", "two\n")
f:close()
for line in io.lines("notes.txt") do io.write("[", line, "] ") end
print()
os.remove("notes.txt")
```

## `os`

| Function | Does |
|----------|------|
| `os.time([t])` | now, or the time of a date table, in seconds since 1970 |
| `os.date([fmt [, time]])` | format a time; `"!"` first means UTC; `"*t"` returns a table |
| `os.clock()` | CPU time used by the program, in seconds |
| `os.getenv(name)` | an environment variable, or `nil` |
| `os.remove(path)`, `os.rename(a, b)` | delete, rename; `nil, err` on failure |
| `os.tmpname()` | a temporary file name |
| `os.execute(cmd)` | run a shell command; LuaJIT returns the raw status, `0` for success (`exit 3` gives `768`) |
| `os.exit([code])` | exit; `true`/`false` mean success/failure |
| `os.difftime(t2, t1)` | `t2 - t1` in seconds |

```lua
os.date("!%Y-%m-%d %H:%M:%S", 0)          --> 1970-01-01 00:00:00
os.date("!*t", 86400).day                 --> 2
```

Common `os.date` codes: `%Y` year, `%m` month, `%d` day, `%H` `%M` `%S` time, `%a`/`%A` weekday,
`%b`/`%B` month name, `%j` day of the year, `%c` the locale's date and time.

## `coroutine`

| Function | Does |
|----------|------|
| `create(f)` | a new coroutine |
| `resume(co, ...)` | run it until it yields or ends: `true, values...` or `false, err` |
| `yield(...)` | pause, handing values to `resume` |
| `status(co)` | `"suspended"`, `"running"`, `"normal"` or `"dead"` |
| `wrap(f)` | a function that resumes the coroutine and raises its errors |
| `running()` | the running coroutine (`nil` in the main thread) |
| `isyieldable()` | can the current code yield? (LuaJIT, 5.3+) |

```lua
local gen = coroutine.wrap(function() for i = 1, 3 do coroutine.yield(i) end end)
gen(), gen(), gen()                       --> 1  2  3
```

LuaJIT can yield across `pcall`, metamethods and iterators ([Chapter 11](11-coroutines.md)).

## `package` and modules

| Name | Holds |
|------|-------|
| `package.path` | where `require` looks for Lua files: `"./?.lua;..."` |
| `package.cpath` | where `require` looks for C libraries: `"./?.so;..."` |
| `package.loaded` | modules already loaded, by name |
| `package.preload` | loader functions to try first, by name |
| `package.loaders` | the list of searchers `require` tries (`package.searchers` in 5.2+) |
| `package.searchpath(name, path)` | find a file the way `require` would |

```lua
-- mymod.lua: a module is a file that returns a table.
local M = {}
local function helper() return 42 end     -- private
function M.answer() return helper() end   -- public
return M
```

`require("a.b")` searches for `a/b.lua` ([Chapter 8](08-modules.md)).

## `bit` (LuaJIT)

All operations work on 32-bit integers and return signed results.

| Function | Does |
|----------|------|
| `band` `bor` `bxor` `bnot` | and, or, xor, not |
| `lshift` `rshift` `arshift` | shift left, shift right (logical, arithmetic) |
| `rol` `ror` | rotate |
| `bswap(x)` | swap byte order |
| `tobit(x)` | normalize to a signed 32-bit number |
| `tohex(x [, n])` | hex string; `n < 0` for uppercase |

```lua
bit.band(0xff, 0x0f), bit.bor(1, 2, 4), bit.lshift(1, 4)   --> 15  7  16
bit.tobit(0xffffffff), bit.tohex(255), bit.tohex(255, -2) --> -1  000000ff  FF
```

## `jit` (LuaJIT)

| Name | Holds or does |
|------|---------------|
| `jit.version`, `jit.version_num` | `"LuaJIT 2.1.…"`, `20199` |
| `jit.os`, `jit.arch` | `"Linux"`, `"x64"`, ... |
| `jit.on()`, `jit.off()` | turn the compiler on or off (globally, or for a function) |
| `jit.flush()` | throw away compiled code |
| `jit.status()` | `true`/`false` and the enabled optimizations |
| `luajit -jv`, `-jdump`, `-jp` | show traces, dump them, profile ([Chapter 18](18-performance-and-the-jit.md)) |

## `debug`

For tools and error messages: `debug.traceback([msg])` returns a stack trace,
`debug.getinfo(f or level, "Sl")` describes a function (`source`, `currentline`...), and
`debug.sethook`, `debug.getlocal`, `debug.getupvalue` and friends let debuggers look inside.
Don't use them in normal program logic.

## Idioms

```lua
local function greet(name)
  name = name or "world"                  -- default argument
  return "hello " .. name
end
greet(), greet("Lua")                     --> hello world  hello Lua

local set = { lua = true, c = true }      -- a set
set.lua, set.go                           --> true  nil

local parts = {}                          -- build strings with a table
for i = 1, 3 do parts[#parts + 1] = "item" .. i end
table.concat(parts, ", ")                 --> item1, item2, item3

local copy = { unpack({ 1, 2, 3 }) }      -- copy a small array
#copy                                     --> 3

local ok, err = pcall(function() error("bad input", 0) end)
ok, err                                   --> false  bad input

local Point = {}                          -- a class
Point.__index = Point
function Point.new(x, y) return setmetatable({ x = x, y = y }, Point) end
function Point:len() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
Point.new(3, 4):len()                     --> 5
```

Always use `local` unless you mean to make a global ([Chapter 21](21-design-and-next-steps.md)
lists more pitfalls).

Sources for this appendix: [REFERENCES.md](REFERENCES.md#appendix-a--cheat-sheet)
