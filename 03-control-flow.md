# Chapter 3 — Control Flow

How Lua decides and repeats: `if`, three kinds of loops, `break`, and `goto`. The set is small on
purpose. There is no `switch` and no `continue`; you learn what to use instead. `stash` learns to
scan all its arguments, so `--help` and `--version` work anywhere on the command line. Previous:
[Chapter 2](02-values-and-types.md). Next: [Chapter 4](04-functions.md).

## `if`, `elseif`, `else`

`examples/ch03/ifelse.lua`

```lua
-- Usage: luajit ifelse.lua NUMBER
local n = tonumber(arg[1])

if n == nil then
  print("not a number: " .. tostring(arg[1]))
elseif n < 0 then
  print(n .. " is negative")
elseif n == 0 then
  print("zero")
else
  if n % 2 == 0 then
    print(n .. " is positive and even")
  else
    print(n .. " is positive and odd")
  end
end
```

```console
$ luajit examples/ch03/ifelse.lua 7
7 is positive and odd
$ luajit examples/ch03/ifelse.lua -2
-2 is negative
$ luajit examples/ch03/ifelse.lua 0
zero
$ luajit examples/ch03/ifelse.lua x
not a number: x
$ luajit examples/ch03/ifelse.lua
not a number: nil
```

- The form is `if cond then ... elseif cond then ... else ... end`. One `end` closes the chain.
- `elseif` is one word. `else if` opens a *new* `if` that needs its own `end`.
- The condition can be any value; only `nil` and `false` are false
  ([Chapter 2](02-values-and-types.md)).
- The condition needs no parentheses.

There is no `switch`. Use an `if`/`elseif` chain, or a table that maps each case to a function
([Chapter 5](05-tables.md)). With many cases, the table is the Lua way.

Common mistakes:

```console
$ luajit -e 'x = 1 if x = 1 then end'
luajit: (command line):1: 'then' expected near '='
$ luajit -e 'if x then print(1)'
luajit: (command line):1: 'end' expected near '<eof>'
```

`=` is assignment, and assignment isn't an expression in Lua, so `if x = 1` can't compile. Use `==`.

## `while`

`while cond do ... end` checks the condition before each pass, so it may run zero times.

`examples/ch03/while.lua`

```lua
-- while checks the condition BEFORE each pass.
-- The Collatz sequence: halve even numbers, map odd n to 3n + 1.
local n = tonumber(arg[1]) or 6
local steps = 0
while n ~= 1 do
  if n % 2 == 0 then
    n = n / 2
  else
    n = 3 * n + 1
  end
  steps = steps + 1
end
print("reached 1 after " .. steps .. " steps")
```

```console
$ luajit examples/ch03/while.lua
reached 1 after 8 steps
$ luajit examples/ch03/while.lua 27
reached 1 after 111 steps
```

`while true do ... end` is the usual endless loop; leave it with `break` or `return`.

## `repeat ... until`

`repeat ... until cond` checks the condition after each pass, so the body runs at least once. The
loop stops when the condition becomes **true** (the opposite of `while`).

`examples/ch03/repeat.lua`

```lua
-- repeat ... until checks the condition AFTER each pass,
-- so the body always runs at least once.
local n = 0
repeat
  n = n + 1
  local square = n * n
until square > 50              -- the body's locals are visible here
print(n, "is the first number whose square is over 50")

-- The body runs once even when the condition is already true.
repeat
  print("ran once")
until true
```

```console
$ luajit examples/ch03/repeat.lua
8	is the first number whose square is over 50
ran once
```

The scope quirk: the `until` condition sees locals declared in the body (`square` above). In most
languages the body's scope ends before the condition; in Lua it ends after. You don't need to
declare the variable outside the loop.

## Numeric `for`

`for var = start, stop, step do ... end` counts from `start` to `stop`, **inclusive**. `step` is
optional (default 1).

`examples/ch03/numfor.lua`

