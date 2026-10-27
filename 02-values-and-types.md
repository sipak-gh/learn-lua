# Chapter 2 — Values and Types

Lua has only eight types, and you use five of them all the time. You learn each one, what counts as
"true", how numbers really work, and why every variable should be `local`. Then come the operators,
including the `and`/`or` idioms found in all Lua code. `stash` gets a version number and reads its
first argument. Previous: [Chapter 1](01-getting-started.md). Next: [Chapter 3](03-control-flow.md).

## Dynamic types

Lua is **dynamically typed**: values have types, variables don't. One variable can hold a number now
and a string later. `type(v)` returns a value's type as a string.

`examples/ch02/types.lua`

```lua
-- type() returns the name of a value's type, as a string.
print(type(nil))              --> nil
print(type(true))             --> boolean
print(type(42))               --> number
print(type("hi"))             --> string
print(type({}))               --> table
print(type(print))            --> function
print(type(io.stdout))        --> userdata  (a C object: an open file)
print(type(coroutine.create(print)))  --> thread (Chapter 11)
print(type(1LL))              --> cdata     (LuaJIT only: C data, Chapter 13)
print(type(type(42)))         --> string: type() itself returns a string
```

```console
$ luajit examples/ch02/types.lua
nil
boolean
number
string
table
function
userdata
thread
cdata
string
```

(`-->` in a comment is a Lua convention for "this prints".)

| Type | Values | Chapter |
|------|--------|---------|
| `nil` | only `nil`: "no value" | here |
| `boolean` | `true`, `false` | here |
| `number` | `42`, `3.5`, `1e9` | here |
| `string` | `"hi"`, `'hi'`, `[[hi]]` | here, [6](06-strings.md) |
| `table` | `{}`, `{1, 2}`, `{x = 1}` | [5](05-tables.md) |
| `function` | `print`, `function() end` | [4](04-functions.md) |
| `userdata` | C objects made by C code, like open files | [12](12-io-and-os.md), [20](20-embedding-luajit.md) |
| `thread` | coroutines | [11](11-coroutines.md) |
| `cdata` | LuaJIT only: C values from the FFI | [13](13-ffi-basics.md) |

Why so few? Lua gives you a few general types and lets you build the rest. Arrays, lists, maps,
sets, objects and modules are all tables.

## `nil`

`nil` means "no value". A never-assigned variable, a missing table field and a missing function
argument are all `nil`.

Assigning `nil` deletes: a table field set to `nil` no longer exists ([Chapter 5](05-tables.md)
relies on this).

## Booleans and truthiness

The booleans are `true` and `false`. In a condition, **only `nil` and `false` are false. Everything
else is true**, including `0`, the empty string and the empty table.

`examples/ch02/truthiness.lua`

```lua
-- Only nil and false are false. Everything else is true,
-- including 0, the empty string and the empty table.
print(not nil, not false, not 0, not "", not "false", not {})

if 0 then print("0 is true") end
if "" then print("the empty string is true") end
if nil then print("never printed") end

-- Use == and ~= to test for a specific value.
local n = 0
print(n == 0, n ~= 0)
```

```console
$ luajit examples/ch02/truthiness.lua
true	true	false	false	false	false
0 is true
the empty string is true
true	false
```

(`if ... then ... end` runs its body when the condition is true; see [Chapter 3](03-control-flow.md).)

This is simpler than C's or Python's rule: a value is "present" unless it is `nil` or `false`, so
`if x then` means "if x exists". Gotcha for C programmers: `if 0 then` runs. When a C function
returns `0`/`1` through the FFI, compare with `== 1` ([Chapter 13](13-ffi-basics.md)).

## Numbers

Lua 5.1 has **one** number type: a 64-bit floating-point value (a C `double`). No separate integer
type.

`examples/ch02/numbers.lua`

