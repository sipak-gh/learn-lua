# Appendix B — FFI Reference

The LuaJIT FFI on one page: the API, how values convert between Lua and C, recipes for common
C declarations, and a memory ownership checklist. Chapters 13–17 teach it step by step, starting
with [Chapter 13](13-ffi-basics.md). Below, `expr --> result` means `print(expr)` prints
`result`, with print's tabs shown as two spaces.

## The API

```lua
local ffi = require("ffi")

ffi.cdef[[
int abs(int n);
struct point { int x, y; };
]]
ffi.C.abs(-3)                             --> 3
```

| Function | Does |
|----------|------|
| `ffi.cdef(decls)` | parse C declarations: functions, types, constants. Once per type (put each cdef in one module) |
| `ffi.C` | the default namespace: libc, the libraries the program is linked with, and its own exported symbols |
| `ffi.load(name [, global])` | load a shared library and return its namespace; `"z"` looks for `libz.so` |
| `ffi.new(ct [, n] [, init...])` | allocate zero-filled C data owned by the Lua GC; `n` for `[?]` types |
| `ctype([n,] [init...])` | the same, using a type from `ffi.typeof` as a constructor |
| `ffi.typeof(ct)` | parse a type once, return a ctype (faster than strings in hot code) |
| `ffi.cast(ct, value)` | convert to a C type: numbers to pointers, pointer to pointer, Lua function to callback |
| `ffi.metatype(ct, mt)` | attach a metatable (methods, operators, `__gc`) to a struct type. Permanent |
| `ffi.gc(cdata, fn)` | run `fn(cdata)` when the GC frees the object; `ffi.gc(cdata, nil)` removes it |
| `ffi.sizeof(ct [, n])`, `ffi.alignof(ct)` | size and alignment in bytes (`nil` if unknown) |
| `ffi.offsetof(ct, field)` | byte offset of a struct field |
| `ffi.istype(ct, v)` | is `v` cdata of type `ct`? |
| `ffi.errno([new])` | `errno` from the last C call; read it right after a call that failed |
| `ffi.string(ptr [, len])` | copy C bytes into a Lua string; no `len` means up to the zero byte |
| `ffi.copy(dst, src, len)`, `ffi.copy(dst, str)` | `memcpy`; the second form copies a Lua string plus its zero byte |
| `ffi.fill(dst, len [, byte])` | `memset` (note the argument order); zeros by default |
| `ffi.abi(param)` | ABI checks: `"32bit"`, `"64bit"`, `"le"`, `"be"`, `"win"`, ... |
| `ffi.os`, `ffi.arch` | `"Linux"`, `"OSX"`, `"Windows"`, ...; `"x64"`, `"arm64"`, ... |
| `cb:free()`, `cb:set(fn)` | release a callback; point it at another Lua function |
| `tonumber(cdata)`, `tostring(cdata)` | a Lua number (may lose precision for 64-bit values); `"5LL"`, `"cdata<int [3]>: 0x..."` |

```lua
local ffi = require("ffi")
ffi.cdef[[ typedef struct { int x, y; } point; ]]

local point_t = ffi.typeof("point")
local p = point_t(1, 2)                   -- same as ffi.new("point", 1, 2)
p.x, p.y, ffi.istype(point_t, p)          --> 1  2  true
ffi.sizeof(p), ffi.alignof(p), ffi.offsetof("point", "y")   --> 8  4  4
ffi.sizeof("uint8_t[?]", 10), ffi.sizeof("void")            --> 10  nil
ffi.typeof(1LL), ffi.typeof("int[3]")     --> ctype<int64_t>  ctype<int [3]>
ffi.os, ffi.arch, ffi.abi("64bit")        --> Linux  x64  true
```

The last line depends on your machine.

## C to Lua: reading values

For C function results, struct fields, array elements and `ffi.C` variables.

| C type | Lua value | Example |
|--------|-----------|---------|
| `int8_t` … `int32_t`, `uint8_t` … `uint32_t`, `char`, `short`, `int` | number | `65` |
| `float`, `double` | number | `1.5` |
| `bool` | boolean | `true` |
| `int64_t`, `uint64_t`, and on 64-bit Linux/macOS also `long`, `size_t`, `ssize_t`, `intptr_t` | 64-bit cdata | `5LL`, `6ULL` |
| an `enum` type | enum cdata, equal to its constant and to its name | `s.c == "GREEN"` is `true` |
| pointers, including `char *` | pointer cdata | use `ffi.string(p)` for text |
| arrays, structs, unions | a reference to the C data: writes change it | `b.max.x = 1` |

Enum *constants* (`lib.NAME`) and `static const int` values are plain numbers.

