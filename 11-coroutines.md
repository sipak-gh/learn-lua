# Chapter 11 — Coroutines

A coroutine is a function that can pause, hand a value back, and later continue where it stopped.
That one idea gives you generators, custom iterators, lazy pipelines, and cooperative multitasking.
Lua needs no keyword, threads, or async runtime for it, just the small `coroutine` library. You'll
learn that library, how the generic `for` really works, and how to chain pipelines. Then `stash`
gets streaming iterators: `store:entries()` and an `iter` module that `list` and `search` use.

Previous: [Chapter 10 — Testing](10-testing.md). Next: [Chapter 12 — I/O and the OS](12-io-and-os.md).

## Create, resume, yield

- `coroutine.create(fn)` makes a coroutine. It doesn't run it yet.
- `coroutine.resume(co)` runs it until it calls `coroutine.yield()` or returns.
- The next `resume` continues right after that `yield`.

`examples/ch11/basics.lua`

```lua
-- A coroutine is a function that can pause (yield) and continue later (resume).

local co = coroutine.create(function()
  print("  step 1")
  coroutine.yield()                          -- pause here
  print("  step 2")
  coroutine.yield()
  print("  step 3")
end)

print(type(co), coroutine.status(co))
print("resume:", coroutine.resume(co))
print(coroutine.status(co))
print("resume:", coroutine.resume(co))
print("resume:", coroutine.resume(co))
print(coroutine.status(co))
print("resume:", coroutine.resume(co))     -- nothing left to run
```

```console
$ luajit examples/ch11/basics.lua
thread	suspended
  step 1
resume:	true
suspended
  step 2
resume:	true
  step 3
resume:	true
dead
resume:	false	cannot resume dead coroutine
```

- A coroutine's type is `thread`, but it is not an OS thread. It is a separate Lua stack.
- `resume` returns `true` (plus any values), or `false` and an error message. It never raises an
  error itself.
- `coroutine.status(co)` is one of:

| status | meaning |
|---|---|
| `suspended` | created but not started, or stopped at a `yield` |
| `running` | it is running right now |
| `normal` | it resumed another coroutine and waits for it |
| `dead` | it returned or raised an error; it can't be resumed |

**Why not threads?** Only one coroutine runs at a time, until it yields. Nothing interrupts it
between two statements, so you need no locks. Coroutines need no OS support either, so they work
everywhere Lua runs, which fits Lua's small, portable core. The cost: no parallelism.

Lua's coroutines are *asymmetric*: `yield` always returns to whoever called `resume`. You can't
jump from one coroutine straight to another.

## Passing values in and out

Values flow both ways:

- The first `resume(co, ...)` passes its extra arguments as the function's parameters.
- `yield(...)` hands its arguments out as the results of that `resume`.
- The next `resume(co, ...)` passes its arguments in as the results of that `yield`.
- The function's return values become the results of the last `resume`.

`examples/ch11/exchange.lua`

```lua
-- Values flow both ways: resume's extra arguments come out of yield,
-- and yield's arguments come out of resume.

local co = coroutine.create(function(a, b)   -- first resume: the parameters
  print("  got", a, b)
  local c = coroutine.yield(a + b)           -- hand a + b out, wait for c
  print("  got", c)
  local d, e = coroutine.yield(c * 2)
  print("  got", d, e)
  return "done", d .. e                      -- return values end it
end)

print("out:", coroutine.resume(co, 1, 2))
print("out:", coroutine.resume(co, 10))
print("out:", coroutine.resume(co, "x", "y"))
print(coroutine.status(co))
```

```console
$ luajit examples/ch11/exchange.lua
  got	1	2
out:	true	3
  got	10
out:	true	20
  got	x	y
out:	true	done	xy
dead
```

## coroutine.wrap

Usually you don't need the coroutine object. `coroutine.wrap(fn)` returns a plain function instead.
Each call resumes the coroutine and returns what `yield` passed, without the leading `true`.

`examples/ch11/wrap.lua`

```lua
-- coroutine.wrap returns a plain function. Each call resumes the
-- coroutine; it returns what yield passed, without the true/false flag.

local next_square = coroutine.wrap(function()
  for i = 1, 3 do
    coroutine.yield(i * i)
  end
end)

print(next_square())
print(next_square())
print(next_square())
print(next_square())                         -- the function returns: no values
print(pcall(next_square))                    -- dead now: calling it raises an error
```

