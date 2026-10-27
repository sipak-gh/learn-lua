# Chapter 18 — Performance and the JIT

LuaJIT is fast because it compiles the code that runs most into machine code while the program runs.
This chapter shows how, how to watch it (`-jv`, `-jdump`, the `-jp` profiler), what stops it, and how
to measure without fooling yourself. Then you profile `stash`, find a slow search and fix it. The
code is from [Chapter 17](17-binary-data-and-zlib.md); [Chapter 19](19-plugins-and-scripting.md)
opens `stash` up to plugins.

> ⚠ Every timing in this chapter is from one machine on one day. Your numbers will differ, and they
> change from run to run. Compare the ratios, not the exact values.

## Measuring time

To measure, you need a clock. Lua's `os.clock()` returns the process's **CPU time** in seconds; it
doesn't advance while the process waits for the disk, the network or a sleep. A **monotonic clock**
counts real time and never jumps, even when the system clock is changed. On Linux and macOS it is
`clock_gettime(CLOCK_MONOTONIC)`, which the FFI can call ([Chapter 13](13-ffi-basics.md)).

`examples/ch18/clock.lua`

```lua
-- Two clocks: CPU time (os.clock) and real time (clock_gettime).
local ffi = require("ffi")

ffi.cdef [[
struct timespec { long tv_sec; long tv_nsec; };
int clock_gettime(int clock, struct timespec *tp);
int poll(void *fds, unsigned long nfds, int timeout);
]]
local CLOCK_MONOTONIC = ffi.os == "OSX" and 6 or 1

local ts = ffi.new("struct timespec")
local function now()
  ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
  return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

local function time(name, fn)
  local cpu, real = os.clock(), now()
  fn()
  print(("%-6s cpu %.2f s   real %.2f s"):format(name, os.clock() - cpu, now() - real))
end

time("work", function()                      -- busy: both clocks advance
  local x = 0
  for i = 1, 1e8 do x = x + i % 7 end
end)
time("sleep", function()                     -- waiting: only real time passes
  ffi.C.poll(nil, 0, 300)                    -- sleep 300 ms
end)
```

```console
$ luajit examples/ch18/clock.lua
work   cpu 0.19 s   real 0.19 s
sleep  cpu 0.00 s   real 0.30 s
```

- `CLOCK_MONOTONIC` is a C `#define`, so we copy its value: 1 on Linux, 6 on macOS.
- The `timespec` is created once and reused; creating it in `now()` would add garbage to every
  measurement.
- `poll(nil, 0, ms)` with no file descriptors just waits: a portable sleep.
- Use `os.clock()` for pure computation, and the monotonic clock when the code waits for anything,
  like SQLite writing a file. The examples below are pure computation, so they use `os.clock()`.

## How a tracing JIT works

LuaJIT starts every program in its **interpreter**, which is fast but runs bytecode one instruction
at a time. Meanwhile it counts how often each loop goes round and each function is called. When a
counter crosses a threshold (56 by default), the code is **hot** and the JIT gets to work:

1. **Record.** The interpreter runs one more iteration and records each operation: a **trace**, one
   straight path through the code. Calls are followed into the callee, so they're inlined.
2. **Guard.** The trace assumes what it saw: this variable was an integer, that branch went left, this
   table had that shape. Each assumption becomes a cheap check, a **guard**.
3. **Compile.** The trace is optimized into machine code. Next time the loop starts, LuaJIT jumps into
   that code instead of interpreting.

This is a **tracing JIT**. It compiles what the program *does*, not every path it *could* take, so
the machine code is short and specialized. `-jv` (verbose) prints a line per trace:

`examples/ch18/hot.lua`

```lua
-- A hot loop: run it with `luajit -jv hot.lua` to watch the JIT.

local function sum_squares(n)
  local sum = 0
  for i = 1, n do
    sum = sum + i * i
  end
  return sum
end

print(sum_squares(10))        -- 10 iterations: too few to get hot
print(sum_squares(1000))      -- hot: the loop is traced and compiled
```

```console
$ luajit -jv examples/ch18/hot.lua
385
[TRACE   1 hot.lua:5 loop]
333833500
```

- `-jv` writes to stderr, so its lines appear among the program's output.
- The first call loops 10 times, below the threshold: no trace.
- In the second call the loop gets hot. `TRACE 1 hot.lua:5 loop`: trace 1 starts at line 5 and ends
  by jumping back to its own start (`loop`). The other 900-odd iterations run as machine code.

## Side exits and side traces

When a guard fails, the compiled code takes a **side exit**: it hands the current values back to the
interpreter, which carries on. If the same exit is taken often (10 times by default), the JIT records
a **side trace** from it and patches it in, so next time execution stays in compiled code.

`examples/ch18/sideexit.lua`

```lua
-- A branch the trace didn't expect: `luajit -jv sideexit.lua`

local function count(n)
  local small, big = 0, 0
  for i = 1, n do
    if i <= 500 then
      small = small + 1
    else
      big = big + 1               -- first taken at i = 501
    end
  end
  return small, big
end

print(count(1000))
```

```console
$ luajit -jv examples/ch18/sideexit.lua
[TRACE   1 sideexit.lua:5 loop]
[TRACE   2 (1/1) sideexit.lua:9 -> 1]
500	500
```

- Trace 1 was recorded while `i <= 500`, so it holds only the `small` branch and a guard.
- From `i = 501` the guard fails every time; after a few exits, trace 2 is recorded.
- `(1/1)` means a side trace of trace 1 from its exit 1; `-> 1` means it jumps back into trace 1 at
  the end.

Branches are fine. A loop whose branches go many ways becomes many small side traces and runs a bit
slower than a straight loop, but still far faster than the interpreter.

## Looking inside: `-jdump`

`-jdump` prints each trace three ways: the recorded bytecode, the **IR** (the compiler's
intermediate representation, where it optimizes), and the machine code. Addresses change every run.

```console
$ luajit -jdump examples/ch18/hot.lua
385
---- TRACE 1 start hot.lua:5
0006  MULVV    6   5   5
0007  ADDVV    1   1   6
0008  FORL     2 => 0006
---- TRACE 1 IR
0001 >  int SLOAD  #5    CRI
0002 >  int LE     0001  +2147483646
0003    int SLOAD  #4    CI
0004    num CONV   0003  num.int
0005    num MUL    0004  0004
0006 >  num SLOAD  #3    T
0007  + num ADD    0006  0005
0008  + int ADD    0003  +1  
0009 >  int LE     0008  0001
0010 ------ LOOP ------------
0011    num CONV   0008  num.int
0012    num MUL    0011  0011
0013  + num ADD    0012  0007
0014  + int ADD    0008  +1  
0015 >  int LE     0014  0001
0016    int PHI    0008  0014
0017    num PHI    0007  0013
---- TRACE 1 mcode 127
6252227dff7c  mov dword [r14-0xee8], 0x1
6252227dff87  movsd xmm7, [rdx+0x18]
6252227dff8c  cvttsd2si eax, xmm7
6252227dff90  xorps xmm6, xmm6
6252227dff93  cvtsi2sd xmm6, eax
6252227dff97  ucomisd xmm7, xmm6
6252227dff9b  jnz 0x6252227d0060	->0
6252227dffa1  jpe 0x6252227d0060	->0
6252227dffa7  cmp eax, 0x7ffffffe
6252227dffad  jg 0x6252227d0060	->0
6252227dffb3  cvttsd2si ebp, [rdx+0x10]
6252227dffb8  xorps xmm7, xmm7
6252227dffbb  cvtsi2sd xmm7, ebp
6252227dffbf  mulsd xmm7, xmm7
6252227dffc3  cmp dword [rdx+0xc], 0xfff90000
6252227dffca  jnb 0x6252227d0060	->0
6252227dffd0  addsd xmm7, [rdx+0x8]
6252227dffd5  add ebp, +0x01
6252227dffd8  cmp ebp, eax
6252227dffda  jg 0x6252227d0064	->1
->LOOP:
6252227dffe0  xorps xmm6, xmm6
6252227dffe3  cvtsi2sd xmm6, ebp
6252227dffe7  mulsd xmm6, xmm6
6252227dffeb  addsd xmm7, xmm6
6252227dffef  add ebp, +0x01
6252227dfff2  cmp ebp, eax
6252227dfff4  jle 0x6252227dffe0	->LOOP
6252227dfff6  jmp 0x6252227d006c	->3
---- TRACE 1 stop -> loop

333833500
```