```lua
-- for var = start, stop [, step] do ... end   (stop is inclusive)
-- io.write prints its arguments with no tabs and no newline (Chapter 12).
for i = 1, 3 do io.write(i, " ") end print()
for i = 10, 1, -3 do io.write(i, " ") end print()
for i = 1, 0 do print("never runs") end

-- start, stop and step are evaluated once, before the loop starts.
local n = 3
for i = 1, n do n = 10; io.write(i, " ") end print()

-- The loop variable is a new local, gone after the loop.
for i = 1, 2 do end
print(i)                       -- nil: this is the global `i`

-- Float steps accumulate rounding errors. 0.3 is never reached:
for x = 0, 0.3, 0.1 do io.write(x, " ") end print()

-- Loop over integers and compute the float instead.
for k = 0, 3 do io.write(k / 10, " ") end print()
```

```console
$ luajit examples/ch03/numfor.lua
1 2 3 
10 7 4 1 
1 2 3 
nil
0 0.1 0.2 
0 0.1 0.2 0.3 
```

Rules:

- `start`, `stop` and `step` are evaluated **once**. Changing `n` in the loop doesn't change the
  number of passes.
- The loop variable is a fresh local for the body. It is gone after the loop.
- Don't assign to the loop variable in the body; the reference manual says you must not. Need to
  control the counter yourself? Use `while`.
- A negative `step` counts down. If start is already past stop, the loop runs zero times.
- Float steps add up rounding error. After three additions of `0.1`, `x` is `0.30000000000000004`,
  more than `0.3`, so the loop stops early. Loop over integers and divide instead.

## Generic `for`

The generic `for` walks over the values an *iterator* produces. You use two built-in iterators long
before [Chapter 11](11-coroutines.md) shows how to write your own:

- `ipairs(t)` gives `index, value` for each item of an array, in order.
- `pairs(t)` gives `key, value` for every entry of a table, in no particular order.

`examples/ch03/genfor.lua`

```lua
-- The generic for walks over whatever an iterator function gives it.
-- ipairs: the items of an array, in order, with their index.
local fruits = { "apple", "banana", "cherry" }
for i, fruit in ipairs(fruits) do
  print(i, fruit)
end

-- pairs: every key and value of a table, in no particular order.
local ages = { ada = 36, alan = 41 }
for name, age in pairs(ages) do
  print(name, age)
end
```

```console
$ luajit examples/ch03/genfor.lua
1	apple
2	banana
3	cherry
alan	41
ada	36
```

The `pairs` order may differ on your machine; never depend on it. [Chapter 5](05-tables.md) covers
tables and both iterators in depth.

## `break` and early `return`

`break` leaves the innermost loop. `return` leaves the current function, or the whole script at the
top level.

`examples/ch03/break.lua`

```lua
-- break leaves the innermost loop at once.
local words = { "alpha", "beta", "", "delta" }
local first_empty
for i, w in ipairs(words) do
  if w == "" then
    first_empty = i
    break
  end
end
print("first empty word at", first_empty)

-- `return` also ends a function or a whole chunk early.
-- Like break, it must be the last statement in its block,
-- so to stop in the middle of a block, wrap it: do return end
print("before")
do return end
print("after")                 -- never runs
```

```console
$ luajit examples/ch03/break.lua
first empty word at	3
before
```

In Lua 5.1, `break` and `return` must be the **last statement of a block**. Code after them in the
same block is a syntax error:

```console
$ luajit -e 'for i = 1, 2 do break print(i) end'
luajit: (command line):1: 'end' expected near 'print'
$ luajit -e 'break'
luajit: (command line):1: no loop to break
```

The rule exists because code after them could never run. To use one mid-block, wrap it in
`do ... end`, for example to switch off the rest of a script while debugging.

## `goto` and labels

`goto name` jumps to a label `::name::` in the same function. It came with Lua 5.2, and LuaJIT
supports it. Its main jobs are the two things Lua lacks: `continue`, and breaking out of nested
loops.

`examples/ch03/continue.lua`

```lua
-- Lua has no `continue`. A goto to a label at the end of the body does the job.
for i = 1, 6 do
  if i % 3 == 0 then
    goto continue              -- skip multiples of 3
  end
  io.write(i, " ")
  ::continue::
end
print()

-- goto also leaves nested loops in one step.
for row = 1, 3 do
  for col = 1, 3 do
    if row * col == 4 then
      print("found 4 at", row, col)
      goto done
    end
  end
end
::done::
print("after the loops")
```

