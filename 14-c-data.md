# Chapter 14 — C Data

[Chapter 13](13-ffi-basics.md) called C functions with numbers and strings. Real C APIs also want
structs, arrays and pointers: they fill in structs you hand them, return results through pointers,
and give you memory to free. This chapter creates C data from Lua (arrays, structs, unions,
pointers, memory you own and memory C owns), gives C types methods with `ffi.metatype`, and covers
the lifetime rules that keep a program from crashing. With these, any C API is within reach.

Then `stash` uses two of them: `list` asks the terminal how wide it is (a struct filled in by
`ioctl`), and a new `Buffer` type, a growable byte array in C memory, gets ready for Chapter 16.

Previous: [Chapter 13 — FFI basics](13-ffi-basics.md). Next: [Chapter 15 — Wrapping SQLite](15-wrapping-sqlite.md).

## ffi.new: scalars, arrays, initializers

`ffi.new(ctype, ...)` allocates a C value and returns it as cdata. The garbage collector owns the
memory and frees it once no Lua variable refers to the cdata.

`examples/ch14/new.lua`

```lua
-- ffi.new creates C values owned by Lua's garbage collector.

local ffi = require("ffi")

-- A scalar: a "boxed" C int. You can read it, but not change it.
local n = ffi.new("int", 42)
print(type(n), tonumber(n), n + 1)

-- To hold one C value you can change, use an array of one.
local d = ffi.new("double[1]", 2.5)
d[0] = d[0] * 2
print(d[0])

-- Arrays: fixed size, zero-filled, indexed from 0.
local a = ffi.new("int[5]")
print(a[0], a[4], ffi.sizeof(a))
for i = 0, 4 do a[i] = i * i end
print(a[0], a[1], a[2], a[3], a[4])

-- Initializers: a list of values or a Lua table.
local b = ffi.new("int[5]", 1, 2)          -- the rest stay 0
local c = ffi.new("int[5]", { 7, 8, 9 })
local e = ffi.new("int[5]", 3)             -- ONE initializer fills every element
print(b[0], b[1], b[2], "|", c[0], c[2], c[4], "|", e[0], e[4])

-- VLA: "[?]" leaves the size open; pass it as the first argument.
local size = 3 + 2
local bytes = ffi.new("uint8_t[?]", size)
print(ffi.sizeof(bytes), ffi.typeof(bytes))
local bytes2 = ffi.new("uint8_t[?]", 4, { 1, 2, 3, 4 })
print(bytes2[3])

-- Out of range writes are NOT checked. bytes[100] = 1 would corrupt memory.

-- Character arrays and strings:
local name = ffi.new("char[16]", "stash")  -- copies the bytes and a terminating 0
print(ffi.string(name), ffi.sizeof(name))

-- Creating the same type again and again? Parse it once with ffi.typeof:
local int_array = ffi.typeof("int[?]")
local x = int_array(1000)
print(ffi.sizeof(x))
```

```console
$ luajit examples/ch14/new.lua
cdata	42	43LL
5
0	0	20
0	1	4	9	16
1	2	0	|	7	9	0	|	3	3
5	ctype<unsigned char [?]>
4
stash	16
4000
```

- **Scalars.** `ffi.new("int", 42)` is a *boxed* int: readable but not changeable (Lua has no
  `*n = 5`). Arithmetic on it gives a 64-bit integer (`43LL`), so use `tonumber`. For one C value
  that can change, make an array of one, `ffi.new("double[1]")`, and use `[0]`. That is how out
  parameters work (below).
- **Arrays** are zero-filled and indexed **from 0**, like C: an `int[5]` has `a[0]` to `a[4]`.
  Lua's `ipairs` and `#` don't apply.
- **Initializers.** Extra arguments, or a Lua table, fill elements in order; the rest stay 0. A
  single value (or a table with one value) fills *every* element: `ffi.new("int[5]", 3)` is five 3s.
- **VLAs** (variable-length arrays). `"uint8_t[?]"` leaves the size open. The first argument after
  the type is the element count; initializers follow it.
- **No bounds checks.** `bytes[100] = 1` on a 5-byte array writes into whatever memory comes next.
  It may crash now, later, or never.
- A `char[16]` initialized with a Lua string gets the bytes and a terminating `\0`. `ffi.string`
  reads them back.
- `ffi.typeof("int[?]")` parses a type once and returns a *ctype* you call like a constructor,
  faster than parsing the type string on every `ffi.new`.

## Structs, nested structs and unions

`examples/ch14/structs.lua`

```lua
-- Structs, nested structs and unions.

local ffi = require("ffi")
ffi.cdef [[
typedef struct point { double x, y; } point;
typedef struct {
  point min, max;          /* nested structs */
  char label[8];
} box;
typedef union {
  uint32_t u;
  float f;
  uint8_t bytes[4];
} word;
]]

-- Fields are read and written with ".", like a table.
local p = ffi.new("point", 1, 2)              -- positional initializers
p.x = p.x + 10
print(p.x, p.y)

-- A table initializer can name the fields; nested structs take nested tables.
local b = ffi.new("box", { min = { 0, 0 }, max = { x = 4, y = 3 }, label = "room" })
print(b.max.x - b.min.x, b.max.y - b.min.y, ffi.string(b.label))

-- b.max is not a copy: it is a reference into b's memory.
local corner = b.max
corner.x = 100
print(b.max.x)

-- Unknown fields are errors, not nil:
print(pcall(function() return p.z end))

-- A union stores all its fields in the same bytes.
local w = ffi.new("word")
w.f = 1.0
print(("float 1.0 = 0x%08x"):format(w.u), w.bytes[0], w.bytes[3])
print(ffi.sizeof("word"))
```

```console
$ luajit examples/ch14/structs.lua
11	2
4	3	room
100
false	examples/ch14/structs.lua:32: 'struct point' has no member named 'z'
float 1.0 = 0x3f800000	0	63
4
```

- Struct fields read and write with `.`, like table fields. Initialize them in declaration order
  (`ffi.new("point", 1, 2)`) or by name with a table.
- A nested struct takes a nested table, in either style: `{ 0, 0 }` or `{ x = 4, y = 3 }`.
- `b.max` is not a copy but a *reference* into `b`'s memory, so changing `corner.x` changes `b`. A
  number or pointer field, like `p.x`, is read as a value.
- Unlike a table, a struct has a fixed set of fields: reading `p.z` is an error, not `nil`.
- A **union** puts all its fields at the same address. Writing `w.f` and reading `w.u` shows the
  bits of the float `1.0`. Its size is that of its largest field.