```console
$ luajit examples/ch11/wrap.lua
1
4
9

false	cannot resume dead coroutine
```

| | `coroutine.create` + `resume` | `coroutine.wrap` |
|---|---|---|
| you get | a `thread` object | a function |
| errors | returned: `false, message` | raised in the caller |
| status | `coroutine.status(co)` | not available |
| use it for | schedulers, anything that inspects coroutines | generators and iterators |

## Where am I? running and isyieldable

- `coroutine.running()` returns the running coroutine, or `nil` in the main program.
- `coroutine.isyieldable()` (from Lua 5.3, added by LuaJIT) says whether `yield` is allowed here.

`examples/ch11/running.lua`

```lua
-- coroutine.running() is the coroutine that runs this code; nil in the
-- main program. coroutine.isyieldable() says whether yield is allowed.

print("main:", coroutine.running(), coroutine.isyieldable())

local co
co = coroutine.create(function()
  print("inside:", coroutine.running() == co, coroutine.isyieldable())
  print("status of itself:", coroutine.status(co))
end)
coroutine.resume(co)

-- A coroutine that resumes another one is "normal" while the other runs.
local outer
outer = coroutine.create(function()
  local inner = coroutine.create(function()
    print("outer is", coroutine.status(outer))
  end)
  coroutine.resume(inner)
end)
coroutine.resume(outer)
```

```console
$ luajit examples/ch11/running.lua
main:	nil	false
inside:	true	true
status of itself:	running
outer is	normal
```

In the main program, Lua 5.2+ `running()` returns the main coroutine plus `true`. LuaJIT keeps the
5.1 behavior: one result, `nil`.

## How the generic for works

You've used `for i, v in ipairs(t)` since [Chapter 3](03-control-flow.md). The expression after `in`
is evaluated once and gives three values:

1. `f`: the iterator function,
2. `s`: an invariant state,
3. `ctl`: the control variable's start value.

The loop then calls `f(s, ctl)` over and over. The first result becomes the next `ctl`. The loop
stops when that first result is `nil`.

`examples/ch11/forloop.lua`

```lua
-- The generic for calls an iterator function until it returns nil.
--   for k, v in explist do body end
-- evaluates explist once to get three values: f, s (state), ctl (control),
-- then loops:  k, v = f(s, ctl); if k == nil then break end; ctl = k; body

local t = { "a", "b", "c" }

print(ipairs(t))                             -- the triplet: function, table, 0

-- The same loop, written by hand.
local f, s, ctl = ipairs(t)
while true do
  local i, v = f(s, ctl)
  if i == nil then
    break
  end
  ctl = i
  print(i, v)
end
```

```console
$ luajit examples/ch11/forloop.lua
function: builtin#6	table: 0x7053fefea588	0
1	a
2	b
3	c
```

(The table address differs on every run.) Since `nil` ends the loop, an iterator can't produce `nil`
as its first value. That's also why `ipairs` stops at the first hole.

With this protocol you can write three kinds of iterators.

### Stateless iterators

A *stateless* iterator keeps nothing of its own: everything comes in as `(s, ctl)`. `ipairs` and
`pairs` (via `next`) work this way. One function serves many loops at once, with no closure per loop.

`examples/ch11/stateless.lua`

```lua
-- A stateless iterator keeps no state of its own: everything it needs
-- comes in as (s, ctl). ipairs and pairs work this way.

-- Counts from ctl+1 up to s, stepping by 1.
local function upto_step(limit, i)
  i = i + 1
  if i <= limit then
    return i
  end
end

local function upto(limit)
  return upto_step, limit, 0
end

for i in upto(3) do
  io.write(i, " ")
end
print()

-- Every second element of an array: the control variable is the index.
local function every_other_step(t, i)
  i = i + 2
  if t[i] ~= nil then
    return i, t[i]
  end
end

local function every_other(t)
  return every_other_step, t, -1             -- the first index is -1 + 2 = 1
end

for i, v in every_other({ "a", "b", "c", "d", "e" }) do
  io.write(i, "=", v, " ")
end
print()
```