```lua
-- One number type: a 64-bit floating-point value (a C double).
print(7 + 2, 7 - 2, 7 * 2)    -- whole results print without ".0"
print(7 / 2)                  -- / always divides exactly
print(math.floor(7 / 2))      -- integer division: floor of the quotient
print(7 % 3, -7 % 3)          -- % takes the sign of the divisor
print(2 ^ 10, 2 ^ 0.5)        -- ^ is exponentiation (always a float)
print(0xff, 1e3, 2.5e-3)      -- hex and scientific notation

-- Every integer up to 2^53 is exact. Beyond that, gaps appear.
print(2 ^ 53, 2 ^ 53 + 1 == 2 ^ 53)

-- Floats are binary fractions, so decimal fractions are approximations.
print(0.1 + 0.2 == 0.3, string.format("%.17g", 0.1 + 0.2))

-- Division by zero is not an error.
print(1 / 0, -1 / 0, 0 / 0)
print(math.huge, math.pi, math.max(3, 9, 4), math.abs(-2))
```

```console
$ luajit examples/ch02/numbers.lua
9	5	14
3.5
3
1	2
1024	1.4142135623731
255	1000	0.0025
9.007199254741e+15	true
false	0.30000000000000004
inf	-inf	nan
inf	3.1415926535898	9	2
```

Remember:

- **Integers are exact up to 2^53** (about 9 × 10^15), so counting, indexing and ids are safe.
  64-bit integers come later through the FFI, as `cdata` such as `1LL` ([Chapter 13](13-ffi-basics.md)).
- **No `//` operator** in Lua 5.1. Write `math.floor(a / b)`.
- **`%` takes the divisor's sign**: `a % b == a - math.floor(a / b) * b`. So `-7 % 3` is `2`, not
  `-1` as in C.
- `print` shows at most 14 significant digits (`3.1415926535898`). `string.format("%.17g", x)`
  shows all of them ([Chapter 6](06-strings.md)).
- `0 / 0` is NaN, "not a number" (some platforms print `-nan`). NaN is the only value not equal to
  itself: `x ~= x` is true only for NaN.
- `math` has the usual functions: `floor`, `ceil`, `abs`, `max`, `min`, `sqrt`, `random`, `huge`
  (infinity), `pi`.

Why only doubles? One type is simpler, and a double holds every 32-bit integer exactly. The cost is
the 2^53 limit. Lua 5.3 removed it by adding a real integer type
([Appendix C](appendix-c-lua-versions.md)).

## Strings

A string is a sequence of bytes. There are three ways to write one:

`examples/ch02/strings.lua`

```lua
local a = "double quotes"
local b = 'single quotes'
local c = [[a long string:
it can span lines and has no escapes: \n stays \n]]
print(a, b)
print(c)

-- Escapes in quoted strings.
print("tab:\t|  newline:\n|  quote:\"  backslash:\\")
print("\65\066\x43")          -- decimal \ddd and hex \xXX byte escapes

-- # gives the length in bytes. Strings may contain any byte, even zero.
print(#"hello", #"", #"a\0b")
print(#"héllo")               -- é is two bytes in UTF-8

-- .. joins strings. Numbers are converted to text automatically.
local name = "Lua"
print("Hello, " .. name .. " " .. 5.1)

-- Strings are immutable: "changing" one makes a new string.
local s = "hello"
local t = s:upper()           -- method call syntax (Chapter 6)
print(s, t)
```

```console
$ luajit examples/ch02/strings.lua
double quotes	single quotes
a long string:
it can span lines and has no escapes: \n stays \n
tab:	|  newline:
|  quote:"  backslash:\
ABC
5	0	3
6
Hello, Lua 5.1
hello	HELLO
```

Three properties matter:

- **Immutable.** Nothing changes a string in place. `s:upper()` returns a new string and leaves `s`
  alone. `s[1] = "x"` is an error.
- **Interned.** Lua keeps one copy of each distinct string. So `==` on strings is as cheap as on
  numbers, and strings are fast table keys. The cost moves to creation: each new string is hashed
  and looked up.