Naming the struct (`typedef struct point {...} point`) gives error messages a readable name; an
anonymous struct shows up as something like `struct 102`.

## Out parameters

A C function returns one value. To return more, it takes a pointer and writes through it. In C
you'd pass `&end`; Lua has no `&`, so you pass a one-element array, which converts to a pointer to
its first element.

`examples/ch14/outparam.lua`

```lua
-- Out parameters: C returns extra results by writing through a pointer.

local ffi = require("ffi")
ffi.cdef [[
long strtol(const char *s, char **endptr, int base);
]]

-- strtol(s, &end, base) parses a number and sets *end to the first
-- character it did not use. In Lua, a one-element array plays "&end".
local function parse_int(s, base)
  local endp = ffi.new("char *[1]")
  local n = ffi.C.strtol(s, endp, base or 10)
  -- endp[0] points into s; subtracting gives how many bytes were used.
  local used = endp[0] - ffi.cast("const char *", s)
  return tonumber(n), s:sub(used + 1)
end

print(parse_int("42 apples"))
print(parse_int("ff", 16))
print(parse_int("0x1F", 16))
print(parse_int("nope"))

-- The same idea with an int: let C fill it.
ffi.cdef [[
int sscanf(const char *s, const char *format, ...);
]]
local w, h = ffi.new("int[1]"), ffi.new("int[1]")
local count = ffi.C.sscanf("1920x1080", "%dx%d", w, h)
print(count, w[0], h[0])
```

```console
$ luajit examples/ch14/outparam.lua
42	 apples
255	
31	
0	nope
2	1920	1080
```

- `strtol(s, endptr, base)` parses a number and stores in `*endptr` a pointer to the first unused
  character. `char *[1]` is "an array of one `char *`".
- `endp[0] - ffi.cast("const char *", s)` subtracts two pointers: the number of characters parsed.
  For `"nope"` it is 0 and `strtol` returns 0; only `endptr` tells "0" from "not a number".
- `sscanf` writes two ints through two pointers and returns how many it filled.

Structs work the same way: `ffi.new("struct winsize")` is memory for C to fill in, which is how
`stash` gets the terminal size below.

## Pointers and ffi.cast

`examples/ch14/pointers.lua`

```lua
-- Pointers: arithmetic, indexing, casts.

local ffi = require("ffi")

local arr = ffi.new("int[4]", { 10, 20, 30, 40 })

-- An array converts to a pointer to its first element.
local p = ffi.cast("int *", arr)
print(p[0], p[3])          -- indexing a pointer: p[i] is *(p + i)

-- Arithmetic moves in units of the pointed-to type (4 bytes for int).
local q = p + 2
print(q[0], q[-1])         -- negative indexes are fine if the memory is yours
print(q - p)               -- difference of two pointers, in elements
print(q > p, p == arr)     -- comparisons work on addresses

-- Write through a pointer:
q[1] = 99
print(arr[3])

-- ffi.cast reinterprets: here, the same bytes seen as single bytes.
local bytes = ffi.cast("uint8_t *", arr)
print(bytes[0], bytes[1], bytes[4])   -- 10 = 0x0a, little-endian

-- Casting numbers: same bits, different meaning, like C.
print(tonumber(ffi.cast("int32_t", 0xffffffff)), tonumber(ffi.cast("uint32_t", -1)))
local big = ffi.new("int", 300)
print(tonumber(ffi.cast("uint8_t", big)))   -- keeps the low 8 bits: 300 - 256

-- A pointer to a struct uses "." for fields too (no "->" in Lua).
ffi.cdef [[ typedef struct pair { int a, b; } pair; ]]
local pairs_arr = ffi.new("pair[2]", { { 1, 2 }, { 3, 4 } })
local pp = ffi.cast("pair *", pairs_arr) + 1
print(pp.a, pp.b, pp[0].a)

-- Pointers can be turned into numbers (addresses), e.g. for debugging.
print(ffi.cast("uintptr_t", q) - ffi.cast("uintptr_t", p))  -- bytes, not elements
```

```console
$ luajit examples/ch14/pointers.lua
10	40
30	20
2
true	true
99
10	0	20
-1	4294967295
44
3	4	3
8ULL
```

- `p[i]` reads the element `i` places after `p`, like `*(p + i)` in C. Lua has no `*` operator, so
  `p[0]` is how you dereference.
- `p + 2` moves by two *elements*, not bytes: 8 bytes for an `int *`.
- Subtracting two pointers gives the distance in elements. Pointers compare with `==`, `<` and `>`.
- `ffi.cast(ctype, value)` converts like a C cast. Casting `int *` to `uint8_t *` shows the same
  memory as bytes: `10` is stored as `0a 00 00 00`, lowest byte first (see "Endianness").
- Number casts keep the bits and change their meaning, as in C: `0xffffffff` as `int32_t` is -1,
  `-1` as `uint32_t` is 4294967295. Casting to a smaller type keeps the low bits.
- A pointer to a struct also uses `.` for fields; Lua has no `->`.
- Casting a pointer to `uintptr_t` gives its address as an integer; the difference is in bytes.

`ffi.cast` also turns the `void *` from functions like `malloc` into a typed pointer. It changes
only the type and doesn't check that the memory really holds that type.

## ffi.copy and ffi.fill

`examples/ch14/copyfill.lua`

```lua
-- ffi.copy and ffi.fill: memcpy and memset for Lua.

local ffi = require("ffi")

local buf = ffi.new("char[16]")

-- ffi.copy(dst, str) copies a Lua string plus its terminating zero.
ffi.copy(buf, "hello")
print(ffi.string(buf))

-- ffi.copy(dst, src, len) copies exactly len bytes, from a string or a pointer.
ffi.copy(buf + 5, ", world", 7)
print(ffi.string(buf))          -- up to the first zero (ffi.new zero-filled buf)
print(ffi.string(buf, 12))      -- with a length: exactly 12 bytes

-- ffi.fill(dst, len, byte) sets len bytes; the byte defaults to 0.
ffi.fill(buf, 5, string.byte("*"))
print(ffi.string(buf, 12))
ffi.fill(buf, 16)
print(#ffi.string(buf), #ffi.string(buf, 16))

-- Copy between two C arrays:
local a = ffi.new("int[3]", { 1, 2, 3 })
local b = ffi.new("int[3]")
ffi.copy(b, a, ffi.sizeof(a))   -- the length is in bytes!
print(b[0], b[1], b[2])
```