```console
$ luajit examples/ch11/stateless.lua
1 2 3 
1=a 3=c 5=e 
```

(`io.write` prints without a newline. [Chapter 12](12-io-and-os.md) covers it.)

### Stateful iterators: closures

When the state is more than one value, keep it in upvalues ([Chapter 4](04-functions.md)). The loop
then needs only the function; `s` and `ctl` are `nil` and ignored.

`examples/ch11/closures.lua`

```lua
-- A stateful iterator keeps its state in upvalues. The for loop only
-- needs the function; s and ctl are unused.

local function words(s)
  local pos = 1
  return function()
    local first, last = s:find("%a+", pos)
    if first == nil then
      return nil
    end
    pos = last + 1
    return s:sub(first, last)
  end
end

for w in words("one, two;  three") do
  print(w)
end

-- The iterator is an ordinary function: you can call it by hand, too.
local it = words("call me")
print(it(), it(), it())
```

```console
$ luajit examples/ch11/closures.lua
one
two
three
call	me	nil
```

### Generators: coroutines as iterators

A `coroutine.wrap` function returns one value per call and nothing at the end, which is exactly what
`for` wants. So any loop that *yields* values becomes an iterator.

This helps when the state is hard to keep by hand. A recursive tree walk keeps its position in the
call stack. A closure would need its own explicit stack. A coroutine just yields from any depth:

`examples/ch11/generator.lua`

```lua
-- A generator: a coroutine that yields values one by one. Recursive
-- walks are where they shine: the recursion keeps the state for you.

local tree = {
  value = "root",
  { value = "a", { value = "a1" }, { value = "a2" } },
  { value = "b", { value = "b1" } },
}

-- Depth-first walk; yields each node's value and its depth.
local function walk(node, depth)
  coroutine.yield(node.value, depth)
  for _, child in ipairs(node) do
    walk(child, depth + 1)                   -- yields from deep inside work too
  end
end

local function nodes(root)
  return coroutine.wrap(function() walk(root, 0) end)
end

for value, depth in nodes(tree) do
  print(("  "):rep(depth) .. value)
end

-- All permutations of an array, generated in place (no lists of lists).
local function permute(a, n)
  if n <= 1 then
    coroutine.yield(a)
    return
  end
  for i = 1, n do
    a[n], a[i] = a[i], a[n]
    permute(a, n - 1)
    a[n], a[i] = a[i], a[n]
  end
end

for p in coroutine.wrap(function() permute({ "x", "y", "z" }, 3) end) do
  io.write(table.concat(p), " ")
end
print()
```

```console
$ luajit examples/ch11/generator.lua
root
  a
    a1
    a2
  b
    b1
yzx zyx zxy xzy yxz xyz
```

- `yield` works at any call depth. Every level of `walk` yields straight to the `for` loop.
- `permute` yields the *same* table each time, changed in place. That's fast, but use the value
  before asking for the next one, or copy it.

**Gotcha: return values leak into the loop.** What the function *returns* also comes out of the
wrapped function. The `for` loop sees one extra element, then calls a dead coroutine:

`examples/ch11/wrap_return.lua`

```lua
-- Gotcha: a generator's *return* values also come out of the wrapped
-- function. In a for loop they look like one more element, and the
-- next call hits a dead coroutine.

local gen = coroutine.wrap(function()
  coroutine.yield(1)
  coroutine.yield(2)
  return "oops"                              -- should be a plain `return`
end)

for v in gen do
  print(v)
end
```

```console
$ luajit examples/ch11/wrap_return.lua
1
2
oops
luajit: examples/ch11/wrap_return.lua:11: cannot resume dead coroutine
stack traceback:
	[C]: in function '(for generator)'
	examples/ch11/wrap_return.lua:11: in main chunk
	[C]: at 0x5c45fb94f3a0
```

A generator must end by returning nothing.

### Which kind to choose

A coroutine switch costs more than a function call. This pulls ten million numbers through each kind:

`examples/ch11/cost.lua`