- **8-bit clean.** A string holds any bytes, even `\0`. Lua ignores encodings: `#` counts bytes, not
  characters. So strings hold binary data well, like the compressed pages in
  [Chapter 17](17-binary-data-and-zlib.md).

Long strings (`[[ ... ]]`, `[==[ ... ]==]`) work like block comments: no escapes, and the number of
`=` signs must match. [Chapter 6](06-strings.md) covers the string library.

## Local and global variables

A variable is **global** unless you declare it `local`.

`examples/ch02/locals.lua`

```lua
-- A local lives from its declaration to the end of its block.
local count = 0
count = count + 1

-- A typo silently creates a new GLOBAL variable. No error.
cuont = count + 1
print(count, cuont)

-- Reading a name that was never assigned gives nil. No error either.
print(undefined_name)

-- Globals are fields of the table _G.
print(_G.cuont, _G.count)     -- count is local, so it isn't in _G

-- A local declared without a value starts as nil.
local x
print(x)

-- `local x = x` makes a local copy of a global (a common speed idiom).
local print = print
print("still works")
```

```console
$ luajit examples/ch02/locals.lua
1	2
nil
2	nil
nil
still works
```

Globals live in one table, `_G`, shared by the whole program. **Use `local` for everything:**

1. **Mistakes.** A typo in an assignment makes a new global; a typo in a read gives `nil`. Neither
   is an error, so the bug shows up later, somewhere else. [Chapter 7](07-metatables-and-objects.md)
   turns these into errors.
2. **Isolation.** Every file can see and overwrite every global.
3. **Speed.** A local is a slot in a register-like array. A global is a table lookup by name.

A local is visible from the statement *after* its declaration to the end of its block (the file, a
function, or a `do ... end`, [Chapter 3](03-control-flow.md)). Constants get `UPPER_CASE` names by
convention. Lua 5.1 has no real constants; the name is only a hint.

## Multiple assignment

`examples/ch02/assign.lua`

```lua
-- Multiple assignment: a list of names = a list of values.
local a, b, c = 1, 2
print(a, b, c)                -- missing values become nil

local x, y = 10, 20, 30       -- extra values are dropped
print(x, y)

-- All values on the right are evaluated BEFORE any assignment,
-- so swapping needs no temporary variable.
x, y = y, x
print(x, y)

local i = 1
i, a = i + 1, i               -- a gets the OLD i
print(i, a)
```

```console
$ luajit examples/ch02/assign.lua
1	2	nil
10	20
20	10
2	1
```

Lua fits the values to the names: extra values are dropped, missing ones become `nil`. Functions
that return several values follow the same rule ([Chapter 4](04-functions.md)).

## Operators

| Kind | Operators |
|------|-----------|
| Arithmetic | `+ - * / % ^` and unary `-` |
| Comparison | `== ~= < > <= >=` |
| Logic | `and or not` |
| Strings | `..` (concatenate) |
| Length | `#` (strings and arrays) |

`examples/ch02/operators.lua`

```lua
-- Comparison returns a boolean. "Not equal" is ~=, not !=.
print(1 < 2, 1 <= 1, 2 > 3, 1 == 1.0, 1 ~= 2)

-- Values of different types are never equal...
print(1 == "1", nil == false)

-- ...and < between different types is an error (see below).
print("a" < "b", "Z" < "a", "10" < "9")  -- strings compare byte by byte

-- Precedence, highest first:
--   ^   then   not # - (unary)   then   * / %   then   + -
--   then ..   then  < > <= >= ~= ==   then  and   then  or
print(-2 ^ 2)                 -- -(2^2): ^ binds tighter than unary minus
print(2 ^ 3 ^ 2)              -- 2^(3^2): ^ and .. are right-associative
print(1 + 2 .. "")            -- (1+2) .. "": arithmetic before ..
print(not 1 == 2)             -- (not 1) == 2, so false == 2: false
```