```console
$ luajit examples/ch14/copyfill.lua
hello
hello, world
hello, world
*****, world
0	16
1	2	3
```

- `ffi.copy(dst, str)` copies a Lua string and its terminating `\0`, like `strcpy`.
- `ffi.copy(dst, src, len)` copies exactly `len` bytes, like `memcpy`. `src` can be a Lua string,
  pointer or array.
- `ffi.fill(dst, len, byte)` sets `len` bytes to `byte` (default 0), like `memset`.
- Lengths are **bytes**: to copy three ints, pass `ffi.sizeof(a)` (12), not 3.
- `buf + 5` is pointer arithmetic: the copy starts 5 bytes into `buf`.

Neither function checks sizes: copying 20 bytes into a `char[16]` overwrites the memory after it.

## By value and by reference

`examples/ch14/byvalue.lua`

```lua
-- By value vs. by reference.

local ffi = require("ffi")
ffi.cdef [[
typedef struct { int quot; int rem; } div_t;
div_t div(int numerator, int denominator);
typedef struct vec { double x, y; } vec;
]]

-- A C function can return a whole struct by value. LuaJIT hands you
-- a new cdata holding the copy.
local r = ffi.C.div(17, 5)
print(r.quot, r.rem)

-- In Lua, assigning a cdata copies the reference, not the bytes.
local a = ffi.new("vec", 1, 2)
local b = a
b.x = 99
print(a.x)                 -- 99: a and b are the same object

-- To copy the bytes, make a new cdata initialized from the old one.
local c = ffi.new("vec", a)
c.x = 0
print(a.x, c.x)

-- Assigning a struct into a struct field or array slot copies bytes too.
local list = ffi.new("vec[2]")
list[0] = a
a.y = -1
print(list[0].x, list[0].y, a.y)
```

```console
$ luajit examples/ch14/byvalue.lua
3	2
99
99	0
99	2	-1
```

- C's `div` returns a struct **by value**; LuaJIT copies the result into a new cdata.
- `local b = a` doesn't copy the struct. As with tables, both names refer to the same object.
- `ffi.new("vec", a)` initializes a new struct from an existing one, copying the bytes.
- Storing a struct into an array element or struct field also copies the bytes, so later changes
  to `a` don't reach `list[0]`.

A struct **pointer** (`vec *`) refers to memory elsewhere, possibly owned by C. Most C APIs take
structs by pointer, and LuaJIT passes a struct cdata as a pointer to it when a function asks for
one, as with `ioctl` below.

## ffi.metatype: methods on C types

`ffi.metatype(ctype, mt)` attaches a metatable to a struct or union type. It works like
`setmetatable` from [Chapter 7](07-metatables-and-objects.md), but for every object of that C
type, wherever it comes from.

`examples/ch14/metatype.lua`

```lua
-- ffi.metatype: give a C type methods and operators.

local ffi = require("ffi")
ffi.cdef [[ typedef struct vec2 { double x, y; } vec2; ]]

local new                 -- the constructor, assigned below

local Vec2 = {}
Vec2.__index = Vec2       -- methods are looked up here, like a class

function Vec2.length(v) return math.sqrt(v.x * v.x + v.y * v.y) end
function Vec2.scale(v, k) return new(v.x * k, v.y * k) end

Vec2.__add = function(a, b) return new(a.x + b.x, a.y + b.y) end
Vec2.__eq = function(a, b) return a.x == b.x and a.y == b.y end
Vec2.__tostring = function(v) return ("(%g, %g)"):format(v.x, v.y) end

-- ffi.metatype returns a constructor: calling it is like ffi.new("vec2", ...).
-- From now on the metatable belongs to the type: don't change Vec2 anymore.
new = ffi.metatype("vec2", Vec2)

local a = new(3, 4)
local b = new(1, 1)
print(a:length(), tostring(a + b), tostring(b:scale(2)))
print(a == new(3, 4), a == b)

-- Every vec2 gets the methods, however it was made.
local arr = ffi.new("vec2[2]", { { 6, 8 } })
print(arr[0]:length())

-- Fields come first; __index is only asked about names that are not fields.
print(a.x, a.length ~= nil)

-- A second metatype call for the same type is an error.
print(pcall(ffi.metatype, "vec2", {}))
```

```console
$ luajit examples/ch14/metatype.lua
5	(4, 5)	(2, 2)
true	false
10
3	true
false	cannot change a protected metatable
```

- `ffi.metatype` returns a constructor: `new(3, 4)` is `ffi.new("vec2", 3, 4)` with the metatable
  attached.
- `__index` gives methods, `__add` and `__eq` operators, `__tostring` printing. All standard
  metamethods work, including `__len` for `#` and `__gc`, which `stash`'s `Buffer` uses below.
- The elements of `ffi.new("vec2[2]")` have methods too: the metatable belongs to the type.
- Real fields win: `__index` is consulted only for names that aren't fields.
- The association is **permanent**. A second `ffi.metatype` for the type fails, and you must not
  change the metatable or its `__index` table afterwards. That's why `new` is a local declared
  before the methods, not a field `Vec2.new` added later.
- A `__gc` metamethod runs when an object of the type is collected, like an automatic `ffi.gc`
  (next section) on every object the constructor makes.

## Memory you allocate: malloc, free and ffi.gc

`ffi.new` memory belongs to the garbage collector. Memory from C's `malloc` doesn't; the collector
doesn't know it exists. You must free it exactly once, and never use it afterwards.

`examples/ch14/gc.lua`

```lua
-- Who frees the memory? ffi.new vs. malloc + ffi.gc.

local ffi = require("ffi")
ffi.cdef [[
void *malloc(size_t size);
void free(void *ptr);
]]
local C = ffi.C

-- 1. ffi.new: the garbage collector owns the memory. Nothing to free.
local a = ffi.new("uint8_t[?]", 1024)
a[0] = 1

-- 2. malloc: C owns the memory. You must free it exactly once.
local p = ffi.cast("uint8_t *", C.malloc(1024))
assert(p ~= nil, "out of memory")
p[0] = 1
C.free(p)
p = nil                      -- don't keep a dangling pointer around

-- 3. ffi.gc attaches a finalizer: free is called when the cdata is collected.
local freed = 0
local function my_free(ptr)
  freed = freed + 1
  C.free(ptr)
end
local q = ffi.gc(ffi.cast("uint8_t *", C.malloc(64)), my_free)
q = nil
collectgarbage(); collectgarbage()
print("freed by gc:", freed)

-- 4. ffi.gc(ptr, nil) removes the finalizer: you take ownership back,
--    e.g. before freeing by hand or handing the pointer to C for good.
local r = ffi.gc(ffi.cast("uint8_t *", C.malloc(64)), my_free)
ffi.gc(r, nil)
my_free(r)                   -- freed once, by us
r = nil
collectgarbage(); collectgarbage()
print("total frees:", freed)
```