```lua
local ffi = require("ffi")
ffi.cdef[[
typedef enum { RED = 1, GREEN, BLUE } color;
typedef struct { color c; bool ok; long l; size_t n; float f; char ch; } sample;
long strtol(const char *s, char **end, int base);
]]
local s = ffi.new("sample", { "GREEN", true, 5, 6, 1.5, 65 })
s.ok, s.l, s.n, s.f, s.ch                 --> true  5LL  6ULL  1.5  65
s.c == ffi.C.GREEN, s.c == "GREEN", ffi.C.BLUE   --> true  true  3
ffi.C.strtol("42", nil, 10)               --> 42LL
tonumber(ffi.C.strtol("42", nil, 10))     --> 42
```

- 64-bit cdata stays 64-bit through arithmetic: `1LL + 1` is `2LL`. Use `tonumber()` before
  table keys, `#`, `string.format("%d")` or floating-point math.
- `long` is 32-bit on Windows, so the same code gets a plain number there.

## Lua to C: writing and passing values

For function arguments, struct fields, array elements, `ffi.new` initializers and casts.

| Lua value | Becomes | Notes |
|-----------|---------|-------|
| number | any number type | narrowed like C: `300` in a `uint8_t` is `44` |
| boolean | `bool` / number | `false` is 0, `true` is 1 |
| `nil` | `NULL` | for any pointer |
| string | `const char *` | points into the Lua string, valid during the call only |
| string | `char[N]`, `uint8_t[N]` | copied, with a zero byte |
| string | enum | the constant with that name |
| table | array or struct | an initializer: `{ 1, 2 }` or `{ x = 1, y = 2 }` |
| function | function pointer | creates a callback (see below) |
| cdata | its own type | converted by C's rules |
| `io` file | `void *` | the `FILE *` |

```lua
local ffi = require("ffi")
local a = ffi.new("uint8_t[2]", 300, -1)
a[0], a[1]                                --> 44  255
ffi.new("int32_t[1]", 0xffffffff)[0]      --> -1
ffi.new("int[4]", 7)[3], ffi.new("int[4]", 7, 8)[3]   --> 7  0
```

One initializer fills the whole array; two or more fill the front and leave zeros after.

## Varargs: printf-style functions

The `...` part of a C function gets default conversions: number → `double`, boolean → `bool`,
string → `const char *`, `nil` → `NULL`, arrays and structs → pointers to them, other cdata → its
own type. So pass an integer as an integer cdata:

```lua
local ffi = require("ffi")
ffi.cdef[[ int snprintf(char *buf, size_t size, const char *fmt, ...); ]]

local buf = ffi.new("char[64]")
local n = ffi.C.snprintf(buf, 64, "%d-%s-%.1f", ffi.new("int", 42), "x", 2.5)
ffi.string(buf, n)                        --> 42-x-2.5
```

A plain `42` for `%d` gives garbage, with no error. The same trap hits
`curl_easy_setopt(h, CURLOPT_TIMEOUT, 10)`: write `ffi.cast("long", 10)`
([Chapter 16](16-callbacks-and-curl.md)).

## Operations on cdata

```lua
local ffi = require("ffi")
local arr = ffi.new("int[5]", { 10, 20, 30, 40, 50 })
arr[0], arr[4]                            --> 10  50
local p = arr + 1                         -- pointer arithmetic, in elements
p[0], p - arr                             --> 20  1
9007199254740993LL, tonumber(9007199254740993LL)   --> 9007199254740993LL  9.007199254741e+15
5ULL - 6, -1LL < 0                        --> 18446744073709551615ULL  true
ffi.new("double", 1.5) + 1                --> 2LL
ffi.new("void *") == nil, not ffi.new("void *")    --> true  false
```

- Arrays and pointers index from **0**, and nothing checks the bounds.
- A NULL pointer is `== nil`, but it is still a true value: write `if p == nil`, never `if not p`.
- `ffi.string(NULL)` and reading through a NULL pointer crash the process (segmentation fault).
  Check first.
- Arithmetic on scalar cdata is 64-bit integer math, even for `double` cdata. Box numbers with
  `ffi.new("int", x)` only for varargs.
- `#` doesn't work on cdata (`attempt to get length of 'int [3]'`) unless its metatype has
  `__len`. Keep the length yourself or use `ffi.sizeof`.
- Cdata keys in tables compare by object, not value: `t[2LL] = "a"` then `t[2LL]` is `nil`. Use
  `tonumber(x)` or `tostring(x)` as the key.

## Recipes

### Constants (`#define`)

The FFI has no preprocessor. Copy the values from the header:

```lua
local ffi = require("ffi")
ffi.cdef[[
enum { O_RDONLY = 0, EEXIST = 17 };
static const int BUF_SIZE = 4096;
]]
ffi.C.EEXIST, ffi.C.BUF_SIZE              --> 17  4096
```

Values that differ between platforms need an `if ffi.os == ...` ([Chapter 13](13-ffi-basics.md)).

### Structs and nested structs

```lua
local ffi = require("ffi")
ffi.cdef[[
typedef struct { double x, y; } vec2;
typedef struct { vec2 min, max; char name[16]; } box;
]]
local b = ffi.new("box", { min = { 0, 0 }, max = { 2, 3 }, name = "unit" })
b.max.x * b.max.y, ffi.string(b.name), ffi.sizeof(b)   --> 6  unit  48
local corner = b.max                      -- a reference into b, not a copy
corner.x = 10
b.max.x                                   --> 10
```

Use `__attribute__((packed))` only when the C header does
([Chapter 14](14-c-data.md)).

### Out parameters

A C function that writes to `T *out` gets a one-element array:

```lua
local ffi = require("ffi")
ffi.cdef[[ long strtol(const char *s, char **end, int base); ]]
local endp = ffi.new("char *[1]")
local n = ffi.C.strtol("42abc", endp, 10)
tonumber(n), ffi.string(endp[0])          --> 42  abc
```

`int[1]`, `long[1]`, `double[1]` and `char *[1]` cover most out parameters; read the result
with `[0]`.

### Buffers and strings

```lua
local ffi = require("ffi")
local n = 8
local buf = ffi.new("uint8_t[?]", n)      -- zero-filled, freed by the GC
ffi.copy(buf, "hi")                       -- 2 bytes + a zero byte
ffi.fill(buf + 3, 2, 0x41)                -- "AA" at offset 3
ffi.string(buf)                           --> hi
#ffi.string(buf, 5), ffi.string(buf + 3, 2)   --> 5  AA
```

- `ffi.string(p)` stops at the first zero byte. `ffi.string(p, len)` copies exactly `len` bytes,
  zeros included: use it for binary data.
- Pass a Lua string where C wants `const char *` or `const void *`. If C wants to write, give it
  a `char[?]` or `uint8_t[?]` buffer.

### Opaque handles with methods

Libraries hand out pointers to structs you never see inside (`sqlite3 *`, `CURL *`, `FILE *`).
Declare the struct without a body and attach methods with `ffi.metatype`:

```lua
local ffi = require("ffi")
ffi.cdef[[
typedef struct FILE FILE;
FILE *fopen(const char *path, const char *mode);
int fputs(const char *s, FILE *f);
int fclose(FILE *f);
char *strerror(int errnum);
]]

local File = {}
File.__index = File
function File:write(s) return ffi.C.fputs(s, self) >= 0 end
function File:close() ffi.C.fclose(ffi.gc(self, nil)) end   -- remove the finalizer, then close
ffi.metatype("FILE", File)

local function open(path, mode)
  local f = ffi.C.fopen(path, mode)
  if f == nil then return nil, ffi.string(ffi.C.strerror(ffi.errno())) end
  return ffi.gc(f, ffi.C.fclose)          -- closed by the GC if you forget
end

local f = assert(open("ffi-demo.txt", "w"))
f:write("hello\n"), f:close()             --> true
open("no/such/dir/x", "r")                --> nil  No such file or directory
os.remove("ffi-demo.txt")
```

### Callbacks

```lua
local ffi = require("ffi")
ffi.cdef[[
typedef int (*cmp_fn)(const void *a, const void *b);
void qsort(void *base, size_t n, size_t size, cmp_fn cmp);
]]

local cmp = ffi.cast("cmp_fn", function(a, b)  -- cast once, keep it referenced
  local x, y = ffi.cast("const int *", a)[0], ffi.cast("const int *", b)[0]
  return x < y and -1 or (x > y and 1 or 0)
end)

local arr = ffi.new("int[5]", 5, 3, 1, 4, 2)
ffi.C.qsort(arr, 5, ffi.sizeof("int"), cmp)
cmp:free()                                -- C won't call it any more
arr[0], arr[1], arr[2], arr[3], arr[4]    --> 1  2  3  4  5
```

- A Lua function passed straight to a C function becomes a callback that is never freed. Cast it
  once instead.
- Callback slots are limited (500 to 1000, depending on the CPU) and the GC never frees them.
  Reuse callbacks; free them when done.
- A Lua error must not escape into C: wrap the body in `pcall` and report failure the way the C
  API expects (a return code).