```console
$ luajit examples/ch02/operators.lua
true	true	false	true	true
false	false
true	true	true
-4
512
3
false
```

- `==` compares types first. Different types are never equal: `1 == "1"` is `false`.
- Tables, functions and other objects compare by **identity**: two separate `{}` are not equal.
- `<` works on two numbers or two strings. Strings compare byte by byte, so `"Z" < "a"` and
  `"10" < "9"`.
- Unsure about precedence? Add parentheses.

Errors you will meet:

```console
$ luajit -e 'print(1 < "2")'
luajit: (command line):1: attempt to compare number with string
$ luajit -e 'local name; print("hi " .. name)'
luajit: (command line):1: attempt to concatenate local 'name' (a nil value)
$ luajit -e 'print(7 // 2)'
luajit: (command line):1: unexpected symbol near '/'
$ luajit -e 'print(1..2)'
luajit: (command line):1: malformed number near '1..2'
```

(Runtime errors also print a stack traceback, left out here.) In the last one, Lua reads `1..2` as a
badly written number. Put spaces around `..` when a number is on its left: `1 .. 2`.

> **Newer syntax in recent builds.** LuaJIT 2.1 builds from July 2026 on also accept some syntax
> backported from LuaJIT 3.0: `!=`, `!`, `&&`, `||`, `+=` and the other compound assignments,
> `a ? b : c`, `??`, `continue`, `const`, and more. Older 2.1 builds and PUC Lua reject it. This
> course doesn't use it, so its code runs on any LuaJIT 2.1 and moves easily to PUC Lua.

## `and`, `or` and their idioms

`and` and `or` **short-circuit**: they evaluate the right side only when needed. They return one of
their operands, not just `true` or `false`:

- `a or b` is `a` if `a` is true (not `nil`/`false`), else `b`.
- `a and b` is `a` if `a` is false (`nil`/`false`), else `b`.

`examples/ch02/andor.lua`

```lua
-- and/or return one of their operands, not just true/false.
print(nil or "default")       -- or: the first operand if it is true, else the second
print("value" or "default")
print(nil and "x")            -- and: the first operand if it is false, else the second
print(1 and "x")

-- Idiom 1: a default value.
local name = arg[1] or "world"
print("hello " .. name)

-- Idiom 2: a choice, like C's  c ? x : y
local n = 7
print(n % 2 == 0 and "even" or "odd")

-- The gotcha: if x is false or nil, `c and x or y` gives y.
local flag = true
print(flag and false or "oops")   -- prints oops, not false

-- Short-circuit: the right side runs only when needed.
local t = nil
print(t and t.field)          -- no error: t.field is never evaluated
```

```console
$ luajit examples/ch02/andor.lua
default
value
nil
x
hello world
odd
oops
nil
$ luajit examples/ch02/andor.lua Ada | head -5 | tail -1
hello Ada
```

These idioms are everywhere in Lua code:

- **`x = x or default`** fills in a missing value. It also replaces `false`, so don't use it for
  boolean settings that may be `false`.
- **`c and x or y`** picks `x` or `y`. Safe only when `x` can't be `nil` or `false`; otherwise use
  an `if` ([Chapter 3](03-control-flow.md)).
- **`t and t.field`** reads a field only if `t` exists, instead of crashing on `nil`.

## Conversions and coercions

`examples/ch02/convert.lua`

```lua
-- tostring turns any value into a string.
print(tostring(42), tostring(1.5), tostring(nil), tostring(true))

-- tonumber turns a string into a number, or returns nil.
print(tonumber("42"), tonumber("  3.5  "), tonumber("0x10"), tonumber("1e2"))
print(tonumber("12abc"), tonumber(""), tonumber("abc"))
print(tonumber("ff", 16), tonumber("777", 8), tonumber("101", 2))

-- Arithmetic converts strings to numbers; .. converts numbers to strings.
print("10" + 1, "3" * "4", 10 .. 20)

-- But == never converts: a string is not equal to a number.
print("10" == 10, tonumber("10") == 10)
```