```console
$ luajit examples/ch03/continue.lua
1 2 4 5 
found 4 at	2	2
after the loops
```

`continue` is not a keyword, so it works as a label name. `goto continue` with `::continue::` at
the end of the loop body is the standard idiom.

Rules:

- `goto` jumps to a label in the same block or an enclosing block. It can jump out of nested
  blocks, but not into them, and never out of a function.
- `goto` can't jump into the scope of a local. A label at the very end of a block is fine even after
  local declarations, which is why the `continue` idiom works with locals in the body.

```lua
goto skip
local x = 1
print(x)
::skip::
print("end")
```

```console
$ luajit skip.lua
luajit: skip.lua:1: <goto skip> jumps into the scope of local 'x'
$ luajit -e 'goto nowhere'
luajit: (command line):1: undefined label 'nowhere'
```

Here another statement follows `::skip::`, so `x` would be visible at `print("end")` without ever
being set. Lua refuses. Wrap the skipped part in `do ... end` to end `x`'s scope before the label.

Use `goto` for these two jobs and little else. Free jumping makes code hard to follow.

> LuaJIT 2.1 builds from July 2026 on also accept a real `continue` statement. Older builds and PUC
> Lua don't, so this course uses `goto continue`.

## Blocks: `do ... end`

`do ... end` makes a block on its own. Locals declared inside end with it.

`examples/ch03/blocks.lua`

```lua
-- do ... end makes a block: locals declared inside end with it.
local x = "outer"
do
  local x = "inner"            -- shadows the outer x inside the block
  local temp = 42
  print(x, temp)
end
print(x, temp)                 -- temp is gone: this reads the global, nil
```

```console
$ luajit examples/ch03/blocks.lua
inner	42
outer	nil
```

Use it to limit how long a helper variable lives, or to wrap a `return`/`break` that isn't at the
end of a block. Every `then`, `do`, `repeat` and function body is a block too, with the same rules.

## Building stash: flags anywhere

So far `stash` read only `arg[1]`. Real tools accept global flags anywhere: `stash list --version`
should print the version. Now `stash`:

- walks over every argument with a numeric `for`,
- records `-h`/`--help` and `--version` wherever they appear, then skips to the next argument with
  `goto continue`,
- takes the first non-flag argument as the command,
- picks an action with an `if`/`elseif` chain,
- says "not implemented yet" for known commands that don't work yet.

The usage text gains an `options:` section. Replace `stash.lua` with:

`stash.lua`

```lua
#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 3: walk over the arguments and decide what to do.

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
  "  version       print the version\n" ..
  "\n" ..
  "options:\n" ..
  "  -h, --help    show this help\n" ..
  "  --version     print the version"

local command                 -- the first argument that is not a flag
local want_help = false
local want_version = false

-- Flags may appear anywhere, so look at every argument.
for i = 1, #arg do
  local a = arg[i]
  if a == "-h" or a == "--help" then
    want_help = true
    goto continue             -- Lua has no `continue`; a goto does the job
  end
  if a == "--version" then
    want_version = true
    goto continue
  end
  if command == nil then
    command = a
  end
  ::continue::
end

if want_help or command == "help" then
  print(USAGE)
elseif want_version or command == "version" then
  print("stash " .. VERSION)
elseif command == nil then
  print(USAGE)
elseif command == "add" or command == "list" or command == "search"
    or command == "show" or command == "rm" then
  print("stash: '" .. command .. "' is not implemented yet")
else
  print("stash: unknown command '" .. command .. "' (try 'stash help')")
end
```

Notes:

- `#arg` is the number of arguments ([Chapter 5](05-tables.md) explains `#` on tables).
- `local command` with no value starts as `nil`: "no command seen yet".
- The order of the `if` chain sets priorities: help beats version, and both beat the command.
- A long condition can go on over several lines; Lua ignores line breaks.

### Checkpoint

```console
$ luajit stash.lua list --version
stash 0.1.0
$ luajit stash.lua --help | tail -3
options:
  -h, --help    show this help
  --version     print the version
$ luajit stash.lua add https://www.lua.org/
stash: 'add' is not implemented yet
$ luajit stash.lua frobnicate
stash: unknown command 'frobnicate' (try 'stash help')
$ luajit stash.lua --version
stash 0.1.0
```