How to read it:

- The bytecode part lists the loop body's three instructions: multiply, add, loop.
- In the IR, `>` marks a guard. `SLOAD #4 CI` loads the loop counter as an `int`: the JIT saw that `i`
  is always a whole number, so it uses a 32-bit integer (**narrowing**).
- `------ LOOP ------` splits the trace. Everything above runs once; everything below is the loop.
  Work that's the same every time moves above the line (**loop hoisting**).
- The machine code after `->LOOP:` is the whole loop: 7 x86-64 instructions. The interpreter needs
  many more for the same work.

You won't read `-jdump` often; it shows whether something compiled the way you hoped. `-jdump=i`
shows only the IR, `-jdump=m` only the machine code.

## What the JIT can't compile

Some operations stop the recorder: it **aborts** the trace and retries later. Code that aborts too
often is **blacklisted**: the JIT stops trying and it stays interpreted. LuaJIT calls these
operations **NYI**, "not yet implemented". The list changes between versions, so check with `-jv`:

`examples/ch18/nyi.lua`

```lua
-- Things the JIT can't compile: run with luajit -jv nyi.lua

local function with_closure(n)
  local sum = 0
  for i = 1, n do
    local double = function(x) return x * 2 end   -- a new closure each time
    sum = sum + double(i)
  end
  return sum
end

local function double(x)
  return x * 2
end

local function without_closure(n)
  local sum = 0
  for i = 1, n do
    sum = sum + double(i)                    -- one function, made once
  end
  return sum
end

local function with_gsub(n)
  local sum = 0
  for i = 1, n do
    sum = sum + #(("a,b,c"):gsub(",", ";"))  -- a C function the JIT doesn't know
  end
  return sum
end

local function time(name, fn)
  local start = os.clock()
  fn(1e6)
  print(("%-16s %6.1f ms"):format(name, (os.clock() - start) * 1000))
end

time("with closure", with_closure)
time("without closure", without_closure)
time("with gsub", with_gsub)
```

```console
$ luajit -jv examples/ch18/nyi.lua
[TRACE --- nyi.lua:5 -- NYI: bytecode FNEW   at nyi.lua:6]
[TRACE --- nyi.lua:5 -- NYI: bytecode FNEW   at nyi.lua:6]
[TRACE   1 nyi.lua:6 return]
[TRACE --- nyi.lua:5 -- NYI: bytecode FNEW   at nyi.lua:6]
[TRACE --- nyi.lua:5 -- NYI: bytecode FNEW   at nyi.lua:6]
[TRACE --- nyi.lua:5 -- NYI: bytecode FNEW   at nyi.lua:6]
[TRACE --- nyi.lua:5 -- NYI: bytecode FNEW   at nyi.lua:6]
[TRACE --- nyi.lua:5 -- NYI: bytecode FNEW   at nyi.lua:6]
[TRACE --- nyi.lua:5 -- NYI: bytecode FNEW   at nyi.lua:6]
[TRACE --- nyi.lua:5 -- NYI: bytecode FNEW   at nyi.lua:6]
[TRACE --- nyi.lua:5 -- NYI: bytecode FNEW   at nyi.lua:6]
[TRACE --- nyi.lua:5 -- NYI: bytecode FNEW   at nyi.lua:6]
with closure       41.6 ms
[TRACE   2 nyi.lua:18 loop]
without closure     0.5 ms
[TRACE   3 nyi.lua:26 stitch string.gsub]
[TRACE   4 (3/stitch) nyi.lua:27 -> 3]
with gsub         108.7 ms
```

- `NYI: bytecode FNEW` means creating a closure. The loop in `with_closure` aborts again and again,
  then gives up; only the closure body (trace 1, ending in `return`) is compiled. The same loop with
  the function made once compiles, with `double` inlined, and is dozens of times faster.
- `stitch string.gsub` means the trace stops at a C function the JIT doesn't know, calls it normally,
  and a new trace continues after it. The code around the call is still compiled, but nothing is
  optimized across it, and each call creates a new string.
- In LuaJIT 2.1, `pairs`, `next`, `string.format`, `tostring`, `table.insert`, `unpack`, `pcall` and
  FFI calls all compile. Pattern functions (`gsub`, `match`, `gmatch`) are stitched.

Rule of thumb: in a hot loop, don't create closures, and know that pattern matching runs at C speed
but blocks optimization around it. Outside hot loops, none of this matters.

## Profiling with `-jp`

Guesses about where the time goes are usually wrong. A **profiler** checks every few milliseconds
which function is running and counts. LuaJIT has one built in: `-jp`.

`examples/ch18/profile.lua`

```lua
-- Where does the time go? Run: luajit -jp=F profile.lua

local WORDS = { "lua", "jit", "trace", "table", "string", "buffer", "ffi" }

local function make_text(n)                  -- n words, as one string
  local words = {}
  for i = 1, n do
    words[i] = WORDS[i % #WORDS + 1] .. (i % 50)
  end
  return table.concat(words, " ")
end

local function count_words(text)
  local counts = {}
  for word in text:gmatch("%a+") do          -- letters only: "lua17" -> "lua"
    counts[word] = (counts[word] or 0) + 1
  end
  return counts
end

local function top(counts)
  local list = {}
  for word, n in pairs(counts) do
    list[#list + 1] = { word = word, n = n }
  end
  table.sort(list, function(a, b) return a.n > b.n or (a.n == b.n and a.word < b.word) end)
  return list[1].word, list[1].n
end

local text = make_text(2e6)
local counts
for _ = 1, 5 do
  counts = count_words(text)
end
print(top(counts))
```

```console
$ luajit -jp=F examples/ch18/profile.lua
jit	285715
86%  profile.lua:count_words
10%  profile.lua:make_text
 4%  profile.lua:0
$ luajit -jp=l examples/ch18/profile.lua
jit	285715
90%  profile.lua:15
 5%  profile.lua:7
 3%  profile.lua:31
$ luajit -jp=Fv examples/ch18/profile.lua
jit	285715
90%  profile.lua:count_words
  <- 78%  C code
  <- 21%  Compiled
 8%  profile.lua:make_text
  <- 88%  Compiled
  <- 13%  Garbage Collector
```