```console
$ luajit examples/ch02/convert.lua
42	1.5	nil	true
42	3.5	16	100
nil	nil	nil
255	511	5
11	12	1020
false	true
```

- `tonumber(s)` returns `nil` unless the whole string is a number (surrounding spaces are fine).
  Use it to check input: `tonumber(arg[1]) == nil` means "not a number".
- `tonumber(s, base)` reads bases 2 to 36.
- **Coercion**: arithmetic converts numeric strings (`"10" + 1` is `11`), and `..` converts numbers
  to strings. Don't rely on the first. Convert with `tonumber`, so a bad string gets a clear error
  of your own instead of `attempt to perform arithmetic on a string value`.

## Building stash: a version and the first argument

`stash` now reads its first argument: `help` (or nothing) prints the usage, `version` the version,
anything else an error. `if` comes in Chapter 3, so for now `and`/`or` pick the message.

Changes from Chapter 1:

- `VERSION` is a local constant.
- The usage text moves into one string, `USAGE`, built with `..` across lines. The title line is
  dropped and a `version` command is added.
- `arg[1] or "help"` gives a default command.
- An `and`/`or` chain picks one of three messages.

Replace `stash.lua` with:

`stash.lua`

```lua
#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 2: a version constant and a first look at the arguments.

-- `local` keeps names private to this file. Upper case marks constants
-- (a convention only: Lua has no real constants).
local VERSION = "0.1.0"

local USAGE = "usage: stash <command> [arguments]\n" ..
  "\n" ..
  "commands:\n" ..
  "  add URL       save a bookmark\n" ..
  "  list          list bookmarks\n" ..
  "  search TERM   search bookmarks\n" ..
  "  show ID       show one bookmark\n" ..
  "  rm ID         delete a bookmark\n" ..
  "  help          show this help\n" ..
  "  version       print the version"

-- arg[1] is nil when no argument was given; `or` supplies a default.
local command = arg[1] or "help"

-- No `if` yet (that is Chapter 3): `and`/`or` pick one of three messages.
-- Each `x and y` yields y only when x is true, so the first true test wins.
local message = (command == "help" and USAGE)
  or (command == "version" and "stash " .. VERSION)
  or "stash: unknown command '" .. command .. "' (try 'stash help')"

print(message)
```

How the chain works for `command = "version"`:

1. `command == "help"` is `false`, so `(false and USAGE)` is `false`.
2. `false or (...)` moves on. `command == "version"` is `true`, so the second group gives the
   string `"stash " .. VERSION`.
3. A true left side of `or` ends the chain.

The `c and x or y` gotcha can't happen here: `USAGE` and `"stash " .. VERSION` are strings, never
`nil` or `false`. `..` binds tighter than `and`, so `"stash " .. VERSION` needs no parentheses.

### Checkpoint

```console
$ luajit stash.lua version
stash 0.1.0
$ luajit stash.lua
usage: stash <command> [arguments]

commands:
  add URL       save a bookmark
  list          list bookmarks
  search TERM   search bookmarks
  show ID       show one bookmark
  rm ID         delete a bookmark
  help          show this help
  version       print the version
$ luajit stash.lua frobnicate
stash: unknown command 'frobnicate' (try 'stash help')
```

The complete project at this point is in `project/ch02/`.

## Summary

- Eight types: `nil`, `boolean`, `number`, `string`, `table`, `function`, `userdata`, `thread`, plus
  LuaJIT's `cdata`. `type(v)` returns the name.