```console
$ luajit examples/ch14/gc.lua
freed by gc:	1
total frees:	2
```

- `malloc` returns a `void *` cdata, or `NULL` on failure, so check `p ~= nil` (never `if p`; see
  [Chapter 13](13-ffi-basics.md)).
- `ffi.gc(cdata, finalizer)` makes the collector call `finalizer(cdata)` when the cdata is
  collected. The usual form is `ffi.gc(ffi.C.malloc(n), ffi.C.free)`; we wrapped `free` only to
  count calls.
- `ffi.gc(p, nil)` removes the finalizer. Do that before freeing by hand, or the collector frees
  the memory a second time, and a double free can crash the program.
- Collection runs "eventually". The two `collectgarbage()` calls force it to show the effect.

Why `malloc` when `ffi.new` exists? Some memory must outlive Lua's references, be freed by C, or be
resized with `realloc`. `stash`'s `Buffer` grows, so it uses `realloc`.

## Lifetimes: keep it alive while C uses it

The collector frees a cdata once no *Lua* reference to it is left. It doesn't follow C pointers, so
a pointer to an array stored in a struct field doesn't keep the array alive.

`examples/ch14/lifetime.lua`

```lua
-- Lifetimes: keep memory alive while C (or a pointer) still uses it.

local ffi = require("ffi")
ffi.cdef [[
typedef struct item { const char *name; int *values; int count; } item;
]]

-- WRONG (don't do this): the arrays below are only referenced by the struct's
-- pointer fields. The GC does not follow C pointers, so it may free them
-- while `bad` still points at them.
--
--   local bad = ffi.new("item")
--   bad.values = ffi.new("int[3]", { 1, 2, 3 })   -- garbage right away!
--   bad.name = "temp" .. 1                        -- same for this string

-- RIGHT: keep a Lua reference ("anchor") for as long as the pointer is used.
local function new_item(name, values)
  local arr = ffi.new("int[?]", #values, values)
  local it = ffi.new("item", { name = name, values = arr, count = #values })
  return { c = it, anchors = { name, arr } }   -- the table keeps both alive
end

local x = new_item("scores", { 7, 8, 9 })
collectgarbage(); collectgarbage()           -- safe: the anchors hold on
local it = x.c
print(ffi.string(it.name), it.count, it.values[0] + it.values[1] + it.values[2])

-- A Lua string passed straight to a C function is only valid during that
-- call. Fine for strlen or setenv (which copies it); not fine if C keeps the
-- pointer for later, like putenv does. Then copy it into memory you own.
ffi.cdef [[ size_t strlen(const char *s); ]]
print(tonumber(ffi.C.strlen("only needed during the call")))
```

```console
$ luajit examples/ch14/lifetime.lua
scores	3	24
27
```

- In the "WRONG" code, the `int[3]` has no Lua reference after the assignment. The collector may
  free it at any time, leaving `bad.values` pointing at freed memory. Such bugs show up later, at
  random, as wrong data or crashes.
- The fix is an **anchor**: a Lua reference kept as long as the pointer is used. Here the returned
  table holds both the struct and what its pointers point to.
- Strings too: a string converted to `const char *` must stay referenced. A string literal is kept
  alive by the function containing it.
- Arguments to a C call stay alive until it returns, so passing a temporary string or
  `ffi.new(...)` directly is safe. Trouble starts when C *keeps* the pointer: `setenv` copies its
  strings, but `putenv` keeps the pointer it's given. Read the documentation of each function you
  bind.

## Alignment and packing

C compilers put each field at an offset that is a multiple of its *alignment* (usually its size),
inserting unused padding bytes to get there. The FFI follows the system C compiler's rules, so a
struct declared in `ffi.cdef` has the same layout as in C.

`examples/ch14/packing.lua`

```lua
-- Alignment and packing: where the fields really are.

local ffi = require("ffi")
ffi.cdef [[
typedef struct { uint8_t tag; uint32_t value; uint8_t flag; } loose;
typedef struct { uint32_t value; uint8_t tag; uint8_t flag; } ordered;
typedef struct __attribute__((packed)) { uint8_t tag; uint32_t value; uint8_t flag; } packed;
]]

-- Each field starts at a multiple of its alignment, and the whole struct
-- is padded to a multiple of its largest alignment.
for _, name in ipairs({ "loose", "ordered", "packed" }) do
  print(("%-8s size %2d  align %d  offsets tag=%d value=%d flag=%d"):format(
    name, ffi.sizeof(name), ffi.alignof(name),
    ffi.offsetof(name, "tag"), ffi.offsetof(name, "value"), ffi.offsetof(name, "flag")))
end

-- Some C types have different sizes on different systems.
print(ffi.sizeof("long"), ffi.sizeof("void *"), ffi.sizeof("size_t"))
```

```console
$ luajit examples/ch14/packing.lua
loose    size 12  align 4  offsets tag=0 value=4 flag=8
ordered  size  8  align 4  offsets tag=4 value=0 flag=5
packed   size  6  align 1  offsets tag=0 value=1 flag=5
8	8	8
```

- In `loose`, `value` (4-byte alignment) can't start at offset 1, so three padding bytes come
  first. The size is also rounded up to a multiple of 4: 12 bytes for 6 bytes of data.
- `ordered` has the same fields, largest first, in 8 bytes.
- `__attribute__((packed))` removes all padding. Use it only when C declares the struct that way, as
  some file formats and protocols do: your `cdef` must match C's layout exactly.
- When a struct doesn't work as expected, check its layout with `ffi.offsetof` and `ffi.sizeof`.
- `long` and pointers are 8 bytes on 64-bit Linux and macOS, but `long` is 4 on 64-bit Windows.

## Endianness

Machines disagree about the order of a `uint32_t`'s 4 bytes. **Little-endian** machines (x86, and
ARM as normally used) store the lowest byte first; **big-endian** puts the highest first, as do
network protocols and many file formats.

`examples/ch14/endian.lua`