- `F` shows `file:function`, `l` shows `file:line`. `profile.lua:0` is the main chunk.
- `v` shows **VM states**: interpreted, compiled, C code or garbage collector. Much of `count_words`
  is C code (`gmatch` searching the text), which changing the Lua around it can't speed up. This
  split varies between runs more than the other modes.
- The percentages are samples, so they move a little between runs. Spots under 3% are hidden.
- To profile part of a program, wrap it in `require("jit.p").start("F")` and
  `require("jit.p").stop()`. `stash`'s benchmark runner does that.

## Building strings: `..`, `table.concat`, `string.buffer`

Lua strings can't change. `s = s .. piece` makes a new string and copies all of `s` into it, so in a
loop the work grows with the square of the length. [Chapter 6](06-strings.md) used `table.concat`
instead. LuaJIT also has `string.buffer`, a growable buffer that appends in place:

`examples/ch18/concat.lua`

```lua
-- Three ways to build a long string from many pieces.
local buffer = require("string.buffer")
local N = 20000

local function time(name, fn)
  local start = os.clock()
  local s = fn()
  print(("%-14s %8.2f ms  %d bytes"):format(name, (os.clock() - start) * 1000, #s))
end

time("..", function()
  local s = ""
  for i = 1, N do
    s = s .. "line " .. i .. "\n"            -- copies all of s, every time
  end
  return s
end)

time("table.concat", function()
  local parts = {}
  for i = 1, N do
    parts[#parts + 1] = "line " .. i .. "\n"
  end
  return table.concat(parts)
end)

time("string.buffer", function()
  local buf = buffer.new()
  for i = 1, N do
    buf:put("line ", i, "\n")                -- appends in place
  end
  return buf:tostring()
end)
```

```console
$ luajit examples/ch18/concat.lua
..               264.47 ms  208894 bytes
table.concat       3.54 ms  208894 bytes
string.buffer      0.66 ms  208894 bytes
```

The buffer wins because it makes nothing it doesn't need. `table.concat` still creates a string per
piece and a table to hold them; the buffer copies each piece once, into reused memory. A short tour
of the rest of the API:

`examples/ch18/buffer.lua`

```lua
-- LuaJIT's string buffers: a growable, reusable string builder.
local buffer = require("string.buffer")

local buf = buffer.new()
buf:put("stash", " ", 18):put("\n")          -- put returns buf: calls chain
buf:putf("%-6s|%5.1f|\n", "pi", math.pi)     -- like string.format
print(#buf)
io.write(buf:tostring())                     -- a copy; buf is unchanged

-- A buffer is also a queue: get() takes bytes off the front.
print(buf:get(5), #buf)
buf:reset()                                  -- empty, but keeps its memory
print(#buf)

-- Serialization: any Lua value without functions, to bytes and back.
local bytes = buffer.encode({ id = 7, tags = { "lua", "jit" } })
local copy = buffer.decode(bytes)
print(#bytes, copy.id, copy.tags[2])
```

```console
$ luajit examples/ch18/buffer.lua
23
stash 18
pi    |  3.1|
stash	18
0
29	7	jit
```

- `put` accepts any number of strings and numbers and returns the buffer.
- `putf` formats like `string.format` without creating the formatted string first.
- `tostring` copies the contents into a new Lua string; `get(n)` removes `n` bytes from the front.
- `reset` empties the buffer but keeps its memory. Reuse one buffer rather than creating one per
  call.
- `buffer.encode`/`buffer.decode` serialize Lua values (tables, strings, numbers, booleans) to a
  compact binary string. Fast, but the format is LuaJIT's own: use JSON for anything another program
  reads.

## Tables, `table.new` and C arrays