```lua
-- Coroutines are cheap, but a switch costs more than a function call.
-- Timings vary by machine; compare the two numbers, not the values.

local N = 1e7

local function closure_iter(n)
  local i = 0
  return function()
    i = i + 1
    if i <= n then
      return i
    end
  end
end

local function coroutine_iter(n)
  return coroutine.wrap(function()
    for i = 1, n do
      coroutine.yield(i)
    end
  end)
end

for _, case in ipairs({ { "closure", closure_iter }, { "coroutine", coroutine_iter } }) do
  local start, sum = os.clock(), 0
  for i in case[2](N) do
    sum = sum + i
  end
  print(("%-9s %6.0f ms  (sum %.0f)"):format(case[1], (os.clock() - start) * 1000, sum))
end
```

```console
$ luajit examples/ch11/cost.lua
closure        5 ms  (sum 50000005000000)
coroutine    289 ms  (sum 50000005000000)
```

Your timings will differ; the ratio is the point. LuaJIT compiles the closure loop to tight machine
code. It can't compile the coroutine switch, so every `resume` and `yield` leaves compiled code
([Chapter 18](18-performance-and-the-jit.md) explains the JIT). Still, about 30 nanoseconds per value
is nothing for a list of bookmarks. Rules of thumb:

- Simple position (an index, an offset): stateless iterator or closure.
- Complex state (recursion, nested loops): coroutine. The code stays a plain loop.
- Hot inner loop over millions of items: avoid coroutines.

## Pipelines: producer, filters, consumer

Generators combine. A *filter* is a coroutine that pulls values from one iterator and yields some of
them, maybe changed. Chain a few for a pipeline, like `cat | grep | nl` in a shell:

`examples/ch11/pipeline.lua`

```lua
-- Producer -> filters -> consumer. Each stage is a coroutine that pulls
-- values from the stage before it. Nothing runs until the consumer asks.

local function producer(lines)
  return coroutine.wrap(function()
    for _, line in ipairs(lines) do
      print("  (produce " .. line .. ")")
      coroutine.yield(line)
    end
  end)
end

local function grep(pattern, source)
  return coroutine.wrap(function()
    for line in source do
      if line:find(pattern) then
        coroutine.yield(line)
      end
    end
  end)
end

local function number(source)
  return coroutine.wrap(function()
    local n = 0
    for line in source do
      n = n + 1
      coroutine.yield(("%d: %s"):format(n, line))
    end
  end)
end

local input = { "apple pie", "banana", "apple tart", "cherry" }
for line in number(grep("^apple", producer(input))) do
  print(line)                                -- the consumer
end
```

```console
$ luajit examples/ch11/pipeline.lua
  (produce apple pie)
1: apple pie
  (produce banana)
  (produce apple tart)
2: apple tart
  (produce cherry)
```

The output shows how a pipeline runs:

- **Lazy.** The consumer pulls. Each value passes through every stage before the next is produced.
  Only one item is "in flight", so huge inputs need constant memory.
- **Each stage is a plain loop.** `grep` reads like a filter over a list and doesn't know its input
  is computed on demand.
- **Stopping early is free.** If the consumer `break`s, upstream coroutines stay suspended and are
  garbage-collected later. No cleanup code.

This is the *pull* style: consumers drive producers. In a *push* pipeline, the producer `resume`s a
consumer coroutine and sends values in. Pull fits Lua's `for` loop, so `stash` uses it.

## Errors inside coroutines

An error stops a coroutine and makes it `dead`. What you see depends on how you resumed it:

- `coroutine.resume` catches the error, like `pcall`, and returns `false, message`.
- A `wrap` function raises the error again in the caller.

`examples/ch11/errors.lua`