The complete project at this point is in `project/ch03/`.

## Summary

- `if ... then ... elseif ... else ... end`. No `switch`: use `elseif` chains or tables.
- `while cond do ... end` tests first. `repeat ... until cond` tests last, runs at least once, and
  its condition sees the body's locals.
- Numeric `for i = a, b, step` includes `b`, evaluates its limits once, and has a loop-local counter.
  Avoid float steps.
- Generic `for k, v in pairs(t)` / `for i, v in ipairs(t)` walk tables.
- `break` and `return` must end their block; `do return end` returns from the middle.
- `goto continue` + `::continue::` replaces `continue`. `goto` can't enter a local's scope.
- `do ... end` limits the life of locals.

## Exercises

1. Print FizzBuzz for 1 to 15: `Fizz` for multiples of 3, `Buzz` for multiples of 5, `FizzBuzz`
   for both, else the number.

<details><summary>Solution</summary>

```lua
for i = 1, 15 do
  if i % 15 == 0 then
    print("FizzBuzz")
  elseif i % 3 == 0 then
    print("Fizz")
  elseif i % 5 == 0 then
    print("Buzz")
  else
    print(i)
  end
end
```

```console
$ luajit fizz.lua | tr '\n' ' '
1 2 Fizz 4 Buzz Fizz 7 8 Fizz Buzz 11 Fizz 13 14 FizzBuzz 
```

Test `% 15` first, or the `% 3` branch wins for 15.

</details>

2. Sum the digits of a number given as the first argument (`1234` → `10`). Use `repeat ... until`
   so that `0` works too.

<details><summary>Solution</summary>

```lua
local n = tonumber(arg[1]) or 0
local sum = 0
repeat
  sum = sum + n % 10
  n = math.floor(n / 10)
until n == 0
print(sum)
```

```console
$ luajit digits.lua 1234
10
$ luajit digits.lua 0
0
$ luajit digits.lua 9999
36
```

</details>

3. Print a 4×4 multiplication table, one row per line, values separated by tabs. Use two nested
   numeric `for` loops and `io.write`.

<details><summary>Solution</summary>

```lua
for row = 1, 4 do
  for col = 1, 4 do
    io.write(row * col, "\t")
  end
  print()
end
```

```console
$ luajit table.lua
1	2	3	4	
2	4	6	8	
3	6	9	12	
4	8	12	16	
```

</details>

4. Rewrite the first loop of `continue.lua` without `goto`. Which version reads better here, and
   when does `goto continue` win?

<details><summary>Solution</summary>

```lua
for i = 1, 6 do
  if i % 3 ~= 0 then
    io.write(i, " ")
  end
end
print()
```

```console
$ luajit nocont.lua
1 2 4 5 
```

With one short body, the `if` reads better. `goto continue` wins when several "skip this one"
checks come before a long body: each check stays flat instead of nesting another `if`.

</details>

5. Unix tools treat `--` as "no more flags". Change `stash.lua` so that every argument after `--` is
   a plain word, even if it looks like a flag. `stash -- --version` should report an unknown command
   `--version`.

<details><summary>Solution</summary>

Add a `flags_done` variable and two checks at the top of the loop:

```lua
local command                 -- the first argument that is not a flag
local want_help = false
local want_version = false
local flags_done = false      -- true after "--"

-- Flags may appear anywhere, so look at every argument.
for i = 1, #arg do
  local a = arg[i]
  if flags_done then
    if command == nil then
      command = a
    end
    goto continue
  end
  if a == "--" then
    flags_done = true
    goto continue
  end
  if a == "-h" or a == "--help" then
    want_help = true
    goto continue             -- Lua has no `continue`; a goto does the job
  end
  if a == "--version" then
    want_version = true
    goto continue
  end
  if command == nil then
    command = a
  end
  ::continue::
end
```

```console
$ luajit stash.lua -- --version
stash: unknown command '--version' (try 'stash help')
$ luajit stash.lua --version --
stash 0.1.0
```

(The project doesn't keep this change.)

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-3--control-flow)
