# Chapter 4 — Functions

Functions are values, like numbers and strings: store them in variables, pass them to other
functions, return them. You learn to define and call them, and you meet multiple results, variable
arguments, closures, recursion and tail calls. Functions and tables are the building blocks of
everything else in Lua. `stash` turns each command into a function. Previous:
[Chapter 3](03-control-flow.md). Next: [Chapter 5](05-tables.md).

## Defining and calling functions

`examples/ch04/define.lua`

```lua
-- A function definition is an assignment of a function value.
local function add(a, b)       -- same as: local add; add = function(a, b) ... end
  return a + b
end

local square = function(x)     -- an anonymous function stored in a local
  return x * x
end

print(add(2, 3), square(4))

-- Functions are values: store them, pass them, compare them.
local op = add
print(op(10, 20), op == add, type(op))

-- Extra arguments are dropped; missing ones are nil.
print(add(1, 2, 3))
print(pcall(add, 1))           -- pcall catches the error (Chapter 9)

-- Default values with `or`.
local function greet(name, greeting)
  greeting = greeting or "Hello"
  return greeting .. ", " .. (name or "world") .. "!"
end
print(greet())
print(greet("Ada", "Hi"))

-- A function with no return statement returns nothing (nil when you ask).
local function nothing() end
print(nothing())               -- an empty line: no values at all
print((nothing()))             -- parentheses force exactly one value: nil
```

```console
$ luajit examples/ch04/define.lua
5	16
30	true	function
3
false	examples/ch04/define.lua:3: attempt to perform arithmetic on local 'b' (a nil value)
Hello, world!
Hi, Ada!

nil
```

- **A function definition is an assignment.** `function name(...) end` stores a new function value
  in `name`, a *global* unless you add `local`. Write `local function` unless you have a reason not
  to.
- **Functions have no names**, only variables that refer to them. `function(x) ... end` alone is an
  *anonymous function* expression.
- **Parameters are locals.** Arguments fit parameters like a multiple assignment: extras are
  dropped, missing ones are `nil`. No overloading, no argument count check.
- **Defaults** use the `x = x or default` idiom ([Chapter 2](02-values-and-types.md)).
- `return` gives zero, one or many values. With no `return`, a function returns no values.

Why? One kind of function value and one way to name things (variables). Methods, callbacks, modules
and objects all reuse them instead of needing their own syntax.

## Local functions and recursion

`examples/ch04/recursion.lua`

```lua
-- `local function` makes the name visible inside the body, so it can recurse.
local function factorial(n)
  if n <= 1 then
    return 1
  end
  return n * factorial(n - 1)
end
print(factorial(5), factorial(20))

-- Mutual recursion: declare the second name first.
local is_odd
local function is_even(n)
  if n == 0 then return true end
  return is_odd(n - 1)
end
function is_odd(n)             -- assigns the local declared above
  if n == 0 then return false end
  return is_even(n - 1)
end
print(is_even(10), is_odd(7))

-- The trap: with `local f = function`, f is not in scope inside its own body.
local fib = function(n)
  if n < 2 then return n end
  return fib(n - 1) + fib(n - 2) -- this `fib` is the GLOBAL fib: nil
end
print(fib(5))
```

```console
$ luajit examples/ch04/recursion.lua
120	2.4329020081766e+18
true	true
luajit: examples/ch04/recursion.lua:25: attempt to call global 'fib' (a nil value)
stack traceback:
	examples/ch04/recursion.lua:25: in function 'fib'
	examples/ch04/recursion.lua:27: in main chunk
	[C]: at 0x5fdafeae83a0
```

`local function f` is short for `local f; f = function ... end`. The local exists *before* the
function is built, so the body can call `f`. With `local f = function ... end`, the local starts
only *after* the statement, so inside the body `f` is the global `f`.

For mutual recursion, declare the local first (`local is_odd`) and assign it later.
`function is_odd(n)` then assigns the visible local, not a global.