```lua
-- An error inside a coroutine stops it. resume catches the error like
-- pcall does; wrap raises it again in the caller.

local co = coroutine.create(function()
  coroutine.yield("first")
  error("something broke")
end)

print(coroutine.resume(co))
print(coroutine.resume(co))
print(coroutine.status(co))                  -- an error kills the coroutine

-- The coroutine's stack survives the error: debug.traceback can show it.
local bad = coroutine.create(function()
  local function inner() error("deep error") end
  inner()
end)
local _, err = coroutine.resume(bad)
print(debug.traceback(bad, err))

-- wrap: the error comes out of the call, so pcall or let it propagate.
local gen = coroutine.wrap(function() error({ code = 42 }) end)
local ok2, e = pcall(gen)
print(ok2, type(e), e.code)                  -- error values pass through unchanged

-- LuaJIT can yield across pcall (Lua 5.1 cannot).
local guarded = coroutine.wrap(function()
  local ok3, v = pcall(function()
    local got = coroutine.yield("yielded inside pcall")
    error("failed after resume with " .. got)
  end)
  coroutine.yield(ok3, v)
end)
print(guarded())
print(guarded("hello"))

-- Yielding where no coroutine is running is an error.
print(pcall(coroutine.yield))
```

```console
$ luajit examples/ch11/errors.lua
true	first
false	examples/ch11/errors.lua:6: something broke
dead
examples/ch11/errors.lua:15: deep error
stack traceback:
	[C]: in function 'error'
	examples/ch11/errors.lua:15: in function 'inner'
	examples/ch11/errors.lua:16: in function <examples/ch11/errors.lua:14>
false	table	42
yielded inside pcall
false	examples/ch11/errors.lua:30: failed after resume with hello
false	attempt to yield across C-call boundary
```

Points to remember:

- **Tracebacks.** `debug.traceback()` in the caller shows the *caller's* stack. Pass the coroutine
  instead: `debug.traceback(co, msg)` shows where it died. A dead coroutine keeps its stack, so this
  works.
- **Error values pass through unchanged.** Tables stay tables, so `stash`'s error objects
  ([Chapter 9](09-errors.md)) survive a pipeline.
- **Yield across pcall.** PUC Lua 5.1 can't yield inside `pcall`, a metamethod, or an iterator
  called by C. LuaJIT's VM is *fully resumable*, so all of these work. The `pcall` still catches
  errors after the coroutine resumes.
- **Yield outside a coroutine.** The main program has nothing to yield to. LuaJIT's message for this,
  `attempt to yield across C-call boundary`, is confusing.

## Cooperative scheduling

Coroutines can run several tasks "at once" in one thread. Each task yields when it wants to wait, and
a scheduler loop picks who runs next. Event loops such as OpenResty's work this way. Here is a tiny
scheduler with a fake clock, so the output never changes:

`examples/ch11/scheduler.lua`

```lua
-- Cooperative multitasking: a scheduler runs tasks in turns. A task runs
-- until it yields; nothing interrupts it. The clock here is a counter,
-- so the output is the same on every run.

local tasks = {}                             -- { co = coroutine, wake = tick }
local now = 0

local function spawn(name, fn)
  tasks[#tasks + 1] = { name = name, co = coroutine.create(fn), wake = 0 }
end

-- Called from inside a task: give up control for `ticks` ticks.
local function sleep(ticks)
  coroutine.yield(ticks)
end

local function run()
  while #tasks > 0 do
    local i = 1
    while i <= #tasks do
      local t = tasks[i]
      local finished = false
      if t.wake <= now then
        local ok, result = coroutine.resume(t.co)  -- result: ticks, or an error
        if not ok then
          print(("[%d] %s failed: %s"):format(now, t.name, result))
        end
        finished = coroutine.status(t.co) == "dead"
        if not finished then
          t.wake = now + result
        end
      end
      if finished then
        table.remove(tasks, i)               -- the next task moves into slot i
      else
        i = i + 1
      end
    end
    now = now + 1
  end
end

spawn("ping", function()
  for i = 1, 3 do
    print(("[%d] ping %d"):format(now, i))
    sleep(2)
  end
end)

spawn("pong", function()
  for i = 1, 2 do
    print(("[%d] pong %d"):format(now, i))
    sleep(3)
  end
  error("pong gives up")
end)

run()
print("all tasks finished at tick " .. now)
```

```console
$ luajit examples/ch11/scheduler.lua
[0] ping 1
[0] pong 1
[2] ping 2
[3] pong 2
[4] ping 3
[6] pong failed: examples/ch11/scheduler.lua:55: pong gives up
all tasks finished at tick 7
```

- Each task is straight-line code: print, sleep, repeat. The suspended coroutine holds its state
  between turns.