```lua
-- Endianness: the order of bytes inside a number.

local ffi = require("ffi")
local bit = require("bit")

print("little-endian:", ffi.abi("le"))

-- Look at the bytes of a uint32 through a union.
ffi.cdef [[ typedef union { uint32_t n; uint8_t b[4]; } u32bytes; ]]
local u = ffi.new("u32bytes")
u.n = 0x11223344
print(("%02x %02x %02x %02x"):format(u.b[0], u.b[1], u.b[2], u.b[3]))

-- Network protocols and many file formats are big-endian.
-- On a little-endian machine, bit.bswap reverses the bytes.
local function to_be32(n)
  if ffi.abi("le") then return bit.bswap(n) end
  return n
end
u.n = to_be32(0x11223344)
print(("%02x %02x %02x %02x"):format(u.b[0], u.b[1], u.b[2], u.b[3]))
print(bit.tohex(bit.bswap(0x11223344)))

-- Or build the number from bytes yourself; this works on any machine.
local b = ffi.new("uint8_t[4]", { 0x11, 0x22, 0x33, 0x44 })
local be = bit.bor(bit.lshift(b[0], 24), bit.lshift(b[1], 16), bit.lshift(b[2], 8), b[3])
print(bit.tohex(be))
```

```console
$ luajit examples/ch14/endian.lua
little-endian:	true
44 33 22 11
11 22 33 44
44332211
11223344
```

- `ffi.abi("le")` is true on a little-endian machine, `ffi.abi("be")` on a big-endian one.
- A union shows a number's bytes: `0x11223344` is stored as `44 33 22 11` here.
- `bit.bswap` reverses the 4 bytes. To write big-endian, swap only on little-endian machines.
- Building the number from bytes with shifts gives the same answer on every machine, with no check.
  It is the safest way to read a file format.

## The terminal size

One more example combines a struct, an out parameter and `errno`: `ioctl` with `TIOCGWINSZ` asks
the terminal for its size.

`examples/ch14/winsize.lua`

```lua
-- Ask the terminal for its size with ioctl(TIOCGWINSZ).

local ffi = require("ffi")
ffi.cdef [[
struct winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
int ioctl(int fd, unsigned long request, ...);
char *strerror(int errnum);
]]
local TIOCGWINSZ = ffi.os == "OSX" and 0x40087468 or 0x5413

local ws = ffi.new("struct winsize")      -- C fills this in (an out parameter)
if ffi.C.ioctl(1, TIOCGWINSZ, ws) == 0 then
  print(("terminal: %d columns x %d rows"):format(ws.ws_col, ws.ws_row))
else
  local e = ffi.errno()
  print("not a terminal: " .. ffi.string(ffi.C.strerror(e)) .. " (errno " .. e .. ")")
end
```

Output to a pipe or file has no terminal to ask:

```console
$ luajit examples/ch14/winsize.lua | cat
not a terminal: Inappropriate ioctl for device (errno 25)
```

In a terminal it prints something like `terminal: 100 columns x 30 rows`.

- `ioctl` is variadic. Its third argument is a pointer to a `struct winsize`; passing the struct
  cdata passes its address, and `ioctl` writes the fields.
- `TIOCGWINSZ` is a `#define`, so its value is copied. It differs between Linux and macOS.
- `ws_col` is an `unsigned short`, which reads as a plain Lua number.

## Building stash: terminal width and a byte buffer

Two changes:

- `list` fits the title column to the terminal. At 80 columns the output is unchanged; wider
  terminals give titles more room, narrower ones less, down to 20 characters.
- A new module, `stash.buffer`, is a growable byte array in C memory. Nothing uses it yet. In
  [Chapter 16](16-callbacks-and-curl.md), curl hands us a download in pieces, as C pointers and
  lengths, and the buffer collects them.

New files: `src/stash/buffer.lua`, `test/buffer_test.lua`. Changed: `ffi/libc.lua`, `term.lua`,
`commands.lua`, `main.lua`, and the tests `commands_test`, `term_test`, `e2e_test` and `run.lua`.

### src/stash/ffi/libc.lua

The raw declarations gain `malloc`, `realloc`, `free`, `struct winsize`, `ioctl` and the
`TIOCGWINSZ` constant.

```lua
-- Raw bindings to the few C library functions stash uses. ffi.cdef takes
-- plain C declarations, copied from the system headers; ffi.C is the C
-- library itself, already loaded into every process.

local ffi = require("ffi")

-- mode_t is a typedef whose size depends on the platform, so we declare it
-- before the functions that use it.
if ffi.os == "OSX" then
  ffi.cdef("typedef uint16_t mode_t;")
else
  ffi.cdef("typedef uint32_t mode_t;")
end

ffi.cdef [[
int isatty(int fd);
int mkdir(const char *path, mode_t mode);
char *strerror(int errnum);

void *malloc(size_t size);
void *realloc(void *ptr, size_t size);
void free(void *ptr);

struct winsize {
  unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel;
};
int ioctl(int fd, unsigned long request, ...);
]]

local M = {}

-- #define constants don't exist for the FFI; we copy their values.
M.EEXIST = 17                                -- the same on Linux and macOS
M.TIOCGWINSZ = ffi.os == "OSX" and 0x40087468 or 0x5413   -- this one differs

-- The message for an errno value (default: the latest one).
function M.strerror(errnum)
  return ffi.string(ffi.C.strerror(errnum or ffi.errno()))
end

return M
```

`struct winsize` uses a struct tag, not a typedef, as `<sys/ioctl.h>` does, so you write
`struct winsize` everywhere, in Lua strings too.

### src/stash/term.lua

`term.lua` now needs the module's table, not just its declarations, to read `libc.TIOCGWINSZ`:

```lua
-- Terminal output: color, but only when a person is watching.

local ffi = require("ffi")
local libc = require("stash.ffi.libc")

local M = {}
```

The new function:

```lua
-- The width of the terminal in columns. ioctl fills in a struct we
-- allocate; when stdout is not a terminal there is no width to ask for,
-- so we fall back to $COLUMNS, then to 80.
function M.width()
  if M.is_tty(1) then
    local size = ffi.new("struct winsize")   -- zero-filled
    if ffi.C.ioctl(1, libc.TIOCGWINSZ, size) == 0 and size.ws_col > 0 then
      return size.ws_col
    end
  end
  return tonumber(os.getenv("COLUMNS")) or 80
end
```

- `ioctl` runs only when stdout is a terminal; otherwise it would fail with `ENOTTY` anyway.
- `size.ws_col > 0` guards against terminals that report a size of 0, as some do (over a serial
  line, for example).
- `$COLUMNS` is the fallback. Shells set it but mostly don't export it to programs, so it's mainly
  for setting by hand: `COLUMNS=100 ./stash list | less`.