- If a JIT-compiled Lua function calls C that calls back into Lua, you get
  `PANIC: ... (bad callback)`. Call `jit.off(f)` on that Lua function
  ([Chapter 16](16-callbacks-and-curl.md)).

### Loading a library under several names

```lua
local ffi = require("ffi")
ffi.cdef[[ unsigned long crc32(unsigned long crc, const unsigned char *buf, unsigned int len); ]]

local function load_any(...)
  for i = 1, select("#", ...) do
    local ok, lib = pcall(ffi.load, (select(i, ...)))
    if ok then return lib end
  end
  error("cannot load any of: " .. table.concat({ ... }, ", "))
end

local z = load_any("z", "libz.so.1")      -- the dev symlink, then the soname
tonumber(z.crc32(0, "hello", 5))          --> 907060870
```

`ffi.load("z")` looks for `libz.so`, which only the development package installs; the versioned
name (`libz.so.1`) is always there ([Chapter 15](15-wrapping-sqlite.md)).

### Memory from `malloc`

```lua
local ffi = require("ffi")
ffi.cdef[[ void *malloc(size_t n); void free(void *p); ]]
local p = ffi.gc(ffi.cast("uint8_t *", ffi.C.malloc(16)), ffi.C.free)
p[0] = 7
p[0]                                      --> 7
ffi.C.free(ffi.gc(p, nil))                -- free now, and stop the GC from freeing it again
```

Prefer `ffi.new` when you can: the GC frees it.

## Ownership checklist

Check every pointer that crosses between Lua and C.

1. **Who frees it?** Read the C docs for each pointer you get back.
   - "The caller must free it" → `ffi.gc(p, lib.free_fn)`, or free it yourself, exactly once.
   - Borrowed or static (`strerror`, `sqlite3_errmsg`, `curl_version`) → copy it with
     `ffi.string` right away, and never free it.
2. **Keep GC memory alive while C uses it.** `ffi.new` memory is freed when no Lua variable,
   table or upvalue refers to it. Pointers don't count: a struct field pointing to an `ffi.new`
   array doesn't keep the array alive.
3. **Lua strings live as long as you reference them.** C may use a string you passed only during
   the call. If C keeps the pointer, keep the string referenced or let C copy it
   (`SQLITE_TRANSIENT`).
4. **Close scarce resources explicitly.** Finalizers run whenever the GC gets to them. Close
   files, database handles and connections yourself; keep `ffi.gc` as the safety net.
5. **Close by hand with `lib.close(ffi.gc(h, nil))`.** It removes the finalizer first, so the GC
   can't free the handle a second time.
6. **Check for NULL before using a pointer:** `if p == nil then`.
7. **Callbacks:** cast once, keep the cdata referenced, `pcall` inside, `cb:free()` when C stops
   calling, `jit.off` the Lua function that triggers C to call back.
8. **Numbers:** `tonumber()` 64-bit results; pass integers to varargs as `ffi.new("int", x)` or
   `ffi.cast("long", x)`.
9. **One cdef per declaration.** Keep each library's cdef in one module, so `require` runs it
   once.
10. **The FFI has no safety net.** A wrong declaration or a bad pointer crashes the process.
    Never give `ffi` to untrusted code ([Chapter 19](19-plugins-and-scripting.md)).

## Error messages

| Message | Cause |
|---------|-------|
| `missing declaration for symbol 'f'` | `ffi.C.f` or `lib.f` with no `ffi.cdef` for `f` |
| `.../luajit: undefined symbol: f` | declared, but the library (here: `ffi.C`) doesn't have it; use `ffi.load` |
| `libfoo.so: cannot open shared object file: No such file or directory` | `ffi.load("foo")` found no library |
| `attempt to redefine 'point'` | a second cdef of the same struct |
| `')' expected near '<eof>'` | a C syntax error in a cdef |
| `undeclared or implicit tag 'nope'` | `struct nope` was never declared |
| `cannot convert 'string' to 'int'` | wrong Lua type for a C argument or field |
| `too many initializers for 'int [2]'` | more initializers than elements |
| `'struct point' has no member named 'z'` | a typo in a field name |
| `size of C type is unknown or too large` | `ffi.new` of an opaque struct; use pointers to it |
| `attempt to get length of 'int [3]'` | `#` on cdata |
| `PANIC: unprotected error in call to Lua API (bad callback)` | a C callback re-entered JIT-compiled code; `jit.off` the caller |
| `Segmentation fault` | a NULL or dangling pointer, a wrong cdef, or freed memory |

Redeclaring a *function* with a different signature gives no error; the first declaration wins.

Sources for this appendix: [REFERENCES.md](REFERENCES.md#appendix-b--ffi-reference)