- `sleep` is an ordinary function that yields. Any function a task calls can yield for it.
- One task's error doesn't stop the others. `resume` catches it; the scheduler reports it.
- **Cooperative** means a task that never yields blocks everyone. A real event loop also waits for
  I/O (`poll`/`epoll`, via the FFI from [Chapter 13](13-ffi-basics.md) on). The coroutine part stays
  this simple.

## Building stash: streaming iterators

So far `MemoryStore` built a sorted array of all entries (`sorted()`) for every `list`, `search` and
`tags`, then filtered it. Now the store gets one iterator, `entries()`, and the commands become
pipelines over it. Two wins:

- `list --limit 5` stops pulling after five matches instead of filtering everything first.
- `export` streams entries to JSON one at a time ([Chapter 12](12-io-and-os.md)). In
  [Chapter 15](15-wrapping-sqlite.md), `entries()` iterates over database rows and the commands
  don't change.

The data is still the built-in in-memory sample; changes vanish when `stash` exits. Files arrive in
the next chapter.

### src/stash/iter.lua (new)

Generic pipeline stages. Each takes an iterator and returns one, so they nest:
`iter.take(3, iter.filter(pred, it))`.

```lua
-- Iterator pipelines. An iterator here is a function that returns the
-- next value on each call and nil at the end, so it works in a generic
-- for:  for v in it do ... end
--
-- coroutine.wrap turns a loop that *yields* values into such a function.
-- That lets each stage be written as a plain loop.

local M = {}

-- Iterates over the values of an array.
function M.values(array)
  return coroutine.wrap(function()
    for _, v in ipairs(array) do
      coroutine.yield(v)
    end
  end)
end

-- Passes on the values for which pred(value) is true.
function M.filter(pred, it)
  return coroutine.wrap(function()
    for v in it do
      if pred(v) then
        coroutine.yield(v)
      end
    end
  end)
end

-- Passes on at most n values, then stops pulling from `it`.
function M.take(n, it)
  return coroutine.wrap(function()
    if n <= 0 then
      return
    end
    local count = 0
    for v in it do
      coroutine.yield(v)
      count = count + 1
      if count == n then
        return
      end
    end
  end)
end

-- Drains an iterator into an array.
function M.collect(it)
  local result = {}
  for v in it do
    result[#result + 1] = v
  end
  return result
end

return M
```

Details that matter:

- `take` checks `count == n` *right after* yielding. Checking before the next pull would pull one
  value too many: wasted work, and an extra row read for a database cursor. A test checks this.