### src/stash/commands.lua

`format_row` computes the title width from `ctx.width`:

```lua
-- One line of `list` output. The title gets whatever the other columns
-- leave of the terminal width, but never less than 20 characters.
-- Pads first, then paints: escape codes have no width on screen, but
-- string.format would count them.
local function format_row(ctx, entry)
  local paint = ctx.paint
  local title_width = math.max(20, ctx.width - 44)
  return ("%s  %s  %s  %s"):format(
    paint(("%3d"):format(entry.id), "id"),
    ("%-" .. title_width .. "s"):format(util.truncate(entry.title, title_width)),
    paint(("%-16s"):format(util.truncate(entry:tag_string(), 16)), "tag"),
    paint(util.date(entry.created), "dim"))
end
```

The other columns and the gaps between them take 35 characters. Subtracting 44 leaves a margin and
gives exactly the old 36-character title at 80 columns. `"%-" .. title_width .. "s"` builds the
format string at run time, such as `"%-56s"`. The top-of-file comment now lists `width` among the
context fields.

### src/stash/main.lua

```lua
  local ctx = {
    store = store,
    config = settings,
    out = print,
    paint = term.painter(term.use_color(settings.color)),
    width = term.width(),
  }
  command.run(ctx, opts)
```

`main` computes the width once per run and passes it in the context. Commands don't call C, and
tests can pass any width.

### src/stash/buffer.lua (new)

```lua
-- Buffer: a growable array of bytes in C memory, for data that arrives
-- from C in pieces (Chapter 16 collects downloads in one).
--
-- The buffer is a C struct with Lua methods attached by ffi.metatype. Its
-- bytes live in memory from malloc, which the garbage collector knows
-- nothing about, so the __gc metamethod hands them back with free().

local ffi = require("ffi")
require("stash.ffi.libc")                    -- declares malloc, realloc, free

ffi.cdef [[
typedef struct {
  uint8_t *data;                             /* NULL until the first append */
  size_t len;                                /* bytes in use */
  size_t cap;                                /* bytes allocated */
} stash_buffer;
]]

local C = ffi.C

local Buffer = {}
Buffer.__index = Buffer

-- Makes room for n more bytes, doubling the allocation as needed.
-- size_t fields read as 64-bit cdata; tonumber turns them into Lua numbers.
function Buffer:reserve(n)
  local need = tonumber(self.len) + n
  local cap = tonumber(self.cap)
  if need <= cap then
    return
  end
  cap = math.max(cap, 64)
  while cap < need do
    cap = cap * 2
  end
  local data = C.realloc(self.data, cap)     -- realloc(NULL, n) works like malloc(n)
  if data == nil then                        -- a NULL pointer compares equal to nil
    error("out of memory", 2)
  end
  self.data = ffi.cast("uint8_t *", data)
  self.cap = cap
end

-- Appends a Lua string, or len bytes starting at a C pointer.
function Buffer:append(data, len)
  len = len or #data
  self:reserve(len)
  ffi.copy(self.data + self.len, data, len)  -- pointer arithmetic: data + offset
  self.len = self.len + len
  return self
end

-- The byte at position i (0-based, like C).
function Buffer:byte(i)
  assert(i >= 0 and i < self.len, "index out of range")
  return self.data[i]
end

function Buffer:tostring()
  return ffi.string(self.data, self.len)     -- copies the bytes into a Lua string
end

function Buffer:reset()
  self.len = 0
end

Buffer.__tostring = Buffer.tostring

function Buffer.__len(self)
  return tonumber(self.len)
end

function Buffer.__gc(self)
  C.free(self.data)                          -- free(NULL) is allowed
end

-- ffi.metatype returns a constructor for the C type; every object it
-- makes shares the metatable. ffi.new zero-fills the struct.
local new = ffi.metatype("stash_buffer", Buffer)

return {
  new = function()
    return new()
  end,
}
```

This module uses most of the chapter:

- **The struct.** `stash_buffer` holds a pointer and two sizes. `Buffer.new()` calls the
  `ffi.metatype` constructor, which zero-fills it: `data` is `NULL`, `len` and `cap` are 0.
- **Two owners.** The struct comes from `ffi.new`, so the collector owns it. The bytes come from
  `realloc`, so we own them. `__gc` connects the two: when the collector frees the struct, `free`
  frees the bytes. `free(NULL)` does nothing, so an unused buffer is fine.
- **reserve** doubles the capacity, starting at 64 bytes, until the new data fits. Doubling keeps
  total copying proportional to the final size, however small the pieces. `realloc(NULL, n)` works
  like `malloc(n)`, and `realloc` keeps the old contents when it moves the block. A `NULL` result
  means out of memory, with the old block still valid.
- **size_t fields are cdata.** `self.len` reads as a `uint64_t` cdata such as `8ULL`, so `reserve`
  converts with `tonumber` before doing math. Comparisons and `+` work between cdata and numbers,
  which `append` and `byte` rely on.
- **append** copies with `ffi.copy` to `self.data + self.len`, the first free byte. `data` may be a
  Lua string or a pointer with a length, so C data goes in without becoming a Lua string first. It
  returns `self`, so calls chain: `b:append("a"):append("b")`.
- **byte** is 0-based like C, but checks the index, raising an error instead of reading past the
  end.
- **tostring** copies the bytes into a Lua string with `ffi.string(data, len)`. `__tostring` makes
  `tostring(b)` work; `__len` makes `#b` return a Lua number.
- **reset** sets the length to 0 and keeps the memory for reuse.

The module returns a table with a `new` function rather than the constructor itself, so callers
can't pass initializers (`new(somepointer, 5, 1)`) that break the struct's invariants.

### Tests

`test/buffer_test.lua` (new):

```lua
local ffi = require("ffi")
local Buffer = require("stash.buffer")

test("an empty buffer", function()
  local buf = Buffer.new()
  eq(#buf, 0)
  eq(tostring(buf), "")
end)

test("appending strings and C bytes", function()
  local buf = Buffer.new()
  buf:append("hello, ")
  local bytes = ffi.new("uint8_t[5]", { 119, 111, 114, 108, 100 })    -- "world"
  buf:append(bytes, 5)
  eq(#buf, 12)
  eq(buf:tostring(), "hello, world")
  eq(buf:byte(0), 104)                                                 -- "h"
  raises(function() buf:byte(12) end, "index out of range")
end)

test("the buffer grows past its first allocation", function()
  local buf = Buffer.new()
  for i = 1, 1000 do
    buf:append(("%04d"):format(i))
  end
  eq(#buf, 4000)
  ok(buf.cap >= 4000)
  eq(buf:tostring():sub(-8), "09991000")
  buf:reset()
  eq(#buf, 0)
end)
```