(`factorial(20)` is above 2^53, so the printed value is rounded; see
[Chapter 2](02-values-and-types.md).)

## Multiple results

`examples/ch04/multret.lua`

```lua
-- A function can return several values.
local function divmod(a, b)
  return math.floor(a / b), a % b
end

local q, r = divmod(17, 5)
print(q, r)

-- A call at the END of a list keeps all its values...
print(divmod(17, 5))
print("x", divmod(17, 5))
local t = { divmod(17, 5) }
print(#t)

-- ...anywhere else it is cut to its first value.
print(divmod(17, 5), "x")
local u = { divmod(17, 5), "x" }
print(#u)

-- Parentheses cut a call to exactly one value.
print((divmod(17, 5)))

-- Ignore values you don't need with _ (just a normal name, by convention).
local _, rest = divmod(17, 5)
print(rest)

-- Many library functions return several values.
print(string.find("hello world", "wor"))
```

```console
$ luajit examples/ch04/multret.lua
3	2
3	2
x	3	2
2
3	x
2
3
2
7	9
```

The truncation rule: in a list of expressions (arguments, table items, the right side of an
assignment, `return` values), **only the last call expands to all its values. Every other call is
cut to one.** A call in parentheses is always one value.

Lua uses multiple results instead of out-parameters or tuples, and you see them everywhere:
`string.find` returns start and end positions, and the `nil, message` error convention
([Chapter 9](09-errors.md)) returns two values.

## Variable arguments: `...`

A function whose parameter list ends with `...` takes any number of extra arguments.

`examples/ch04/varargs.lua`

```lua
-- `...` stands for all extra arguments.
local function count(...)
  return select("#", ...)      -- the number of arguments, nils included
end
print(count(), count(1, 2), count(nil, nil))

-- select(n, ...) returns the arguments from n on.
print(select(2, "a", "b", "c"))
print(select(-1, "a", "b", "c")) -- negative counts from the end

-- Loop over the arguments.
local function sum(...)
  local total = 0
  for i = 1, select("#", ...) do
    total = total + (select(i, ...))  -- parentheses keep one value
  end
  return total
end
print(sum(1, 2, 3, 4))

-- {...} packs them into a table; # is unreliable if there are nils.
local function pack(...)
  return { n = select("#", ...), ... }
end
local p = pack("a", nil, "c")
print(p.n, p[1], p[2], p[3])

-- unpack(t, i, j) is the opposite: table items -> separate values.
print(unpack({ 1, 2, 3 }))
print(unpack(p, 1, p.n))      -- pass n to keep trailing/middle nils

-- Pass the arguments on to another function unchanged.
-- string.format fills in the %s and %d placeholders (Chapter 6).
local function log(fmt, ...)
  print("[log] " .. string.format(fmt, ...))
end
log("%s has %d items", "cart", 3)
```

```console
$ luajit examples/ch04/varargs.lua
0	2	2
b	c
c
10
3	a	nil	c
1	2	3
a	nil	c
[log] cart has 3 items
```

| Expression | Meaning |
|------------|---------|
| `...` | all the extra arguments, as a list of values |
| `select("#", ...)` | how many there are, counting `nil`s |
| `select(i, ...)` | argument `i` and all after it; wrap in `()` for just one |
| `{...}` | a table of them (a `nil` makes a hole, so `#` may be wrong) |
| `unpack(t, i, j)` | items `t[i]`..`t[j]` as separate values (`i` defaults to 1, `j` to `#t`) |

Notes:

- `...` is not a table. It is a list of values, like a multiple return.
- In Lua 5.1 and LuaJIT, `unpack` is a global. Lua 5.2+ moved it to `table.unpack`.
- `select("#", ...)` is the only reliable count. A `nil` among the values makes `#{...}` unreliable
  ([Chapter 5](05-tables.md) explains why).
- `select(i, ...)` in a loop costs O(n) per call. For many arguments, pack them into a table once.
- **The main chunk is a vararg function too.** A script's `...` holds its command-line arguments,
  the same values as `arg[1]`, `arg[2]`, ... The project below uses this.