- `take(0, it)` returns without touching `it`.
- Stages end with a bare `return`, so the [wrap_return.lua](#generators-coroutines-as-iterators)
  gotcha can't happen.
- Iterators are single-value (`for v in it`). Entries are tables, so one value is enough.

### src/stash/memstore.lua

`entries()` replaces `sorted()`, and `list`, `search` and `tags` use it. The complete file; the
changes are the header comment, the `iter` import, and everything from `entries` down to the first
loop in `tags`:

```lua
-- MemoryStore: keeps entries in a table. Every store implements the same
-- methods, so the commands do not care where entries live:
--   add(entry) -> entry      get(id) -> entry|nil     remove(id) -> entry|nil
--   list{tag=, limit=} -> array     search(term) -> array     tags() -> array
--   entries() -> iterator over all entries in id order

local Entry = require("stash.entry")
local iter = require("stash.iter")

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

-- Iterates over the entries in id order:  for entry in store:entries() do
-- The generator walks the ids in order, so no sorting is needed; ids of
-- removed entries are simply missing from the table.
function MemoryStore:entries()
  return coroutine.wrap(function()
    for id = 1, self.next_id - 1 do
      local entry = self.by_id[id]
      if entry then
        coroutine.yield(entry)
      end
    end
  end)
end

-- list and search are pipelines: entries -> filter -> take -> collect.
function MemoryStore:list(filter)
  local it = self:entries()
  if filter.tag then
    it = iter.filter(function(e) return e:has_tag(filter.tag) end, it)
  end
  if filter.limit then
    it = iter.take(filter.limit, it)
  end
  return iter.collect(it)
end

function MemoryStore:search(term)
  return iter.collect(iter.filter(function(e) return e:matches(term) end, self:entries()))
end

-- Returns { {tag=, count=}, ... }: most used first, then by name.
function MemoryStore:tags()
  local counts = {}
  for entry in self:entries() do
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

- `entries()` walks ids `1 .. next_id - 1` in order, so no sort is needed. `Entry.__lt` stays for
  anyone who sorts entries.
- `list` adds a stage only when its filter is used. The pipeline is just a variable holding an
  iterator.
- `list` and `search` still return arrays, so `commands.lua` doesn't change.

### test/iter_test.lua (new)

```lua
local iter = require("stash.iter")

local function is_even(n) return n % 2 == 0 end

test("values, filter and collect", function()
  same(iter.collect(iter.values({ 1, 2, 3, 4 })), { 1, 2, 3, 4 })
  same(iter.collect(iter.filter(is_even, iter.values({ 1, 2, 3, 4 }))), { 2, 4 })
end)

test("take stops early", function()
  same(iter.collect(iter.take(2, iter.values({ 1, 2, 3 }))), { 1, 2 })
  same(iter.collect(iter.take(0, iter.values({ 1, 2, 3 }))), {})
  same(iter.collect(iter.take(5, iter.values({ 1 }))), { 1 })
end)

test("take does not pull more values than it needs", function()
  local pulled = 0
  local function counting()
    pulled = pulled + 1
    return pulled                            -- an endless iterator: 1, 2, 3, ...
  end
  same(iter.collect(iter.take(3, counting)), { 1, 2, 3 })
  eq(pulled, 3)
end)

test("errors inside a stage reach the consumer", function()
  local it = iter.filter(function(v) error("bad value " .. v) end, iter.values({ 7 }))
  raises(function() iter.collect(it) end, "bad value 7")
end)
```

The third test feeds a plain function as an endless iterator. Any function that follows the protocol
can feed a pipeline.

### test/memstore_test.lua

Add at the end:

```lua
test("entries skips removed ids", function()
  local store = sample_store()
  store:remove(2)
  local ids = {}
  for entry in store:entries() do
    ids[#ids + 1] = entry.id
  end
  same(ids, { 1, 3 })
end)
```

### test/run.lua

Register the new file in the `FILES` table:

```lua
-- Test files, in the order they run.
local FILES = {
  "util_test", "cli_test", "entry_test", "iter_test", "memstore_test", "config_test",
  "commands_test",
}
```

### Checkpoint

Run from the project root. The `luajit -e` line tries a pipeline by hand; `LUA_PATH` tells `require`
where the modules are ([Chapter 8](08-modules.md)).

```console
$ luajit test/run.lua
util_test        3 tests, 0 failed
cli_test         5 tests, 0 failed
entry_test       5 tests, 0 failed
iter_test        4 tests, 0 failed
memstore_test    7 tests, 0 failed
config_test      3 tests, 0 failed
commands_test    4 tests, 0 failed

31 passed, 0 failed
$ LUA_PATH="src/?.lua" luajit -e 'local iter = require("stash.iter") local evens = iter.filter(function(n) return n % 2 == 0 end, iter.values({ 1, 2, 3, 4, 5, 6, 7, 8 })) print(table.concat(iter.collect(iter.take(3, evens)), " "))'
2 4 6
$ ./stash list
  1  The Programming Language Lua          lang,lua
  2  LuaJIT                                jit,lua
  3  SQLite FTS5 Extension                 db,search
$ ./stash list -t lua --limit 1
  1  The Programming Language Lua          lang,lua
$ ./stash tags
   2  lua
   1  db
   1  jit
   1  lang
   1  search
```

Same output as before: only the inside changed, and the tests prove it.

The complete project at this point is in `project/ch11/`.

## Summary

- `coroutine.create(fn)` makes a coroutine; `resume` runs it until it yields or returns. `status`:
  `suspended`, `running`, `normal`, `dead`.
- `resume` arguments come out of `yield`; `yield` arguments come out of `resume`; return values come
  out of the last `resume`.
- `coroutine.wrap(fn)` gives a function that resumes on each call and raises errors. The usual way to
  write generators.
- The generic `for` calls `f(s, ctl)` until the first result is `nil`. Iterators are stateless
  (`ipairs`), closures, or coroutines.
- Closures for simple state, coroutines for complex state such as recursion. A switch is slower than
  a call.
- Coroutine pipelines are lazy: one item at a time; stopping early is free.
- `resume` catches errors (`false, msg`). `debug.traceback(co, msg)` shows where a coroutine died.
  LuaJIT can yield across `pcall` and metamethods.
- Coroutines give cooperative multitasking, not parallelism.
- `stash`: `iter.lua` (values/filter/take/collect) and `MemoryStore:entries()`; `list` and `search`
  are pipelines.

## Exercises

1. Write a stateless iterator `range(from, to, step)` that counts up or down (`step` defaults to 1).
   `for i in range(10, 1, -3)` should give 10 7 4 1. Use no closures and no coroutines.

<details><summary>Solution</summary>

The state is a table with the limit and step. The control variable is the current number.

```lua
local function range_step(state, i)
  i = i + state.step
  if (state.step > 0 and i <= state.to) or (state.step < 0 and i >= state.to) then
    return i
  end
end

local function range(from, to, step)
  step = step or 1
  return range_step, { to = to, step = step }, from - step
end

for i in range(1, 5) do io.write(i, " ") end print()
for i in range(10, 1, -3) do io.write(i, " ") end print()
for i in range(1, 0) do io.write(i, " ") end print("(empty)")
```

```console
1 2 3 4 5 
10 7 4 1 
(empty)
```

</details>

2. Add `iter.map(fn, it)` to `stash.iter`. It passes on `fn(value)` for every value.
   `iter.collect(iter.map(function(n) return n * n end, iter.values({ 1, 2, 3 })))` should be `{ 1, 4, 9 }`.

<details><summary>Solution</summary>

```lua
-- Passes on fn(value) for every value.
function M.map(fn, it)
  return coroutine.wrap(function()
    for v in it do
      coroutine.yield(fn(v))
    end
  end)
end
```

If `fn` returns `nil`, the consumer's loop ends early: `nil` means "no more values", so `map` can't
pass `nil` along.

</details>

3. Write `zip(a, b)`: it takes two iterators and yields pairs `x, y` until either one runs out.

<details><summary>Solution</summary>

```lua
local function zip(a, b)
  return coroutine.wrap(function()
    while true do
      local x, y = a(), b()
      if x == nil or y == nil then
        return
      end
      coroutine.yield(x, y)
    end
  end)
end

local function values(t)
  local i = 0
  return function()
    i = i + 1
    return t[i]
  end
end

for n, name in zip(values({ 1, 2, 3 }), values({ "one", "two" })) do
  print(n, name)
end
```

```console
1	one
2	two
```

A generator may yield several values. The `for` loop receives them all.

</details>

4. Rewrite `MemoryStore:entries()` as a closure iterator, without a coroutine. All 31 tests must still
   pass.

<details><summary>Solution</summary>

The closure remembers the last id it looked at:

```lua
function MemoryStore:entries()
  local id = 0
  return function()
    while id < self.next_id - 1 do
      id = id + 1
      local entry = self.by_id[id]
      if entry then
        return entry
      end
    end
  end
end
```

`luajit test/run.lua` still prints `31 passed, 0 failed`. The stages don't care how an iterator is
made. The coroutine version reads more easily; this one is faster.

</details>

5. Add a `spawn` call *inside* the `ping` task in `scheduler.lua`, so that on its second round it
   starts a third task, `late`, that prints once. Does the scheduler pick it up, and when?

<details><summary>Solution</summary>

Change the `ping` loop body to:

```lua
    print(("[%d] ping %d"):format(now, i))
    if i == 2 then
      spawn("late", function() print(("[%d] late"):format(now)) end)
    end
    sleep(2)
```

```console
[0] ping 1
[0] pong 1
[2] ping 2
[2] late
[3] pong 2
[4] ping 3
[6] pong failed: examples/ch11/scheduler.lua:58: pong gives up
all tasks finished at tick 7
```

`[2] late` appears right after `[2] ping 2`. `spawn` appends to `tasks`, and `while i <= #tasks`
re-reads the length, so the new task runs in the same tick. Its `wake` is 0, already in the past.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-11--coroutines)