[Chapter 5](05-tables.md) showed `table.new`, [Chapter 14](14-c-data.md) C arrays. Which is faster
for a million numbers? A small `stash` benchmark (part of this chapter's project, below) answers:

`project/ch18/bench/arrays.lua`

```lua
-- Lua tables vs C arrays: filling and summing a million numbers.
--
--   luajit bench/arrays.lua
--
-- Timings depend on the machine; compare runs on the same one.

package.path = "src/?.lua;" .. package.path

local ffi = require("ffi")
local table_new = require("table.new")     -- table.new(narray, nhash)
local clock = require("stash.clock")

local N = 1000000

local function measure(name, fn)
  local best = math.huge
  for _ = 1, 5 do
    collectgarbage()
    local start = clock.now()
    fn()
    best = math.min(best, clock.now() - start)
  end
  print(("%-28s %8.2f ms"):format(name, best * 1000))
end

-- Filling: a table grows as we go (and is copied each time it grows),
-- unless table.new makes it big enough up front.
measure("fill table", function()
  local t = {}
  for i = 1, N do t[i] = i * 0.5 end
end)
measure("fill table.new", function()
  local t = table_new(N, 0)
  for i = 1, N do t[i] = i * 0.5 end
end)
measure("fill double[N]", function()
  local a = ffi.new("double[?]", N)        -- zero-filled, fixed size
  for i = 0, N - 1 do a[i] = i * 0.5 end
end)

-- Summing: the loops are traces of a few machine instructions each.
local t, a = {}, ffi.new("double[?]", N)
for i = 1, N do t[i] = i * 0.5; a[i - 1] = i * 0.5 end

local function sum_table()
  local sum = 0
  for i = 1, N do sum = sum + t[i] end
  return sum
end
local function sum_array()
  local sum = 0
  for i = 0, N - 1 do sum = sum + a[i] end
  return sum
end
assert(sum_table() == sum_array())
measure("sum table", sum_table)
measure("sum double[N]", sum_array)

-- Memory: what does each one add to the heap? For plain numbers the
-- two are alike; the C array wins with smaller types and with records,
-- where every Lua table is a separate object with its own header.
local function heap_kb(make)
  collectgarbage()
  local before = collectgarbage("count")
  local keep = make()                      -- not garbage before we count
  local after = collectgarbage("count")
  return math.floor(after - before + 0.5)
end

local M = 100000
print(("%d numbers: table %d KB, double[] %d KB, uint8_t[] %d KB"):format(N,
  heap_kb(function() return table_new(N, 0) end),
  heap_kb(function() return ffi.new("double[?]", N) end),
  heap_kb(function() return ffi.new("uint8_t[?]", N) end)))
print(("%d points: tables %d KB, struct[] %d KB"):format(M,
  heap_kb(function()
    local points = table_new(M, 0)
    for i = 1, M do points[i] = { x = i, y = i } end
    return points
  end),
  heap_kb(function() return ffi.new("struct { double x, y; }[?]", M) end)))
```

```console
$ luajit bench/arrays.lua
fill table                       2.77 ms
fill table.new                   2.24 ms
fill double[N]                   2.25 ms
sum table                        0.45 ms
sum double[N]                    0.48 ms
1000000 numbers: table 7813 KB, double[] 7813 KB, uint8_t[] 977 KB
100000 points: tables 11719 KB, struct[] 1563 KB
```

- For speed, the JIT makes a plain Lua table as fast as a C array. Summing a million numbers takes
  under a millisecond either way.
- `table.new` helps a little: the table doesn't have to grow (and copy itself) along the way.
- For **memory**, C arrays win for small items and records. A Lua table stores every number in 8
  bytes, even a byte value. A table per point costs about 120 bytes; a C struct of two doubles, 16.
- `heap_kb` counts with `collectgarbage("count")`, which includes cdata; that's why the C arrays show
  up at all.

Use C arrays for many records or bytes. For ordinary lists, tables are fine.

## Locals and globals

A global like `math.floor` is two lookups: `math` in the globals table, then `floor` in `math`. A
local is a slot in the function. Old advice says to copy globals into locals for speed:

`examples/ch18/locals.lua`

```lua
-- Globals vs locals. Try: luajit locals.lua, then luajit -joff locals.lua
local N = 1e7

local function with_globals()
  local sum = 0
  for i = 1, N do
    sum = sum + math.floor(i / 3)            -- looks up `math`, then `floor`
  end
  return sum
end

local floor = math.floor                     -- looked up once, here
local function with_locals()
  local sum = 0
  for i = 1, N do
    sum = sum + floor(i / 3)
  end
  return sum
end

local function time(name, fn)
  local start = os.clock()
  fn()
  print(("%-12s %6.1f ms"):format(name, (os.clock() - start) * 1000))
end

time("globals", with_globals)
time("locals", with_locals)
```

```console
$ luajit examples/ch18/locals.lua
globals        10.1 ms
locals         10.4 ms
$ luajit -joff examples/ch18/locals.lua
globals        92.7 ms
locals         65.2 ms
```

- With the JIT, there's no difference. The trace checks that `math.floor` is still the same function,
  loop optimization moves that check out of the loop, and `floor` becomes one machine instruction.
- With `-joff` (interpreter only), the local version is faster, and everything is 6 to 10 times
  slower.
- So `local floor = math.floor` matters only for code that isn't compiled. Do it where it makes the
  code clearer, as [Chapter 8](08-modules.md) suggested for `require`.

## Switching the JIT off

The `jit` module controls the compiler from Lua: `jit.off()` and `jit.on()` for the whole VM, or
`jit.off(f)` for one function. [Chapter 16](16-callbacks-and-curl.md) used `jit.off(Stmt.step)` to
stop a crash.

`examples/ch18/jitoff.lua`

```lua
-- Switching the JIT off and on, for everything or for one function.
print(jit.version, jit.arch)
print(jit.status())                          -- on?, then the CPU features and options

local function sum(n)
  local s = 0
  for i = 1, n do
    local p = { x = i, y = 0.5 }             -- a new table every time?
    s = s + p.x * p.y
  end
  return s
end

local function time(name)
  local start = os.clock()
  sum(1e7)
  print(("%-22s %6.1f ms"):format(name, (os.clock() - start) * 1000))
end

time("compiled")
jit.off(sum)                                 -- this function: interpreter only
time("jit.off(sum)")
jit.on(sum)
time("jit.on(sum)")

jit.off()                                    -- the whole VM, like luajit -joff
print(jit.status())
```

```console
$ luajit examples/ch18/jitoff.lua
LuaJIT 2.1.1792588164	x64
true	SSE3	SSE4.1	BMI2	fold	cse	dce	fwd	dse	narrow	loop	abc	sink	fuse
compiled                  4.5 ms
jit.off(sum)            432.3 ms
jit.on(sum)               4.5 ms
false	SSE3	SSE4.1	BMI2	fold	cse	dce	fwd	dse	narrow	loop	abc	sink	fuse
```

- `jit.status()` returns whether the JIT is on, then the CPU features and optimizations it uses (all
  of them, by default).
- `jit.off(sum)` makes the interpreter run `sum` and discards the code already compiled for it.
  `jit.off(f, true)` also covers every function defined inside `f`.
- The loop builds a table each iteration. Interpreted, that's ten million tables to allocate and
  collect. Compiled, the table never exists: the JIT sees it doesn't escape the iteration and keeps
  the numbers in registers. This is **allocation sinking** (`sink` in the list), and it's why the gap
  is about a hundred times here, not a few.
- Sinking works only in compiled code, and only when the table doesn't leave the loop. Store it
  somewhere, or abort the trace (with a closure, say), and the allocations are real again.

## Benchmarks done right

A benchmark is an experiment, and it's easy to measure the wrong thing:

`examples/ch18/pitfalls.lua`

```lua
-- Three ways a benchmark can lie.
local function time(name, fn)
  local start = os.clock()
  local result = fn()
  print(("%-24s %7.3f ms"):format(name, (os.clock() - start) * 1000))
  return result
end

-- 1. Work whose result is never used may be removed by the compiler.
time("result thrown away", function()
  for i = 1, 1e7 do
    local _ = math.sqrt(i)
  end
end)
time("result used", function()
  local sum = 0
  for i = 1, 1e7 do
    sum = sum + math.sqrt(i)
  end
  return sum
end)

-- 2. One run is not a measurement: the first one includes compiling,
-- and any of them may be slowed down by whatever else the machine does.
local function work()
  local sum = 0
  for i = 1, 20000 do sum = sum + (i % 7) * (i % 3) end
  return sum
end
for round = 1, 4 do
  time("round " .. round, work)
end

-- 3. Garbage made by earlier code is collected during later code.
local function allocate()
  local t = {}
  for i = 1, 3e5 do t[i] = { i } end
  return t
end
local junk = {}
for i = 1, 3e6 do junk[i] = { i } end
junk = nil
time("after making garbage", allocate)
collectgarbage()                             -- a full collection, now
time("after collectgarbage()", allocate)
```

```console
$ luajit examples/ch18/pitfalls.lua
result thrown away         4.786 ms
result used               60.949 ms
round 1                    0.192 ms
round 2                    0.139 ms
round 3                    0.139 ms
round 4                    0.139 ms
after making garbage      28.116 ms
after collectgarbage()    12.880 ms
```

1. The first loop computes square roots and throws them away. The compiler removed that work (**dead
   code elimination**), leaving only the counting. A benchmark must use its results.
2. The rounds differ. The first includes recording and compiling the trace; the rest is noise from
   the machine.
3. The same function is slower right after lots of garbage was made, because it pays for collecting
   it. Call `collectgarbage()` before each measurement.

The rules:

- Measure realistic work that takes at least a few milliseconds.
- Run it several times and keep the **fastest** run; slower runs measure what else the machine was
  doing.
- Collect garbage before each run.
- Change one thing at a time, and compare on the same machine.
- Profile before you optimize, and measure after. If it isn't faster, undo it.

## Building stash: measure, then fix the slow part

How fast is `stash` with 20000 bookmarks? Only measuring tells. This step adds a clock, a benchmark
runner and the arrays benchmark above, then profiles the hot paths and fixes what the profile shows.

### `src/stash/ffi/libc.lua`

The clock needs `clock_gettime`. Add the struct and function to the `cdef` block:

```lua
void *malloc(size_t size);
void *realloc(void *ptr, size_t size);
void free(void *ptr);

struct timespec {
  long tv_sec;                                /* time_t: a long on Linux and macOS */
  long tv_nsec;
};
int clock_gettime(int clock, struct timespec *tp);

struct winsize {
  unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel;
};
int ioctl(int fd, unsigned long request, ...);
]]
```

and the constant after `TIOCGWINSZ`:

```lua
-- #define constants don't exist for the FFI; we copy their values.
M.EEXIST = 17                                -- the same on Linux and macOS
M.TIOCGWINSZ = ffi.os == "OSX" and 0x40087468 or 0x5413   -- this one differs
M.CLOCK_MONOTONIC = ffi.os == "OSX" and 6 or 1
```

### `src/stash/clock.lua` (new)

```lua
-- A clock for measuring: seconds since some fixed moment, with
-- nanosecond resolution. os.clock() counts CPU time of this process
-- only; a monotonic clock counts real time and never jumps backwards.

local ffi = require("ffi")
local libc = require("stash.ffi.libc")

local M = {}

local ts = ffi.new("struct timespec")       -- made once, reused by every call

function M.now()
  ffi.C.clock_gettime(libc.CLOCK_MONOTONIC, ts)
  return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

return M
```

### Nested transactions with savepoints

The benchmark fills a store with 20000 entries in one transaction, for speed. But `Store:add`
already runs in a transaction, and `BEGIN` can't nest. With the Chapter 17 code the benchmark stops
at once:

```text
luajit: database: cannot start a transaction within a transaction
stack traceback:
	[C]: in function 'error'
	src/stash/db.lua:114: in function 'transaction'
	bench/run.lua:36: in function 'big_store'
	bench/run.lua:70: in main chunk
```

SQLite's **savepoints** nest. `SAVEPOINT name` starts one; `RELEASE name` ends it, keeping its
changes; `ROLLBACK TO name` undoes the changes since it started (and leaves it open, so you still
`RELEASE` it). Outside any transaction, a savepoint starts one, and the outermost `RELEASE` commits.
Inner savepoints may share a name: each `RELEASE` or `ROLLBACK TO` finds the most recent one. Replace
`Db:transaction` in `src/stash/db.lua`:

```lua
-- Runs fn() in a transaction: all its changes happen, or none do.
-- Savepoints, unlike BEGIN/COMMIT, nest: a transaction inside another
-- one becomes part of it, and only the outermost RELEASE commits.
function Db:transaction(fn, ...)
  self:exec("SAVEPOINT tx")
  local ok, err = pcall(fn, ...)
  if not ok then
    self:exec("ROLLBACK TO tx")              -- undo the changes...
    self:exec("RELEASE tx")                  -- ...and end the savepoint
    error(err, 0)                            -- re-raise, unchanged
  end
  self:exec("RELEASE tx")
end
```

The callers don't change.

### `bench/run.lua` (new)

```lua
-- Benchmarks for stash's hot paths. Run from the project directory:
--
--   luajit bench/run.lua            all benchmarks
--   luajit bench/run.lua export     the ones whose name contains "export"
--   luajit bench/run.lua -p export  ditto, and profile them (jit.p)
--
-- Timings depend on the machine; compare runs on the same one.

package.path = "src/?.lua;" .. package.path

local clock = require("stash.clock")
local cli = require("stash.cli")
local commands = require("stash.commands")
local config = require("stash.config")
local Entry = require("stash.entry")
local Store = require("stash.store")

local N = 20000

-- Runs fn `rounds` times and prints the fastest run: the slower ones
-- measure whatever else the machine was doing.
local function measure(name, rounds, fn)
  local best = math.huge
  for _ = 1, rounds do
    collectgarbage()
    local start = clock.now()
    fn()
    best = math.min(best, clock.now() - start)
  end
  print(("%-28s %8.1f ms"):format(name, best * 1000))
end

-- A store with N entries, each with two tags and some text.
local function big_store()
  local store = assert(Store.open(":memory:"))
  store.db:transaction(function()
    for i = 1, N do
      store:add(Entry.new({ url = ("https://example.com/page/%d"):format(i),
                            title = ("Page number %d about \"Lua\""):format(i),
                            tags = { "tag" .. i % 10, "bench" }, note = "note\t" .. i,
                            created = 1767225600 + i }),
                "some words for the search index " .. i)
    end
  end)
  return store
end

-- Runs a command with output going nowhere.
local function run_command(store, args)
  local command = commands[args[1]]
  local ctx = { store = store, config = config.defaults, out = function() end,
                paint = function(s) return s end, width = 80 }
  command.run(ctx, assert(cli.parse(args, 2, command.options)))
end

local BENCHMARKS = {
  { "insert " .. N .. " entries", 1, big_store },
  { "export " .. N .. " entries", 5, function(store) run_command(store, { "export" }) end },
  { "list " .. N .. " entries", 5, function(store) run_command(store, { "list", "--limit", "-1" }) end },
  { "search 'words'", 5, function(store) run_command(store, { "search", "words" }) end },
}

local profile, filter = false, nil
for _, a in ipairs(arg) do
  if a == "-p" then profile = true else filter = a end
end

-- `luajit -jp` would profile the whole run, setup included; jit.p lets
-- us profile just the benchmarks. "F" means: show module:function names.
local store = big_store()
if profile then require("jit.p").start("F") end
for _, b in ipairs(BENCHMARKS) do
  local name, rounds, fn = b[1], b[2], b[3]
  if filter == nil or name:find(filter, 1, true) then
    measure(name, rounds, function() fn(store) end)
  end
end
if profile then require("jit.p").stop() end
```

- `measure` follows the rules above: several rounds, garbage collected before each, the best printed.
  Inserting runs once: it's slow, and the store must be built anyway.
- The commands run with `out` set to a do-nothing function, so the benchmark measures `stash`, not
  the terminal.
- `-p` profiles only the benchmarks with `jit.p`; `luajit -jp bench/run.lua` would also profile
  building the store.

Also add `bench/arrays.lua`, shown in full above.

### The first numbers

The Chapter 17 code with only the clock, the benchmark and the savepoints added (these runs, and the
ones after the fixes, were made one after the other on the same machine):

```text
$ luajit bench/run.lua
insert 20000 entries            891.3 ms
export 20000 entries            153.5 ms
list 20000 entries               71.8 ms
search 'words'                  375.5 ms
```

Search finds all 20000 entries, so it's `list`'s work plus the full-text match. Why is it five times
slower? The profile says:

```text
$ luajit bench/run.lua -p search
search 'words'                  369.4 ms
43%  db.lua:prepare
24%  db.lua:step
 9%  db.lua:row
 8%  db.lua:(for generator)
 4%  commands.lua:format_row
 3%  run.lua:measure
 3%  entry.lua:to_entry
```

Almost half the time goes to `prepare`, compiling SQL, yet a search should prepare one statement.
Look at Chapter 17's `Store:search`:

```lua
  for row in self.db:rows([[
      SELECT rowid AS id, snippet(search, -1, '[', ']', '...', 8) AS snippet
      FROM search WHERE search MATCH ? ORDER BY rank]], { query }) do
    local entry = self:get(row.id)
    entry.snippet = row.snippet
    found[#found + 1] = entry
  end
```

The query returns ids, then `self:get(row.id)` runs a second query per match: 20001 queries for one
search. This is the **N+1 query problem**, a very common performance bug in database code.

### `src/stash/store.lua`: one query

Let SQLite join the full-text table with `entries` and return whole entries at once. Split the
column list out of `SELECT` so `search` can use it too:

```lua
-- Every query that returns entries selects these columns. The tags come
-- along as one comma-separated string.
local COLUMNS = [[
  e.id, e.url, e.title, e.note, e.created,
  (SELECT group_concat(tag) FROM tags WHERE entry_id = e.id) AS tags
]]
local SELECT = "SELECT " .. COLUMNS .. " FROM entries e "

local function to_entry(row)
  row.tags = util.split(row.tags or "", ",")
  return Entry.new(row)
end
```

and use it in `search`:

```lua
-- Full-text search, best matches first. Each entry gets a `snippet`
-- field: a few words of context with the matches in [brackets].
function Store:search(text)
  local query = Store.fts_query(text)
  local found = {}
  if query == "" then
    return found
  end
  -- One query does it all; fetching each entry with get() would cost a
  -- query per match (see Chapter 18).
  for row in self.db:rows("SELECT " .. COLUMNS .. [[,
        snippet(search, -1, '[', ']', '...', 8) AS snippet
      FROM search JOIN entries e ON e.id = search.rowid
      WHERE search MATCH ? ORDER BY rank]], { query }) do
    local entry = to_entry(row)
    entry.snippet = row.snippet
    found[#found + 1] = entry
  end
  return found
end
```

`search.rowid` is the entry id (`Store:add` inserts it that way), so `JOIN entries e ON e.id =
search.rowid` pairs each match with its entry.

### `src/stash/db.lua`: column names once

The profile also showed `row` at 9%. For every row, `Stmt:row` converted each column name from a C
string with `ffi.string`, the same names each time. A new `Stmt:columns` does it once, and `row`
takes the result. Replace `Stmt:row` with these two functions:

```lua
-- The column names of the result, as a Lua array.
function Stmt:columns()
  local names = {}
  for i = 0, S.sqlite3_column_count(self) - 1 do      -- columns count from 0
    names[i + 1] = ffi.string(S.sqlite3_column_name(self, i))
  end
  return names
end

-- The current row as a Lua table. NULL columns are simply absent.
-- Pass the result of columns() when reading many rows, so the names
-- are converted to Lua strings once rather than once per row.
function Stmt:row(names)
  names = names or self:columns()
  local row = {}
  for i = 0, #names - 1 do
    local name = names[i + 1]
    local kind = S.sqlite3_column_type(self, i)
    if kind == S.SQLITE_INTEGER then
      row[name] = tonumber(S.sqlite3_column_int64(self, i))
    elseif kind == S.SQLITE_FLOAT then
      row[name] = S.sqlite3_column_double(self, i)
    elseif kind == S.SQLITE_TEXT then
      -- Ask for the text before its length, as the SQLite docs advise.
      local text = S.sqlite3_column_text(self, i)
      row[name] = ffi.string(text, S.sqlite3_column_bytes(self, i))
    elseif kind == S.SQLITE_BLOB then
      local data = S.sqlite3_column_blob(self, i)
      row[name] = ffi.string(data, S.sqlite3_column_bytes(self, i))    -- may hold zero bytes
    end
  end
  return row
end
```

`row()` without arguments still works, so `Db:first` doesn't change. `Db:rows` reads the names once
per query:

```lua
-- Iterates over the rows of a query, each one a table keyed by column name.
function Db:rows(sql, params)
  local stmt = self:prepare(sql):bind(params)
  local names = stmt:columns()               -- the same for every row
  return function()
    if stmt:step() then
      return stmt:row(names)
    end
    stmt:finalize()
  end
end
```

### `src/stash/json.lua`: a string buffer

The export profile was led by `rows` (the column names again) and `encode_string`:

```text
$ luajit bench/run.lua -p export
export 20000 entries            151.9 ms
26%  db.lua:rows
24%  json.lua:encode_string
14%  db.lua:step
 9%  json.lua:encode_table
 5%  json.lua:encode
 5%  util.lua:split
 5%  entry.lua:to_entry
 4%  json.lua:write_array
 4%  json.lua:14
```

`json.lua:14` is `escape_char`, the Lua function `gsub` called for every character to escape. Three
changes to the encoder:

- The escape table is filled once, for every control character, so `gsub` looks each match up in the
  table: no Lua call per match.
- `find` first checks for anything to escape. Most strings have nothing, so `gsub` and its copy are
  skipped.
- The pieces go into one reused `string.buffer` instead of a table joined by `table.concat`.

Load the buffer library at the top:

```lua
local buffer = require("string.buffer")    -- LuaJIT's string builder
```

Replace `escape_char` and `encode_string`:

```lua
local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

-- The other control characters (what %c matches: bytes 0-31 and 127)
-- become \u00XX. Filling the table once, up front, lets gsub look each
-- match up in it instead of calling a Lua function per match.
for byte = 0, 127 do
  local c = string.char(byte)
  if (byte < 32 or byte == 127) and not ESCAPES[c] then
    ESCAPES[c] = ("\\u%04x"):format(byte)
  end
end

local function encode_string(s, out)
  -- %c matches control characters. Bytes >= 128 (UTF-8) pass unchanged.
  -- Most strings need no escaping at all: then skip gsub and its copy.
  if s:find('[%c"\\]') then
    s = s:gsub('[%c"\\]', ESCAPES)
  end
  out:put('"', s, '"')
end
```

And change `encode_table`, `encode` and `M.encode` to `put` into the buffer:

```lua
local function encode_table(t, out)
  if is_array(t) then
    out:put("[")
    for i, v in ipairs(t) do
      if i > 1 then out:put(",") end
      encode(v, out)
    end
    out:put("]")
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
  out:put("{")
  for i, k in ipairs(keys) do
    if i > 1 then out:put(",") end
    encode_string(k, out)
    out:put(":")
    encode(t[k], out)
  end
  out:put("}")
end

function encode(value, out)
  local kind = type(value)
  if kind == "string" then
    encode_string(value, out)
  elseif kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("JSON cannot represent " .. tostring(value))
    end
    if value % 1 == 0 and math.abs(value) < 2^53 then
      out:put(("%d"):format(value))
    else
      out:put(("%.17g"):format(value))
    end
  elseif kind == "boolean" then
    out:put(tostring(value))
  elseif kind == "nil" then
    out:put("null")
  elseif kind == "table" then
    encode_table(value, out)
  else
    error("JSON cannot represent a " .. kind)
  end
end

-- One buffer, reused by every call: its memory is allocated once
-- instead of once per call.
local out = buffer.new()

function M.encode(value)
  out:reset()
  encode(value, out)
  return out:tostring()
end
```

`write_array` doesn't change. Reusing one buffer is safe because `M.encode` returns a string before
anything else uses the buffer.

### The numbers after

```text
$ luajit bench/run.lua
insert 20000 entries            863.3 ms
export 20000 entries            136.9 ms
list 20000 entries               72.4 ms
search 'words'                  145.0 ms
```

- **search**: 375 → 145 ms, about 2.5 times faster (2.5–3 times across runs). That was the N+1
  queries.
- **export**: 153 → about 135 ms. A modest win: most of the time is in SQLite and building entries.
- **list** and **insert** barely move; nothing in this step targeted them.

The search profile now has no `prepare` at all:

```text
$ luajit bench/run.lua -p search
search 'words'                  143.8 ms
55%  db.lua:step
17%  db.lua:(for generator)
 8%  run.lua:measure
 5%  util.lua:split
 3%  commands.lua:format_row
 3%  commands.lua:run
 3%  entry.lua:to_entry
```

What's left is `step` (SQLite working) and building entries, which is where the time should go.

### What the JIT thinks of stash

`-jv` shows what didn't compile. The run prints hundreds of lines, so count the aborts:

```text
$ luajit -jv bench/run.lua list 2>&1 | grep -E 'NYI|blacklisted|disabled' | sort | uniq -c | sort -rn | head -5
     11 [TRACE --- db.lua:88 -- blacklisted at db.lua:219]
      9 [TRACE --- store.lua:101 -- NYI: bytecode FNEW   at store.lua:116]
      4 [TRACE --- (4/1) db.lua:187 -- JIT compilation disabled for function at db.lua:219]
      4 [TRACE --- (1/1) db.lua:187 -- JIT compilation disabled for function at db.lua:219]
      1 [TRACE --- (9/stitch) entry.lua:19 -- NYI: bytecode FNEW   at store.lua:116]
```

- `db.lua:219` is `Stmt.step`, turned off on purpose in Chapter 16. Every trace that reaches it stops
  there: the `Db:rows` iterator (line 88) and the loop in `Stmt:bind` (line 187).
- `NYI: bytecode FNEW at store.lua:116` is the closure `Store:add` passes to `db:transaction` (the
  line number is where the closure ends).

Should we fix them? Turning the JIT back on for `step` changes the timings by no more than
run-to-run noise (about ±5%). That isn't worth a crash risk. Removing the closure from `Store:add` is
exercise 2; it silences the warning but doesn't save time. Even `luajit -joff bench/run.lua` is only
15 to 75% slower: most of `stash`'s time is in SQLite, which is C. A profile tells you this before
you spend an afternoon on it.

### Tests

`test/db_test.lua` checks that transactions nest. Add after the "a failed transaction leaves no
trace" test:

```lua
test("transactions nest", function()
  local db = memory_db()
  db:transaction(function()
    db:run("INSERT INTO t (n) VALUES (1)")
    pcall(db.transaction, db, function()     -- an inner failure is undone...
      db:run("INSERT INTO t (n) VALUES (2)")
      error("boom")
    end)
    db:transaction(function()                -- ...an inner success is kept
      db:run("INSERT INTO t (n) VALUES (3)")
    end)
  end)
  eq(db:first("SELECT group_concat(n) AS ns FROM t").ns, "1,3")
  raises(function()                          -- the outer one undoes it all
    db:transaction(function()
      db:transaction(function() db:run("INSERT INTO t (n) VALUES (4)") end)
      error("boom")
    end)
  end, "boom")
  eq(db:first("SELECT count(*) AS n FROM t").n, 2)
end)
```

`test/store_test.lua` checks that search returns whole entries, ids and tags included. Change the
search test to:

```lua
test("search ranks matches and needs every word", function()
  local store = sample_store()
  local found = store:search("tables")
  eq(#found, 2)
  local beta = store:search("tables closures")[1]
  eq(beta.title, "Beta")
  eq(beta.id, 2)
  same(beta.tags, { "y" })                                     -- whole entries come back
  eq(#store:search("tables gamma"), 0)
  eq(store:search("clos*")[1].snippet, "the second page talks about tables and [closures]")
  eq(store:search("second")[1].snippet, "[second]")             -- the note matches too
end)
```

### Checkpoint

From `project/ch18/` (your timings will differ; the `-jv` counts can too):

```console
$ luajit test/run.lua
util_test        3 tests, 0 failed
cli_test         5 tests, 0 failed
entry_test       4 tests, 0 failed
iter_test        4 tests, 0 failed
config_test      4 tests, 0 failed
commands_test    6 tests, 0 failed
json_test        6 tests, 0 failed
html_test        5 tests, 0 failed
fs_test          3 tests, 0 failed
term_test        3 tests, 0 failed
buffer_test      3 tests, 0 failed
db_test          10 tests, 0 failed
store_test       11 tests, 0 failed
fetch_test       3 tests, 0 failed
compress_test    4 tests, 0 failed
e2e_test         5 tests, 0 failed

79 passed, 0 failed
# timings below vary from run to run and machine to machine
$ luajit bench/run.lua
insert 20000 entries            904.5 ms
export 20000 entries            133.5 ms
list 20000 entries               70.8 ms
search 'words'                  142.1 ms
$ luajit bench/run.lua -p search
search 'words'                  144.3 ms
52%  db.lua:step
16%  db.lua:(for generator)
 7%  run.lua:measure
 7%  entry.lua:to_entry
 6%  util.lua:split
 4%  commands.lua:run
 4%  util.lua:truncate
$ luajit bench/run.lua -p export
export 20000 entries            139.8 ms
27%  json.lua:encode_string
15%  util.lua:split
13%  db.lua:rows
10%  json.lua:write_array
10%  db.lua:step
 8%  json.lua:encode_table
 8%  entry.lua:to_entry
 7%  json.lua:encode
$ luajit bench/arrays.lua
fill table                       2.72 ms
fill table.new                   2.20 ms
fill double[N]                   2.25 ms
sum table                        0.45 ms
sum double[N]                    0.57 ms
1000000 numbers: table 7813 KB, double[] 7813 KB, uint8_t[] 977 KB
100000 points: tables 11719 KB, struct[] 1563 KB
$ luajit -jv bench/run.lua list 2>&1 | grep -E 'NYI|blacklisted|disabled' | sort | uniq -c | sort -rn | head -5
     11 [TRACE --- db.lua:88 -- blacklisted at db.lua:219]
      9 [TRACE --- store.lua:101 -- NYI: bytecode FNEW   at store.lua:116]
      4 [TRACE --- (4/1) db.lua:187 -- JIT compilation disabled for function at db.lua:219]
      4 [TRACE --- (1/1) db.lua:187 -- JIT compilation disabled for function at db.lua:219]
      1 [TRACE --- (9/stitch) entry.lua:19 -- NYI: bytecode FNEW   at store.lua:116]
$ export STASH_HOME=demo STASH_NOW=1767225600
$ PAGES=file://$PWD/test/fixtures
$ ./stash add $PAGES/lua.html -t lua,lang
added #1 The Programming Language Lua
$ ./stash add $PAGES/luajit.html -t lua,jit
added #2 LuaJIT: a Just-In-Time Compiler & FFI
$ ./stash search compiler
  2  LuaJIT: a Just-In-Time Compiler &...  jit,lua           2026-01-01
     ...a Just-In-Time [Compiler] & FFI LuaJIT runs...
$ LUA_PATH="src/?.lua" luajit -e 'local clock = require("stash.clock") local t = clock.now() print(clock.now() >= t, type(t))'
true	number
```

The complete project at this point is in `project/ch18/`.

## Summary

- LuaJIT interprets first, counts, and compiles hot loops and functions into **traces**: one recorded
  path with **guards** for its assumptions. A failing guard takes a **side exit**; frequent exits get
  **side traces**.
- `-jv` lists traces and aborts, `-jdump` shows bytecode, IR and machine code, `-jp` profiles
  (`F` functions, `l` lines, `v` VM states). `jit.p.start`/`stop` profiles part of a program.
- Creating closures (`FNEW`) aborts a trace. Pattern functions are stitched: called, not compiled.
  Check with `-jv`; the NYI list changes.
- Build strings with `string.buffer` (or `table.concat`), never `..` in a loop. Reuse buffers.
- With the JIT, Lua tables are as fast as C arrays for numbers; C arrays save memory for bytes and
  records.
- Caching globals in locals only matters for interpreted code.
- `jit.off(f)` keeps `f` in the interpreter. The JIT can **sink** short-lived tables away entirely.
- Benchmarks: use the results, run several rounds, keep the best, collect garbage first, change one
  thing at a time; measure CPU time with `os.clock` or real time with `clock_gettime`.
- Profile first. In `stash` the big win was an N+1 query, not the JIT.

## Exercises

1. Run `luajit -Ohotloop=5 -jv examples/ch18/hot.lua`. What changes in the output, and why?

   <details><summary>Solution</summary>

   ```console
   $ luajit -Ohotloop=5 -jv examples/ch18/hot.lua
   [TRACE   1 hot.lua:5 loop]
   385
   333833500
   ```

   `-Ohotloop=5` lowers the threshold from 56, so the first call's 10 iterations are enough: the
   trace is compiled during the first call, and its line comes before `385`. The second call reuses
   trace 1.

   </details>

2. `-jv` reports `NYI: bytecode FNEW` in `Store:add`. Remove the closure: `Db:transaction(fn, ...)`
   passes its extra arguments to `fn`. Does `insert` get faster?

   <details><summary>Solution</summary>

   In `src/stash/store.lua`:

   ```lua
   -- The work of add(): a plain function, so add() makes no closure.
   local function add_rows(db, entry, text, page)
     db:run("INSERT INTO entries (url, title, note, created) VALUES (:url, :title, :note, :created)",
            { url = entry.url, title = entry.title, note = entry.note, created = entry.created })
     entry.id = db:last_id()
     for _, tag in ipairs(entry.tags) do
       db:run("INSERT INTO tags (entry_id, tag) VALUES (?, ?)", { entry.id, tag })
     end
     db:run("INSERT INTO search (rowid, title, url, note, tags, body) VALUES (?, ?, ?, ?, ?, ?)",
            { entry.id, entry.title, entry.url, entry.note, entry:tag_string(" "), text or "" })
     if page then
       db:run("INSERT INTO pages (entry_id, size, data) VALUES (?, ?, ?)",
              { entry.id, #page, Db.blob(compress.pack(page)) })
     end
   end

   function Store:add(entry, text, page)
     self.db:transaction(add_rows, self.db, entry, text, page)
     return entry
   end
   ```

   The tests still pass and the FNEW line is gone from `-jv`, but the time isn't: `insert` stays at
   about 870–890 ms. The insert profile shows why:

   ```text
   insert 20000 entries            907.3 ms
   38%  db.lua:exec
   26%  db.lua:step
   19%  db.lua:prepare
    4%  db.lua:run
    4%  entry.lua:new
    3%  db.lua:bind
    3%  store.lua:103
   ```

   The time is in SQLite. A trace abort only matters when the code around it is hot.

   </details>

3. The insert profile shows `exec` (the savepoints) and `prepare` taking over half the time: each
   `Db:run` recompiles its SQL, though `Store:add` sends the same few statements 20000 times. Add a
   **statement cache** to `Db:run`: keep prepared statements by SQL text and reuse them with
   `sqlite3_reset`. Use `run` for the savepoint statements too. Hints: a `Db` is a cdata pointer and
   can't hold fields, so keep the cache in a weak-keyed table indexed by the `Db`
   ([Chapter 7](07-metatables-and-objects.md)). Reused statements keep their old parameters;
   `sqlite3_clear_bindings` resets them to `NULL`.

   <details><summary>Solution</summary>

   Declare the function in `src/stash/ffi/sqlite.lua`, after `sqlite3_reset`:

   ```c
   int sqlite3_clear_bindings(sqlite3_stmt *stmt);
   ```

   In `src/stash/db.lua`, put the cache before `Db:close`, which now finalizes the cached statements:

   ```lua
   -- Prepared statements for run(), per database: cache[db][sql] = stmt.
   -- Weak keys: when a Db is collected, its statements go too.
   local cache = setmetatable({}, { __mode = "k" })

   function Db:close()
     for _, stmt in pairs(cache[self] or {}) do
       stmt:finalize()
     end
     cache[self] = nil
     ffi.gc(self, nil)                          -- no finalizer: we close it now
     S.sqlite3_close_v2(self)
   end
   ```

   Replace `Db:run`:

   ```lua
   -- Runs a statement that returns no rows; returns the number of rows changed.
   -- The statement is compiled once, then reset and reused on later calls.
   function Db:run(sql, params)
     local stmts = cache[self]
     if not stmts then
       stmts = {}
       cache[self] = stmts
     end
     local stmt = stmts[sql]
     if not stmt then
       stmt = self:prepare(sql)
       stmts[sql] = stmt
     end
     S.sqlite3_clear_bindings(stmt)             -- parameters not given: NULL again
     stmt:bind(params)
     local rc = S.sqlite3_step(stmt)
     S.sqlite3_reset(stmt)                      -- ready for the next call
     if rc ~= S.SQLITE_DONE and rc ~= S.SQLITE_ROW then
       self:check(rc)
     end
     return S.sqlite3_changes(self)
   end
   jit.off(Db.run)                              -- it calls sqlite3_step too
   ```

   And in `Db:transaction`, change the four `self:exec(...)` calls to `self:run(...)`.

   - `run` can't use `Stmt:step`, which finalizes the statement on an error. A cached statement must
     stay alive, so `run` calls `sqlite3_step` itself and needs its own `jit.off` (see Chapter 16).
   - `Stmt:db()` returns a new cdata for the same handle, which would be a different key. Only call
     `run` on the `Db` from `Db.open`.

   All 79 tests pass, and `insert` drops from about 900 ms to about 650 ms.

   </details>

4. Add benchmarks for the `tags` and `stats` commands to `bench/run.lua`. How long do they take, and
   what does `luajit bench/run.lua -p stats` show? Why?

   <details><summary>Solution</summary>

   Add two lines to `BENCHMARKS`:

   ```lua
     { "tags", 5, function(store) run_command(store, { "tags" }) end },
     { "stats", 5, function(store) run_command(store, { "stats" }) end },
   ```

   ```text
   $ luajit bench/run.lua
   insert 20000 entries            875.0 ms
   export 20000 entries            132.4 ms
   list 20000 entries               76.4 ms
   search 'words'                  150.6 ms
   tags                              1.2 ms
   stats                             0.9 ms
   $ luajit bench/run.lua -p stats
   stats                             0.9 ms
   [No samples collected]
   ```

   Both take about a millisecond: SQLite does the counting and returns a few rows. The profiler
   samples every 10 ms, so five 1 ms runs give it nothing to count. For work this short, raise the
   number of rounds, or sample more often with `jit.p.start("Fi1")` (every 1 ms). Either way, a
   millisecond isn't worth optimizing.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-18--performance-and-the-jit)