## Closures and upvalues

A function defined inside another can use the outer function's locals, and keeps them alive after
the outer function returns. Such a function is a **closure**; the captured locals are its
**upvalues**.

`examples/ch04/closures.lua`

```lua
-- A closure is a function plus the local variables it uses from outside.
local function make_counter()
  local n = 0                  -- an upvalue of the function below
  return function()
    n = n + 1
    return n
  end
end

local c1 = make_counter()
local c2 = make_counter()      -- a separate n
print(c1(), c1(), c1(), c2())

-- Two closures created together share the same upvalue.
local function make_account(balance)
  local function deposit(x) balance = balance + x end
  local function get() return balance end
  return deposit, get
end
local deposit, get = make_account(100)
deposit(50)
print(get())

-- Each loop pass has a fresh loop variable, so each closure keeps its own i.
local fns = {}
for i = 1, 3 do
  fns[i] = function() return i end
end
print(fns[1](), fns[2](), fns[3]())
```

```console
$ luajit examples/ch04/closures.lua
1	2	3	1
150
1	2	3
```

- Each call of `make_counter` creates a new `n` and a new closure around it. `c1` and `c2` share
  nothing.
- Closures capture **variables, not values**. `deposit` and `get` see the same `balance`, so a
  change by one shows in the other.