The second test appends real C bytes (a `uint8_t[5]` with a length), as curl will. The third makes
the buffer grow several times, from 64 to at least 4000 bytes.

The command tests in `test/commands_test.lua` pass a fixed width in their context:

```lua
  local lines = {}
  local ctx = {
    store = store,
    config = config.defaults,
    out = function(line) lines[#lines + 1] = line end,
    paint = function(text) return text end,
    width = 80,
  }
```

`test/term_test.lua` checks the fallback. Run in a terminal, the width is the real one and can't be
predicted, so the test skips itself:

```lua

test("without a terminal the width comes from COLUMNS or defaults to 80", function()
  if term.is_tty(1) then
    return                                   -- run with output to a terminal: skip
  end
  eq(term.width(), tonumber(os.getenv("COLUMNS")) or 80)
end)
```

`test/e2e_test.lua`: the `stash` helper takes optional environment settings, and a new test checks
two widths. The tests' output goes to a pipe, so `COLUMNS` decides.

```lua
-- Runs `stash ARGS` (with extra environment variables `env`, like
-- "COLUMNS=100") and returns its output (stdout and stderr) and exit code.
-- io.popen's close() does not report the exit code in LuaJIT, so the
-- shell prints it after the output.
local function stash(args, env)
  local command = ("%s STASH_HOME=%s STASH_NOW=1767225600 ./stash %s 2>&1; echo \"[exit $?]\"")
                  :format(env or "", HOME, args)
  local pipe = assert(io.popen(command))
  local output = pipe:read("*a")
  pipe:close()
  local text, code = output:match("^(.-)%[exit (%d+)%]\n$")
  return text, tonumber(code)
end
```

```lua

test("the title column follows COLUMNS", function()
  stash("add " .. PAGES .. "/luajit.html -t jit")
  eq(stash("list -t jit", "COLUMNS=60"),
     "  3  LuaJIT: a Just-In...  jit               2026-01-01\n")
  eq(stash("list -t jit", "COLUMNS=100"),
     "  3  LuaJIT: a Just-In-Time Compiler & FFI                     jit               2026-01-01\n")
end)
```

`test/run.lua` runs the new file:

```lua
local FILES = {
  "util_test", "cli_test", "entry_test", "iter_test", "memstore_test", "config_test",
  "commands_test", "json_test", "html_test", "fs_test", "filestore_test", "term_test",
  "buffer_test",
  "e2e_test",
}
```

### Checkpoint

This output was captured to a file, so `stash` had no terminal and used `COLUMNS` or 80. In your
terminal, plain `./stash list` uses the real width and ignores `COLUMNS`. To reproduce the
transcript there, pipe it: `COLUMNS=60 ./stash list | cat`.

```console
$ luajit test/run.lua
util_test        3 tests, 0 failed
cli_test         5 tests, 0 failed
entry_test       5 tests, 0 failed
iter_test        4 tests, 0 failed
memstore_test    7 tests, 0 failed
config_test      4 tests, 0 failed
commands_test    5 tests, 0 failed
json_test        6 tests, 0 failed
html_test        4 tests, 0 failed
fs_test          3 tests, 0 failed
filestore_test   5 tests, 0 failed
term_test        3 tests, 0 failed
buffer_test      3 tests, 0 failed
e2e_test         5 tests, 0 failed

62 passed, 0 failed
$ export STASH_HOME=demo STASH_NOW=1767225600
$ PAGES=file://$PWD/test/fixtures
$ ./stash add $PAGES/lua.html -t lua,lang
added #1 The Programming Language Lua
$ ./stash add $PAGES/luajit.html -t lua,jit
added #2 LuaJIT: a Just-In-Time Compiler & FFI
$ ./stash list
  1  The Programming Language Lua          lang,lua          2026-01-01
  2  LuaJIT: a Just-In-Time Compiler &...  jit,lua           2026-01-01
$ COLUMNS=60 ./stash list
  1  The Programming L...  lang,lua          2026-01-01
  2  LuaJIT: a Just-In...  jit,lua           2026-01-01
$ COLUMNS=100 ./stash list
  1  The Programming Language Lua                              lang,lua          2026-01-01
  2  LuaJIT: a Just-In-Time Compiler & FFI                     jit,lua           2026-01-01
$ LUA_PATH="src/?.lua" luajit -e 'local B = require("stash.buffer") local b = B.new() b:append("hello, "):append("C") print(#b, tostring(b), b.cap, b.len)'
8	hello, C	64ULL	8ULL
```

Run `rm -rf demo` when you're done.

The complete project at this point is in `project/ch14/`.

## Summary

- `ffi.new` makes C values owned by the garbage collector: scalars, arrays (0-based, zero-filled,
  not bounds-checked), VLAs with `[?]`, structs and unions, initialized with values or a table.
- A one-element array (`int[1]`, `char *[1]`) is Lua's `&x` for out parameters.
- Pointers support `p[i]`, `p + n` (in elements), subtraction and comparison. `ffi.cast` changes
  the type, not the bytes. Use `.` for fields through pointers too.
- `ffi.copy` and `ffi.fill` are `memcpy`/`strcpy` and `memset`, with unchecked lengths in bytes.
- Assigning a cdata to a variable shares it. `ffi.new(T, x)`, or storing into a field or element,
  copies the bytes.
- `ffi.metatype` gives a struct type methods and metamethods (`__index`, `__tostring`, `__len`,
  `__gc`, operators). It is permanent, so finish the metatable first.
- Memory from `malloc`/`realloc` is yours to free exactly once; `ffi.gc` or `__gc` can do it for
  you, and `ffi.gc(p, nil)` takes the job back.
- The collector doesn't follow C pointers. Anchor arrays and strings in Lua as long as C or a struct
  points at them.
- `ffi.cdef` structs follow C's alignment rules; `ffi.offsetof` shows them, and
  `__attribute__((packed))` matches packed C structs. `ffi.abi("le")` tells the byte order. Read
  file formats with shifts.
- `stash`: `list` fits the terminal width (`ioctl`, then `$COLUMNS`, then 80), and `stash.buffer`
  is a growable byte buffer with `realloc` and `__gc`.

## Exercises

1. Write `parse_int(s, base)` that returns a number only if *all* of `s` is a number, and `nil`
   otherwise (`"42 apples"`, `""`, `"nope"`). Use `strtol` and its end pointer.