- Only `nil` and `false` are false. `0` and `""` are true.
- Numbers are doubles, exact for integers up to 2^53. No `//`: use `math.floor(a / b)`.
- Strings are immutable, interned byte sequences. `#s` is the length in bytes; `..` joins.
- Make every variable `local`. Globals are fields of `_G`, and typos in their names aren't errors.
- `a, b = b, a` swaps. Extra values are dropped, missing ones become `nil`.
- Not-equal is `~=`. Different types are never `==`; `<` across types is an error.
- Core idioms: `x or default` and `c and x or y`. The second fails when `x` is `nil`/`false`.
- Convert with `tonumber`/`tostring`. Don't rely on automatic string-to-number coercion.

## Exercises

1. Predict the output, then check it:
   `print(10 / 4, 10 % 4, "5" + 5, 5 .. 5, 2 ^ 2, #"5" + 5, nil == false)`

<details><summary>Solution</summary>

```console
$ luajit -e 'print(10 / 4, 10 % 4, "5" + 5, 5 .. 5, 2 ^ 2, #"5" + 5, nil == false)'
2.5	2	10	55	4	6	false
```

`/` never truncates. `"5" + 5` coerces the string. `5 .. 5` is the string `"55"`. `^` gives 4.
`#"5"` is 1 (one byte), so `#"5" + 5` is 6. `nil` and `false` both act as false in a condition,
but they are different values of different types.

</details>

2. Write `kind.lua` that prints its first argument, its type, the result of `tonumber` on it, and
   that result's type. Try `42`, `0x1F` and `forty`. Use `arg[1] or ""` so a missing argument works.

<details><summary>Solution</summary>

```lua
local input = arg[1] or ""
local n = tonumber(input)
print(input, type(input), n, type(n))
```

```console
$ luajit kind.lua 42
42	string	42	number
$ luajit kind.lua 0x1F
0x1F	string	31	number
$ luajit kind.lua forty
forty	string	nil	nil
```

Command-line arguments are always strings, even when they look like numbers.

</details>

3. Make `stash.lua` accept `-v` as another name for `version`. Change only the `and`/`or` chain.

<details><summary>Solution</summary>

```lua
local message = (command == "help" and USAGE)
  or ((command == "version" or command == "-v") and "stash " .. VERSION)
  or "stash: unknown command '" .. command .. "' (try 'stash help')"
```

```console
$ luajit stash.lua -v
stash 0.1.0
```

The inner `or` is `true` for either name. It needs parentheses because `and` binds tighter than
`or`. (The project doesn't keep this change; Chapter 3 adds `--version`.)

</details>

4. Lua 5.1 has no `math.round`. Round to the nearest whole number with `math.floor(x + 0.5)`. What
   do you get for `2.4`, `2.5`, `-2.5` and `-2.6`?

<details><summary>Solution</summary>

```console
$ luajit -e 'print(math.floor(2.4 + 0.5), math.floor(2.5 + 0.5), math.floor(-2.5 + 0.5), math.floor(-2.6 + 0.5))'
2	3	-2	-3
```

Halves always round up (towards positive infinity), so `-2.5` becomes `-2`. Fine for most uses;
watch out when you need symmetric rounding.

</details>

5. This code should make `quiet` false when the environment variable `DEBUG` is `1`.
   `os.getenv(name)` returns the variable's value, or `nil`. What is `quiet` when `DEBUG=1`, and
   why? Rewrite it so it can't go wrong.

   ```lua
   local debug_on = os.getenv("DEBUG") == "1"
   local quiet = debug_on and false or true
   print(quiet)
   ```

<details><summary>Solution</summary>

```console
$ DEBUG=1 luajit quiet.lua
true
```

With `DEBUG=1`, `debug_on` is `true`, so `debug_on and false` is `false`, and `false or true` is
`true`: the opposite of what was meant. That is the `c and x or y` gotcha with `x = false`.

The fix needs no `and`/`or` at all:

```lua
local debug_on = os.getenv("DEBUG") == "1"
local quiet = not debug_on
```

`==` already gives a boolean; `not` flips it. Use `c and x or y` only when `x` is never `nil` or
`false`.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-2--values-and-types)