- A `for` loop makes a fresh loop variable for each pass, so the three closures return 1, 2, 3.
  (In JavaScript with `var`, all three would see the loop variable's final value.)

Closures are Lua's way to keep private state: nothing outside the function can reach its upvalues.
You will use them for counters, callbacks, iterators ([Chapter 11](11-coroutines.md)) and objects
without metatables.

## Proper tail calls

A call of the form `return f(args)` is a **tail call**. Lua drops the caller's stack frame and the
called function takes its place, so a chain of tail calls never runs out of stack.

`examples/ch04/tailcall.lua`

```lua
-- `return f(x)` is a proper tail call: it reuses the caller's stack frame.
local function count_down(n)
  if n == 0 then
    return "done"
  end
  return count_down(n - 1)     -- tail call: no stack growth
end
print(count_down(10000000))

-- Not a tail call: the `1 +` must run after f returns, so frames pile up.
local function depth(n)
  if n == 0 then
    return 0
  end
  return 1 + depth(n - 1)
end
print(depth(10000))
print(pcall(depth, 10000000))
```

```console
$ luajit examples/ch04/tailcall.lua
done
10000
false	examples/ch04/tailcall.lua:12: stack overflow
```

Only the exact form `return f(args)` is a tail call. These are **not**:

- `return 1 + f(x)`: the addition runs after the call.
- `return (f(x))`: the parentheses cut the results after the call.
- `f(x); return`: the return runs after the call.
- `return x, f(x)`: the call is part of a list.

Normal recursion runs out of stack after tens of thousands of calls (here 10,000 deep is fine, 10
million is not). Tail calls also suit "go to the next state" code: a function ending in
`return other_function(...)` hands over control without growing the stack. The `stash` dispatcher
below does this.

## Named arguments with a table

Lua has no keyword arguments. Instead, pass one table and read its fields. Two bits of call syntax
help:

- `f{...}` is short for `f({...})`.
- `f"text"` is short for `f("text")`.

`examples/ch04/named.lua`

```lua
-- Lua has no keyword arguments. Pass one table instead.
local function box(opts)
  local width = opts.width or 10
  local char = opts.char or "*"
  local title = opts.title or ""
  return title .. string.rep(char, width)
end

-- f{...} is short for f({...}), and f"..." for f("...").
print(box{ width = 5 })
print(box{ char = "=", title = "> ", width = 3 })
print(box{})

local function shout(s) return s:upper() .. "!" end
print(shout"hey")
```

```console
$ luajit examples/ch04/named.lua
*****
> ===
**********
HEY!
```

Tables come in [Chapter 5](05-tables.md). For now: `{ width = 5 }` builds a table with a field
`width`, and `opts.width` reads it (`nil` if missing). The call site is easy to read and every
argument is optional. Much Lua code passes options this way, and so do `stash`'s commands from
Chapter 5 on.

## Method call syntax `:` (preview)

`obj:name(args)` is short for `obj.name(obj, args)`: the object goes in as a hidden first argument.
Defining `function obj:name(args)` adds a hidden first parameter named `self`.

`examples/ch04/methods.lua`

```lua
-- obj:name(args) is short for obj.name(obj, args).
local account = { balance = 100 }

function account.deposit(self, amount)
  self.balance = self.balance + amount
end

function account:withdraw(amount) -- same as account.withdraw(self, amount)
  self.balance = self.balance - amount
end

account.deposit(account, 50)
account:deposit(50)              -- the same call, shorter
account:withdraw(30)
print(account.balance)

-- Strings have methods too (Chapter 6).
local s = "lua"
print(s:upper(), s:rep(3, "-"), ("x"):rep(4))
```

```console
$ luajit examples/ch04/methods.lua
170
LUA	lua-lua-lua	xxxx
```

`:` is only syntax. `self` is special only because `:` creates it. Mixing up `.` and `:` is a common
bug: `account.withdraw(30)` passes `30` as `self` and fails with
`attempt to index local 'self' (a number value)`. [Chapter 7](07-metatables-and-objects.md) builds
classes on this.

## Higher-order functions

A function that takes or returns functions is *higher-order*. The standard library has few
(`table.sort` takes a comparator, `string.gsub` can take a function), but they are easy to write.

`examples/ch04/higher.lua`

```lua
-- Higher-order functions take or return functions.
local function map(list, f)
  local out = {}
  for i, v in ipairs(list) do
    out[i] = f(v)
  end
  return out
end

local function filter(list, keep)
  local out = {}
  for _, v in ipairs(list) do
    if keep(v) then
      out[#out + 1] = v
    end
  end
  return out
end

local function reduce(list, f, acc)
  for _, v in ipairs(list) do
    acc = f(acc, v)
  end
  return acc
end

local function compose(f, g)
  return function(...) return f(g(...)) end
end

local nums = { 1, 2, 3, 4, 5, 6 }
local squares = map(nums, function(x) return x * x end)
local evens = filter(squares, function(x) return x % 2 == 0 end)
print(unpack(squares))
print(unpack(evens))
print(reduce(nums, function(a, b) return a + b end, 0))

local inc_then_double = compose(function(x) return x * 2 end,
                                function(x) return x + 1 end)
print(inc_then_double(5))
```

```console
$ luajit examples/ch04/higher.lua
1	4	9	16	25	36
4	16	36
21
12
```

`out[#out + 1] = v` appends to an array ([Chapter 5](05-tables.md)). `compose` passes `...` straight
through, so it works for functions of any number of arguments.

## Building stash: commands as functions

The `if` chain in `stash.lua` is getting long. Now each command gets its own function, and a small
`run` function dispatches to them. `stash` uses everything from this chapter:

| Piece | Concept |
|-------|---------|
| `fail(...)` | varargs: builds a message from any number of parts with `select` |
| `counter(start)` / `next_id` | a closure that hands out ids 1, 2, 3, ... |
| `not_yet(name)` | a higher-order function: returns a handler for an unwritten command |
| `cmd_add(url, ...)` | a named parameter plus varargs |
| `scan(...)` | returns four values |
| `run(...)` | dispatches with tail calls: `return cmd_add(select(position + 1, ...))` |
| `run(...)` at the bottom | the main chunk's own `...` holds the command-line arguments |

Nothing is stored yet; that needs tables (Chapter 5). `add` hands out an id and reports how many
extra arguments it got, only to show varargs at work.

Replace `stash.lua` with this. `VERSION` and `USAGE` are the same as in Chapter 3.

`stash.lua`

```lua
#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 4: every command is a function.

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

-- Print an error message built from any number of parts.
local function fail(...)
  local message = "stash:"
  for i = 1, select("#", ...) do
    -- select(i, ...) returns ALL values from i on; the parentheses keep one.
    message = message .. " " .. tostring((select(i, ...)))
  end
  print(message)
end

-- A closure: each call of the returned function bumps the captured `n`.
local function counter(start)
  local n = start - 1
  return function()
    n = n + 1
    return n
  end
end

local next_id = counter(1)

-- A higher-order helper: builds a handler for a command we have not written yet.
local function not_yet(name)
  return function()
    fail("'" .. name .. "' is not implemented yet")
  end
end

local function cmd_help()
  print(USAGE)
end

local function cmd_version()
  print("stash " .. VERSION)
end

local function cmd_add(url, ...)
  if url == nil then
    return fail("add: missing URL")
  end
  -- Nothing is stored yet (tables arrive in Chapter 5).
  print("added " .. next_id() .. ": " .. url .. " (" .. select("#", ...) .. " extra arguments)")
end

local function cmd_show(id)
  if tonumber(id) == nil then
    return fail("show: ID must be a number, got", id)
  end
  fail("'show' is not implemented yet")
end

local cmd_list = not_yet("list")
local cmd_search = not_yet("search")
local cmd_rm = not_yet("rm")

-- Scan the arguments. Returns four values: the command, its position,
-- and whether -h/--help or --version appeared anywhere.
local function scan(...)
  local command, position
  local want_help, want_version = false, false
  for i = 1, select("#", ...) do
    local a = select(i, ...)
    if a == "-h" or a == "--help" then
      want_help = true
    elseif a == "--version" then
      want_version = true
    elseif command == nil then
      command, position = a, i
    end
  end
  return command, position, want_help, want_version
end

local function run(...)
  local command, position, want_help, want_version = scan(...)
  if want_help or command == "help" then
    return cmd_help()
  elseif want_version or command == "version" then
    return cmd_version()
  elseif command == nil then
    return cmd_help()
  end

  -- The arguments after the command go to its handler. `return f(...)`
  -- is a proper tail call: run's stack frame is reused.
  if command == "add" then
    return cmd_add(select(position + 1, ...))
  elseif command == "list" then
    return cmd_list(select(position + 1, ...))
  elseif command == "search" then
    return cmd_search(select(position + 1, ...))
  elseif command == "show" then
    return cmd_show(select(position + 1, ...))
  elseif command == "rm" then
    return cmd_rm(select(position + 1, ...))
  end
  return fail("unknown command '" .. command .. "' (try 'stash help')")
end

-- The main chunk receives the command-line arguments as `...` too.
run(...)
```

Things to notice:

- **`fail` with varargs.** `fail("show: ID must be a number, got", id)` joins its parts with spaces.
  `tostring` makes `nil` and numbers safe to join.
- **`select(position + 1, ...)`** passes every argument after the command name to the handler. In
  `scan`, `local a = select(i, ...)` keeps only the first value: a one-name local list drops the
  rest.
- **`scan` no longer needs `goto`.** In one `if`/`elseif` chain, each argument matches at most one
  branch.
- **`return fail(...)`** reports the error and stops the handler in one line. `fail` returns
  nothing, so the handler returns nothing too.
- **`cmd_list`, `cmd_search` and `cmd_rm`** come from `not_yet`. Each is a closure holding its own
  `name`.
- `-t lua` after the URL counts as two extra arguments for now. Chapter 5 parses options properly.

### Checkpoint

```console
$ luajit stash.lua add https://www.lua.org/ -t lua
added 1: https://www.lua.org/ (2 extra arguments)
$ luajit stash.lua add
stash: add: missing URL
$ luajit stash.lua show abc
stash: show: ID must be a number, got abc
$ luajit stash.lua list
stash: 'list' is not implemented yet
$ luajit stash.lua --version
stash 0.1.0
```

The id is always 1: each run is a new process, so `next_id` starts over. Saving data between runs
comes in [Chapter 12](12-io-and-os.md).

The complete project at this point is in `project/ch04/`.

## Summary

- `local function f(...) end` defines a function that can call itself. `local f = function` can't.
- Functions are values: assign, pass, return and compare them.
- Missing arguments are `nil`, extra ones are dropped. Defaults: `x = x or default`.
- Only the last call in a list expands to all its results. `(f())` gives exactly one.
- `...` is the vararg list. Count it with `select("#", ...)`, not `#{...}`. `unpack` undoes `{...}`.
- Closures capture variables (upvalues), not copies. Each loop pass gets a fresh loop variable.
- `return f(x)` is a proper tail call and uses no stack. `return 1 + f(x)` is not.
- `f{...}` passes named arguments in a table. `obj:m(x)` means `obj.m(obj, x)`.

## Exercises

1. Write `max(...)` that returns the largest argument **and** its position, or `nil` with no
   arguments. `max(3, 9, 4)` should return `9, 2`.

<details><summary>Solution</summary>

```lua
local function max(...)
  local n = select("#", ...)
  if n == 0 then
    return nil
  end
  local best, at = (select(1, ...)), 1
  for i = 2, n do
    local v = (select(i, ...))
    if v > best then
      best, at = v, i
    end
  end
  return best, at
end

print(max(3, 9, 4))
print(max(-1))
print(max())
```

```console
$ luajit max.lua
9	2
-1	1
nil
```

</details>

2. Extend `make_counter` to take a `step` (default 1) and return two functions, `next_value` and
   `reset`, that work on the same count.

<details><summary>Solution</summary>

```lua
local function make_counter(step)
  step = step or 1
  local n = 0
  local function next_value()
    n = n + step
    return n
  end
  local function reset()
    n = 0
  end
  return next_value, reset
end

local next_value, reset = make_counter(5)
print(next_value(), next_value())
reset()
print(next_value())
```

```console
$ luajit counter.lua
5	10
5
```

Both closures capture the same `n`, so `reset` affects `next_value`.

</details>

3. Write `partial(f, first)` that returns a new function. Calling it with any arguments calls `f`
   with `first` and then those arguments. Test it with `print`.

<details><summary>Solution</summary>

```lua
local function partial(f, first)
  return function(...)
    return f(first, ...)
  end
end

local function add3(a, b, c) return a + b + c end
local add10 = partial(add3, 10)
print(add10(1, 2))
local hello = partial(print, "hello:")
hello("a", "b")
```

```console
$ luajit partial.lua
13
hello:	a	b
```

`return f(first, ...)` is a tail call, and `...` passes every argument through, `nil`s included.

</details>

4. In `stash.lua`, give `search` its own handler that requires a term: `stash search` should print
   `stash: search: missing TERM`; with a term it still says "not implemented yet".

<details><summary>Solution</summary>

Replace the `cmd_search` line with a function. It must be defined before `run`:

```lua
local function cmd_search(term)
  if term == nil then
    return fail("search: missing TERM")
  end
  fail("'search' is not implemented yet")
end

local cmd_list = not_yet("list")
local cmd_rm = not_yet("rm")
```

```console
$ luajit stash.lua search
stash: search: missing TERM
$ luajit stash.lua search lua
stash: 'search' is not implemented yet
```

</details>

5. Which of these are tail calls? `return f(x)`, `return (f(x))`, `return f(x) or 0`,
   `return g(f(x))`, `return x.method(x)`.

<details><summary>Solution</summary>

- `return f(x)`: yes.
- `return (f(x))`: no. The parentheses trim the results after `f` returns.
- `return f(x) or 0`: no. The `or` runs after `f` returns.
- `return g(f(x))`: yes for `g`. `f(x)` is an ordinary call, but the last thing done is calling `g`.
- `return x.method(x)`: yes. Any call expression counts, field and method calls included.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-4--functions)