<details><summary>Solution</summary>

```lua
local ffi = require("ffi")
ffi.cdef [[
long strtol(const char *s, char **endptr, int base);
]]

-- Returns the number, or nil if s is not entirely a number.
local function parse_int(s, base)
  local endp = ffi.new("char *[1]")
  local n = ffi.C.strtol(s, endp, base or 10)
  local used = endp[0] - ffi.cast("const char *", s)
  if used == 0 or used ~= #s then
    return nil
  end
  return tonumber(n)
end

for _, s in ipairs({ "42", "-17", "42 apples", "", "nope", "ff" }) do
  print(("%q"):format(s), parse_int(s), parse_int(s, 16))
end
```

```console
$ luajit parse_int.lua
"42"	42	66
"-17"	-17	-23
"42 apples"	nil	nil
""	nil	nil
"nope"	nil	nil
"ff"	nil	255
```

`used == 0` catches the empty string and `"nope"`; `used ~= #s` catches leftovers such as
`" apples"`. Note that `"42"` in base 16 is 66.

</details>

2. Write a `Stack` of ints with a fixed capacity, stored in an `ffi.new("int[?]", capacity)` array.
   `push` raises an error when full, and `pop` returns `nil` when empty.

<details><summary>Solution</summary>

```lua
local ffi = require("ffi")

-- A stack of ints with a fixed capacity, stored in a C array.
local Stack = {}
Stack.__index = Stack

function Stack.new(capacity)
  return setmetatable({ items = ffi.new("int[?]", capacity), n = 0, cap = capacity }, Stack)
end

function Stack:push(v)
  if self.n == self.cap then
    error("stack full", 2)
  end
  self.items[self.n] = v          -- 0-based: the first item goes in items[0]
  self.n = self.n + 1
end

function Stack:pop()
  if self.n == 0 then
    return nil
  end
  self.n = self.n - 1
  return self.items[self.n]
end

local s = Stack.new(3)
s:push(1); s:push(2); s:push(3)
print(pcall(s.push, s, 4))
print(s:pop(), s:pop(), s:pop(), s:pop())
```

```console
$ luajit stack.lua
false	stack full
3	2	1	nil
```

The C array has no length, so the Lua table keeps `n` and `cap` beside it. The check in `push`
matters: without it, a fourth push would write past the end of the array.

</details>

3. Give `vec2` from `examples/ch14/metatype.lua` a unary minus (`-v`) and multiplication by a number
   on either side (`v * 3` and `2 * v`).

<details><summary>Solution</summary>

```lua
local ffi = require("ffi")
ffi.cdef [[ typedef struct vec2 { double x, y; } vec2; ]]

local Vec2 = {}
Vec2.__index = Vec2
local new

Vec2.__add = function(a, b) return new(a.x + b.x, a.y + b.y) end
Vec2.__unm = function(v) return new(-v.x, -v.y) end
Vec2.__mul = function(a, b)
  -- a number may be on either side: 2 * v or v * 2
  if type(a) == "number" then a, b = b, a end
  return new(a.x * b, a.y * b)
end
Vec2.__tostring = function(v) return ("(%g, %g)"):format(v.x, v.y) end

new = ffi.metatype("vec2", Vec2)

local v = new(1, 2)
print(tostring(-v), tostring(v * 3), tostring(2 * v), tostring(v + -v))
```

```console
$ luajit vec2.lua
(-1, -2)	(3, 6)	(2, 4)	(0, 0)
```

For `2 * v` the left operand is a number, so LuaJIT uses the right operand's `__mul`, with the
arguments in their original order. The function swaps them so `a` is always the vector.

</details>

4. A PNG file starts with an 8-byte signature, then a chunk length (4 bytes), the type `"IHDR"`, and
   the image width and height (4 bytes each), all big-endian. Write `u32be(s, offset)` that reads
   a big-endian `uint32` from a Lua string through a `const uint8_t *`. Use it to read the size
   from a PNG header.

<details><summary>Solution</summary>

```lua
local ffi = require("ffi")
local bit = require("bit")

-- Reads big-endian numbers from a Lua string, 0-based offset.
local function u16be(s, offset)
  local p = ffi.cast("const uint8_t *", s) + offset
  return bit.bor(bit.lshift(p[0], 8), p[1])
end

local function u32be(s, offset)
  local p = ffi.cast("const uint8_t *", s) + offset
  -- bit.* results are signed 32-bit; % 2^32 makes the result non-negative.
  return bit.bor(bit.lshift(p[0], 24), bit.lshift(p[1], 16), bit.lshift(p[2], 8), p[3]) % 2^32
end

-- A PNG file: an 8-byte signature, then the IHDR chunk (length, "IHDR",
-- width, height, ...). The width and height are big-endian uint32.
local png = "\137PNG\r\n\26\n" .. "\0\0\0\13" .. "IHDR"
         .. "\0\0\7\128" .. "\0\0\4\56" .. "\8\6\0\0\0"
assert(png:sub(2, 4) == "PNG")
print("chunk length", u32be(png, 8))
print("size", u32be(png, 16), u32be(png, 20))
print(u16be("\1\2", 0), u32be("\255\255\255\255", 0))
```

```console
$ luajit header.lua
chunk length	13
size	1920	1080
258	4294967295
```

Casting the string to `const uint8_t *` reads its bytes without copying. The pointer is valid only
while `s` is alive, which it is during the call. LuaJIT's `bit` functions return signed 32-bit
results, so without `% 2^32` the last value would print as -1.

</details>

5. Add `Buffer:append_byte(b)` to `stash.buffer`. It should append one byte given as a number and
   return the buffer for chaining. Add a test.

<details><summary>Solution</summary>

In `src/stash/buffer.lua`, before `Buffer:byte`:

```lua
-- Appends one byte (a number from 0 to 255).
function Buffer:append_byte(b)
  self:reserve(1)
  self.data[self.len] = b
  self.len = self.len + 1
  return self
end
```

In `test/buffer_test.lua`:

```lua
test("appending single bytes", function()
  local buf = Buffer.new()
  buf:append("ab"):append_byte(0):append_byte(99)
  eq(#buf, 4)
  eq(buf:tostring(), "ab\0c")
end)
```

`luajit test/run.lua` now reports `buffer_test      4 tests, 0 failed` and `63 passed, 0 failed`.
`self.data[self.len]` indexes with a `uint64_t` cdata, which works like a number. The test's 0
byte shows that the buffer, unlike a C string, can hold zeros.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-14--c-data)
