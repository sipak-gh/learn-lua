# Chapter 13 — FFI Basics

Standard Lua can only do what ANSI C's standard library can do. It can't create a directory, ask
whether output goes to a terminal, or call SQLite. In plain Lua each such feature needs a C module:
glue code written against the Lua C API and compiled per platform. LuaJIT's **FFI** (foreign
function interface) does better. You paste C declarations into your Lua code and call C functions
directly, with no glue code and nothing to compile. Nearly every library worth having (libc, zlib,
SQLite, curl, OpenSSL, SDL) has a C API, so this opens all of them to a scripting language.

This chapter covers declaring and calling functions, converting values between Lua and C, pointers
and `NULL`, type information, `errno`, and platform differences. Then `stash` uses libc for `mkdir`
without the shell, and for colored output when a person is watching.

Previous: [Chapter 12 — I/O and the OS](12-io-and-os.md). Next: [Chapter 14 — C data](14-c-data.md).

## What the FFI is

`require("ffi")` loads the FFI library, which is built into LuaJIT. Calling C takes two steps:

1. `ffi.cdef(declarations)` gives the FFI C declarations as a string: the same function prototypes,
   `struct`s, `typedef`s and `enum`s you'd find in a C header. LuaJIT's built-in C parser reads them
   at runtime.
2. A *namespace* finds the function. `ffi.C` is the C library plus everything else already loaded
   into the process (`printf`, `strlen`, `mkdir`, ...). `ffi.load` loads other libraries
   ([Chapter 15](15-wrapping-sqlite.md)).

`examples/ch13/hello.lua`

```lua
-- Calling a C function from Lua: declare it, then call it.

local ffi = require("ffi")

-- 1. Tell the FFI what the function looks like, in plain C.
ffi.cdef [[
int printf(const char *format, ...);
]]

-- 2. Call it through ffi.C, the C library that is already loaded.
local n = ffi.C.printf("Hello from %s, %d + %d = %d\n", "C", ffi.new("int", 2),
                       ffi.new("int", 3), ffi.new("int", 5))
print("printf returned", n, type(n))
```

```console
$ luajit examples/ch13/hello.lua
Hello from C, 2 + 3 = 5
printf returned	24	number
```

Declarations usually go in a `[[ ... ]]` long string. `cdef` runs nothing; it only tells the FFI
what exists. Looking up `ffi.C.printf` finds the symbol in the loaded libraries and binds it to the
declaration.

`printf` writes through C's `stdout`, the same C `FILE` that LuaJIT's `print` and `io.write` use.
They share one buffer, so the output appears in order.

### Why it is special

- **The declarations are plain C, and they *are* the binding.** There is no separate binding
  language and no glue to compile. You copy prototypes from the library's header, and when the
  library changes, you update a few lines of text.
- **The JIT compiles FFI calls.** In a hot loop, a call through `ffi.C` becomes a direct
  machine-code call, as a C compiler would emit, with the arguments converted inline. A classic
  Lua C module call goes through the Lua stack every time.

`examples/ch13/jitcall.lua`

```lua
-- FFI calls are compiled by the JIT into direct machine-code calls.

local ffi = require("ffi")
ffi.cdef [[
int abs(int n);
]]
local C = ffi.C

local sum = 0
for i = 1, 1e7 do
  sum = sum + C.abs(-i)       -- one C call per iteration
end
print(sum)
```

```console
$ luajit -jv examples/ch13/jitcall.lua
[TRACE   1 jitcall.lua:10 loop]
50000005000000
```

`-jv` prints a line for every trace the JIT compiles ([Chapter 18](18-performance-and-the-jit.md)
explains traces). `TRACE 1 ... loop` means the whole loop, C call included, became machine code;
after the first few iterations the interpreter isn't involved.

The price: **the FFI is not memory-safe.** A wrong declaration, a bad pointer or a freed buffer
crashes the process with a segmentation fault, not a Lua error. You are writing C, with C's rules,
in Lua syntax. Wrap FFI calls in small modules with a safe Lua interface and keep the rest of the
program plain Lua, as `stash` does.

## Calling libc

`examples/ch13/libc_calls.lua`

```lua
-- A few everyday libc functions.

local ffi = require("ffi")

ffi.cdef [[
size_t strlen(const char *s);
char *getenv(const char *name);
int getpid(void);
typedef long time_t;
time_t time(time_t *t);
int abs(int n);
double floor(double x);
]]

local C = ffi.C

-- A Lua string is passed as a const char* to its bytes.
local len = C.strlen("hello")
print("strlen:", len, type(len), tonumber(len))

-- getenv returns a char*. ffi.string copies the C string into a Lua string.
local home = C.getenv("HOME")
print("getenv:", type(home), ffi.string(home) == os.getenv("HOME"))

-- A missing variable gives a NULL pointer.
local missing = C.getenv("STASH_NO_SUCH_VAR")
print("NULL:", missing, missing == nil)

print("getpid:", type(C.getpid()))   -- int results arrive as Lua numbers
print("time:", C.time(nil) - os.time() <= 1)
print("abs:", C.abs(-42), "floor:", C.floor(2.7))
```

```console
$ luajit examples/ch13/libc_calls.lua
strlen:	5ULL	cdata	5
getenv:	cdata	true
NULL:	cdata<char *>: NULL	true
getpid:	number
time:	true
abs:	42	floor:	2
```

- **Arguments.** A Lua string passed to `const char *` becomes a pointer to its bytes. Lua strings
  always end with a hidden `\0`, so C sees a normal C string. Lua numbers are converted to `int` or
  `double` parameters.
- **Results.** `int` and `double` results become Lua numbers. `size_t` is a 64-bit integer here,
  which doesn't always fit in a double, so `strlen` returns a `uint64_t` *cdata*, printed as `5ULL`.
  `tonumber` turns it into a Lua number.
- **Pointers** come back as cdata too. `ffi.string(ptr)` copies a C string (up to its `\0`) into a
  new Lua string. Use `ffi.string(ptr, len)` when you know the length or the data may contain zeros.
- `time_t` isn't built into the FFI, so we declared it (`typedef long time_t;`), which is right on
  64-bit Linux and macOS. Getting such details right per platform is part of using the FFI.

`cdata` is the Lua type of every C value the FFI creates: numbers that don't fit a Lua number,
pointers, structs, arrays. `type(x)` returns `"cdata"`; `ffi.typeof(x)` gives the C type.

### Variadic functions

For `printf`'s `...` the declaration gives no types, so the FFI applies fixed rules. The surprising
one: a Lua number is passed as a `double`.

`examples/ch13/varargs.lua`

```lua
-- Variadic C functions (the "..." in printf) get no type information,
-- so the FFI uses default rules: a Lua number is passed as a double.

local ffi = require("ffi")
ffi.cdef [[
int printf(const char *format, ...);
]]

ffi.C.printf("%%g  with a Lua number: %g\n", 42)                -- fine: %g expects a double
ffi.C.printf("%%d  with a Lua number: %d\n", 42)                -- wrong: %d expects an int
ffi.C.printf("%%d  with an int:       %d\n", ffi.new("int", 42))
ffi.C.printf("%%d  with a cast:       %d\n", ffi.cast("int", 42))
ffi.C.printf("%%s  with a Lua string: %s\n", "strings are fine")
ffi.C.printf("%%lld with 1LL:         %lld\n", 1LL)              -- int64_t literal
```

```console
$ luajit examples/ch13/varargs.lua
%g  with a Lua number: 42
%d  with a Lua number: 0
%d  with an int:       42
%d  with a cast:       42
%s  with a Lua string: strings are fine
%lld with 1LL:         1
```

`%d` read an `int` from where the `double` wasn't. That is undefined behavior in C; the `0` may be
any number on your machine. For integer formats pass a typed value: `ffi.new("int", n)` or
`ffi.cast("int", n)`. Strings, `1LL` and other cdata pass with their own types.

## Converting between Lua and C

`examples/ch13/conversions.lua`

```lua
-- How values cross between Lua and C.

local ffi = require("ffi")

-- 64-bit integers: the LL and ULL suffixes make int64_t / uint64_t cdata.
local big = 9007199254740993LL           -- 2^53 + 1: too big for a double
print(big, type(big), ffi.typeof(big))
print(("%.0f"):format(9007199254740993)) -- the same digits as a Lua number lose the 1
print(big + 1, big * 2)                  -- arithmetic stays 64-bit
print(-1ULL)                             -- unsigned wraps around
print(5LL / 2LL, 5LL % 3LL)              -- integer division

-- tonumber turns cdata numbers into Lua numbers (a double; may round).
print(tonumber(42LL), ("%.0f"):format(tonumber(big)))

-- Comparisons mix freely; table keys do not.
print(42LL == 42, 1LL < 2)
local t = { [42] = "number key" }
print(t[42LL])                           -- cdata is a different key

-- Lua -> C when calling a function with a declared type:
ffi.cdef [[
int abs(int n);
double fabs(double x);
]]
print(ffi.C.abs(-3.9))                   -- number -> int truncates toward 0
print(ffi.C.fabs(-3.9))
print(ffi.C.abs(true))                   -- a boolean becomes 1 or 0
print(pcall(ffi.C.abs, "7"))             -- strings are not converted to numbers
print(pcall(ffi.C.abs, nil))             -- nil is not a number

-- Results: small integers and doubles become Lua numbers,
-- 64-bit integers stay cdata, pointers stay cdata, bool becomes boolean.
local flags = ffi.new("bool[2]", true, false)
print(flags[0], flags[1], type(flags[0]))
```

```console
$ luajit examples/ch13/conversions.lua
9007199254740993LL	cdata	ctype<int64_t>
9007199254740992
9007199254740994LL	18014398509481986LL
18446744073709551615ULL
2LL	2LL
42	9007199254740992
true	true
nil
3
3.9
1
false	bad argument #1 to '?' (cannot convert 'string' to 'int')
false	bad argument #1 to '?' (cannot convert 'nil' to 'int')
true	false	boolean
```

**64-bit integers.** Lua numbers are doubles, exact for integers only up to 2^53. LuaJIT adds
suffixed literals: `1LL` is an `int64_t` cdata, `1ULL` a `uint64_t`. Arithmetic on them stays
64-bit integer arithmetic (`/` truncates, `-1ULL` wraps to the largest value), and a Lua number
mixed in is converted to 64-bit first.

The traps:

- `tonumber(x)` converts back to a double and may round, as `2^53 + 1` did above.
- `42LL == 42` is true, but they are different *table keys*: `t[42LL]` doesn't find `t[42]`. Use
  `tonumber` before using a C integer as a key.

**Lua to C, for declared parameters:**

| Lua value | C parameter | result |
|---|---|---|
| number | integer type | truncated toward zero (`-3.9` → `-3`) |
| number | `double`/`float` | as is |
| boolean | integer or `bool` | `true` → 1, `false` → 0 |
| string | `const char *` | pointer to the string's bytes (safe only during the call) |
| string | integer | error: no automatic conversion |
| `nil` | pointer | `NULL` |
| cdata | matching type | as is |

**C to Lua, for results and fields:**

| C type | Lua value |
|---|---|
| `int`, `short`, `char`, `float`, `double`, ... (fits in a double) | number |
| `int64_t`, `uint64_t`, `size_t`, `long` on 64-bit | cdata (`1LL`, `1ULL`) |
| `bool` | boolean |
| pointers, structs, arrays | cdata |

In the `string` row, the pointer points into the Lua string. If C keeps it after the call returns,
the string may already be garbage. [Chapter 14](14-c-data.md) covers lifetimes.

## NULL is not nil

`examples/ch13/null.lua`

```lua
-- NULL pointers are cdata, not nil.

local ffi = require("ffi")
ffi.cdef [[
char *getenv(const char *name);
]]

local p = ffi.C.getenv("STASH_NO_SUCH_VAR")
print(type(p), p == nil)        -- cdata, but compares equal to nil
print(not p)                    -- false: every cdata is "true" in an if!
if p then print("if p: taken, even though p is NULL") end

-- The safe test is an explicit comparison:
if p == nil then print("p == nil: NULL") end

-- A helper that turns a C string result into a Lua string or nil:
local function cstring(ptr)
  if ptr == nil then return nil end
  return ffi.string(ptr)
end
print(cstring(p), cstring(ffi.C.getenv("HOME")) ~= nil)

-- You can make a NULL pointer of any type yourself:
local q = ffi.new("int *")      -- pointers start out NULL
print(q == nil, ffi.cast("void *", 0) == nil)
```

```console
$ luajit examples/ch13/null.lua
cdata	true
false
if p: taken, even though p is NULL
p == nil: NULL
nil	true
true	true
```

A `NULL` pointer is cdata, and every cdata is true in Lua, so `if p then` is **always** taken. The
FFI does make `p == nil` true for `NULL`, so always compare explicitly. Never call `ffi.string(p)`
on `NULL`: it reads address 0 and crashes the process.

## Type information

`examples/ch13/types.lua`

```lua
-- Asking the FFI about C types.

local ffi = require("ffi")
ffi.cdef [[
struct point { int x, y; };
struct sample { char tag; double value; short count; };
]]

-- ffi.typeof turns a C type into a ctype object. Calling it creates values.
local point_t = ffi.typeof("struct point")
local p = point_t(3, 4)
print(point_t, p.x, p.y)

-- Sizes and alignment in bytes (on this machine).
print("int", ffi.sizeof("int"), "double", ffi.sizeof("double"), "pointer", ffi.sizeof("void *"))
print("struct point", ffi.sizeof(point_t), ffi.alignof(point_t))

-- The compiler inserts padding to align each field.
print("struct sample", ffi.sizeof("struct sample"))
for _, field in ipairs({ "tag", "value", "count" }) do
  print("  offsetof " .. field, ffi.offsetof("struct sample", field))
end

-- ffi.istype checks whether a value has a given C type.
print(ffi.istype(point_t, p), ffi.istype("struct point", p), ffi.istype("int", p))
print(ffi.istype("int", 42))    -- a Lua number is not cdata at all

-- tostring of a ctype shows its C name; typeof also works on values.
print(ffi.typeof(p), ffi.typeof(1LL), ffi.typeof("int[3]"))
```

```console
$ luajit examples/ch13/types.lua
ctype<struct point>	3	4
int	4	double	8	pointer	8
struct point	8	4
struct sample	24
  offsetof tag	0
  offsetof value	8
  offsetof count	16
true	true	false
false
ctype<struct point>	ctype<int64_t>	ctype<int [3]>
```

- `ffi.typeof(ctype)` parses a type once and returns a *ctype* object. Calling it creates values
  (`point_t(3, 4)`). Keep ctypes you use often in locals to skip reparsing the string.
- `ffi.sizeof`, `ffi.alignof` and `ffi.offsetof` match C's `sizeof`, `_Alignof` and `offsetof` on
  this platform. `struct sample` shows padding: the `double` `value` must start at a multiple of 8,
  so 7 unused bytes follow `tag`, and the struct's size is rounded up to a multiple of 8 too.
- `ffi.istype(ctype, x)` is true when `x` is cdata of that type. A Lua number is never cdata.

## errno and strerror

C functions usually signal failure with a special return value (`-1`, `NULL`) and store the reason
in a global integer, `errno`. `strerror(errno)` turns it into a message.

`examples/ch13/errno.lua`

```lua
-- C reports errors through a return value plus the global `errno`.

local ffi = require("ffi")
ffi.cdef [[
int mkdir(const char *path, unsigned int mode);
int rmdir(const char *path);
char *strerror(int errnum);
]]

local function try_mkdir(path)
  local rc = ffi.C.mkdir(path, tonumber("755", 8))
  if rc ~= 0 then
    local errno = ffi.errno()        -- read it right away
    return nil, ("%s: %s (errno %d)"):format(path, ffi.string(ffi.C.strerror(errno)), errno)
  end
  return true
end

print(try_mkdir("demo-dir"))
print(try_mkdir("demo-dir"))          -- already exists
print(try_mkdir("no/such/parent"))
print(try_mkdir("/stash-demo"))       -- no permission to write in /
ffi.C.rmdir("demo-dir")

-- ffi.errno(new) sets errno and returns the old value.
ffi.errno(0)
print(ffi.errno())
```

```console
$ luajit examples/ch13/errno.lua
true
nil	demo-dir: File exists (errno 17)
nil	no/such/parent: No such file or directory (errno 2)
nil	/stash-demo: Permission denied (errno 13)
0
```

`ffi.errno()` returns the current `errno`. **Read it right after the failed call**: any later C
call may overwrite it. (LuaJIT's own internal work, such as memory allocation, preserves it.) Here
the code saves it in a local before calling `strerror`.

The `mkdir` mode is `tonumber("755", 8)`: Lua has no octal literals, and `0755` is just 755.

The classic `errno` values and messages are the same on Linux and macOS (`2` `ENOENT`, `13`
`EACCES`, `17` `EEXIST`, `20` `ENOTDIR`). Newer ones differ, so don't hard-code more than you need.

## Platforms

`examples/ch13/platform.lua`

```lua
-- Where am I running? The FFI knows.

local ffi = require("ffi")

print("os:  ", ffi.os)                -- "Linux", "OSX", "Windows", "BSD", ...
print("arch:", ffi.arch)              -- "x64", "arm64", "x86", ...
for _, flag in ipairs({ "32bit", "64bit", "le", "be", "fpu", "hardfp", "win" }) do
  print(("abi(%q) = %s"):format(flag, tostring(ffi.abi(flag))))
end

-- Types whose size depends on the platform:
print("long:", ffi.sizeof("long"), "size_t:", ffi.sizeof("size_t"))

-- Choose declarations by platform when they differ.
if ffi.os == "Windows" then
  ffi.cdef("int _getpid(void);")
  print("pid via _getpid", ffi.C._getpid() > 0)
else
  ffi.cdef("int getpid(void);")
  print("pid via getpid", ffi.C.getpid() > 0)
end
```

```console
$ luajit examples/ch13/platform.lua
os:  	Linux
arch:	x64
abi("32bit") = false
abi("64bit") = true
abi("le") = true
abi("be") = false
abi("fpu") = true
abi("hardfp") = true
abi("win") = false
long:	8	size_t:	8
pid via getpid	true
```

Your output depends on your machine; a Mac with Apple silicon shows `OSX` and `arm64`.

- `ffi.os` and `ffi.arch` name the system and the CPU.
- `ffi.abi(flag)` tests a platform property: `"64bit"`, `"le"` (little-endian), `"win"`, and more.
- C type sizes vary. `long` is 8 bytes on 64-bit Linux and macOS but 4 on 64-bit Windows. Typedefs
  differ too: `mode_t` is 32 bits on Linux, 16 on macOS. Use fixed-size types (`int32_t`,
  `uint64_t`) when you control the declaration, and branch on `ffi.os` when you don't.
- Function names differ (`getpid` vs `_getpid`). A missing symbol only fails when you *use* it, so
  declaring both is harmless.

## No preprocessor: #define

`examples/ch13/defines.lua`

```lua
-- C headers are full of #define constants. The FFI's C parser has no
-- preprocessor, so you bring the values over yourself.

local ffi = require("ffi")

-- This fails: cdef only understands declarations.
print(pcall(ffi.cdef, "#define EEXIST 17"))

-- Option 1: a plain Lua constant.
local O_RDONLY = 0

-- Option 2: an enum. Its constants live in ffi.C and are typed.
ffi.cdef [[
enum { SEEK_SET = 0, SEEK_CUR = 1, SEEK_END = 2 };
]]
print("enum:", ffi.C.SEEK_END)

-- Option 3: a static const. Also reachable through ffi.C.
ffi.cdef [[
static const int EEXIST = 17;
]]
print("static const:", ffi.C.EEXIST)

-- Enums also give names to a C type's values:
ffi.cdef [[
typedef enum { RED, GREEN = 5, BLUE } color;
]]
local c = ffi.new("color", "BLUE")    -- a string converts to the enum value
print("color:", tonumber(c), c == ffi.C.BLUE, ffi.C.GREEN)
print("lua const:", O_RDONLY)
```

```console
$ luajit examples/ch13/defines.lua
false	unexpected symbol near 'define'
enum:	2
static const:	17
color:	6	true	5
lua const:	0
```

The FFI parses C declarations, not the preprocessor: `#define`, `#include` and `#ifdef` don't work.
Since most C constants are `#define`s, you copy their *values* from the headers (or from a small C
program that prints them) in one of three forms:

- **Lua constants** (`local EEXIST = 17`). Simple and clear; `stash` does this.
- **`enum`** in a cdef. The names are reachable as `ffi.C.NAME`, and a string such as `"BLUE"`
  converts to the enum value when you create one.
- **`static const int`** in a cdef, also reachable through `ffi.C`.

Values copied from headers are platform-specific. Check them on each system you support.

## When declarations go wrong

`examples/ch13/cdef_errors.lua`

```lua
-- What happens when declarations are wrong or missing.

local ffi = require("ffi")

-- Calling something you never declared:
print(pcall(function() return ffi.C.strlen("x") end))

-- Declaring a function that does not exist in the library:
ffi.cdef("int no_such_function(int);")
print(pcall(function() return ffi.C.no_such_function(1) end))

-- A C syntax error:
print(pcall(ffi.cdef, "int broken(int x"))

-- An unknown type:
print(pcall(ffi.cdef, "my_type f(void);"))

-- Struct definitions can only be given once per process:
ffi.cdef("struct pair { int a, b; };")
print(pcall(ffi.cdef, "struct pair { int a, b; };"))

-- But a function declared twice keeps the first declaration, silently:
ffi.cdef("int abs(int);")
ffi.cdef("double abs(double);")
print(ffi.C.abs(-2.5))
```

```console
$ luajit examples/ch13/cdef_errors.lua
false	examples/ch13/cdef_errors.lua:6: missing declaration for symbol 'strlen'
false	examples/ch13/cdef_errors.lua:10: luajit: undefined symbol: no_such_function
false	')' expected near '<eof>'
false	declaration specifier expected near 'my_type'
false	attempt to redefine 'pair'
2
```

- A name that was never declared: `missing declaration for symbol`.
- A declared name that isn't in any loaded library is fine until you look it up in `ffi.C`. Then
  the dynamic linker reports `undefined symbol` (the exact text varies by system).
- `ffi.cdef` itself reports syntax errors and unknown types.
- Struct definitions are global to the process and allowed only once. A module that defines a
  struct must run only once, which `require` ensures.
- A second declaration of a function is **silently ignored**: the first wins, even if the second is
  right. Keep all declarations for one library in one module.

Declarations aren't checked against the real function either. Declare `double abs(double)` first
and LuaJIT believes you, passing the argument in the wrong kind of register. Wrong declarations are
the most common FFI bug, so copy prototypes from the real headers.

## Building stash: libc and colors

Two small FFI changes:

- `fs.mkdir_p` calls C's `mkdir` instead of running `mkdir -p` in a shell: no process to start, no
  quoting, and real error messages.
- `list` and `tags` use color on a terminal. That needs `isatty`, which standard Lua lacks.

Terminal width needs a C struct, so it comes in [Chapter 14](14-c-data.md).

New files: `src/stash/ffi/libc.lua`, `src/stash/term.lua`, `test/fs_test.lua`,
`test/term_test.lua`, `test/fixtures/config_choice.lua`. Changed: `fs.lua`, `config.lua`,
`commands.lua`, `main.lua`, and the tests `commands_test`, `config_test`, `e2e_test` and `run.lua`.

### src/stash/ffi/libc.lua (new)

All of `stash`'s raw libc declarations live in one module, in a new `ffi/` directory for raw
bindings (`ffi/sqlite.lua` and `ffi/curl.lua` join it later).

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
]]

local M = {}

-- #define constants don't exist for the FFI; we copy their values.
M.EEXIST = 17                                -- the same on Linux and macOS

-- The message for an errno value (default: the latest one).
function M.strerror(errnum)
  return ffi.string(ffi.C.strerror(errnum or ffi.errno()))
end

return M
```

- `require("ffi")` still loads LuaJIT's FFI; our module has a different name, `stash.ffi.libc`.
- `mode_t` differs between Linux and macOS, so `ffi.os` picks its typedef, which must come before
  the declarations that use it.
- `EEXIST` is a `#define` in `<errno.h>`, so its value is copied.
- `M.strerror` hides `ffi.string` and the `char *`; callers get a plain Lua string.

### src/stash/fs.lua

`shell_quote` and the `os.execute` call go away. Replace the top of the file, through `mkdir_p`,
with:

```lua
-- File system helpers.

local ffi = require("ffi")
local libc = require("stash.ffi.libc")

local M = {}

-- Creates a directory and its parents, like `mkdir -p`, by calling
-- mkdir(2) for "a", "a/b", "a/b/c" in turn. "Already exists" is fine.
function M.mkdir_p(path)
  local prefix = path:sub(1, 1) == "/" and "/" or ""
  for part in path:gmatch("[^/]+") do
    prefix = prefix .. part
    if ffi.C.mkdir(prefix, tonumber("755", 8)) ~= 0 then
      local errno = ffi.errno()              -- read it at once: the next C call may change it
      if errno ~= libc.EEXIST then
        return nil, prefix .. ": " .. libc.strerror(errno)
      end
    end
    prefix = prefix .. "/"
  end
  return true
end
```

C's `mkdir` creates one directory, so we walk the path: `a`, `a/b`, `a/b/c`. `EEXIST` means that
level already exists, so we go on. Any other error stops us and returns the C message, such as
`demo/blocker/sub: Not a directory`.

An existing *file* also gives `EEXIST`; then the next level, or the save that follows, fails with
`Not a directory`. That message is clear enough, so we accept it.

### src/stash/term.lua (new)

```lua
-- Terminal output: color, but only when a person is watching.

local ffi = require("ffi")
require("stash.ffi.libc")                    -- declares isatty

local M = {}

-- ANSI escape codes ("Select Graphic Rendition") for each kind of text.
local STYLES = {
  id = "33",                                 -- yellow
  tag = "36",                                -- cyan
  dim = "2",
}

-- True when file descriptor fd (1 = stdout) is a terminal, not a pipe
-- or a file. isatty returns a C int, which arrives as a Lua number.
function M.is_tty(fd)
  return ffi.C.isatty(fd) == 1
end

-- Decides whether to use color, from the `color` setting:
-- "always", "never", or "auto" (a terminal, and NO_COLOR is not set).
function M.use_color(setting)
  if setting == "auto" then
    return M.is_tty(1) and os.getenv("NO_COLOR") == nil and os.getenv("TERM") ~= "dumb"
  end
  return setting == "always"
end

-- Returns a function paint(text, style). With color off it returns the
-- text unchanged, so callers never need to check.
function M.painter(enabled)
  if not enabled then
    return function(text)
      return text
    end
  end
  return function(text, style)
    return "\27[" .. STYLES[style] .. "m" .. text .. "\27[0m"
  end
end

return M
```

- **`is_tty`.** `isatty(fd)` returns the `int` `1` for a terminal and `0` otherwise. It arrives as a
  Lua number, and `0` is *true* in Lua, so compare with `== 1`. Never write
  `if ffi.C.isatty(1) then`.
- **`use_color`.** `auto` colors only when stdout is a terminal, so piping `stash list` into `grep`
  or a file gives clean text. Two conventions also turn color off: the `NO_COLOR` environment
  variable and `TERM=dumb`.
- **`painter`.** Colors are ANSI escape sequences: `ESC [ 33 m` switches to yellow, `ESC [ 0 m`
  resets. `\27` is the escape byte (decimal 27). `painter(false)` returns a function that ignores
  the style, so callers always call `paint(text, style)` without checking whether color is on.

### src/stash/config.lua

The new `color` setting accepts only three values. Add it to the defaults, add the choices table
and a helper after it, and mention it in the top comment:

```lua
-- Configuration: $STASH_HOME/config.lua is a Lua file that sets variables.
--
--   list_limit = 10
--   aliases = { ls = "list", lua = "list -t lua" }
--   color = "never"
--
-- Config is code, so we run it, but in an empty environment: it cannot
-- see our globals, and its assignments land in a table we inspect.

local M = {}

-- Every known setting with its default. The type of the default is the
-- type the setting must have.
M.defaults = {
  list_limit = 20,
  aliases = {},
  color = "auto",
}

-- Settings that only accept a few values.
M.choices = {
  color = { "auto", "always", "never" },
}

local function is_one_of(value, choices)
  for _, choice in ipairs(choices) do
    if value == choice then
      return true
    end
  end
  return false
end
```

Then check the choices in `M.load`, after the type check:

```lua
    if type(value) ~= type(default) then
      return nil, ("%s: '%s' must be a %s"):format(path, key, type(default))
    end
    local choices = M.choices[key]
    if choices and not is_one_of(value, choices) then
      return nil, ("%s: '%s' must be one of %s"):format(path, key, table.concat(choices, ", "))
    end
    settings[key] = value
```

### src/stash/commands.lua

The context gets a `paint` function (mention it in the top comment). `format_row` uses it:

```lua
-- Pads first, then paints: escape codes have no width on screen, but
-- string.format would count them.
local function format_row(ctx, entry)
  local paint = ctx.paint
  return ("%s  %-36s  %s  %s"):format(
    paint(("%3d"):format(entry.id), "id"),
    util.truncate(entry.title, 36),
    paint(("%-16s"):format(util.truncate(entry:tag_string(), 16)), "tag"),
    paint(util.date(entry.created), "dim"))
end
```

`("%-16s"):format(s)` pads to 16 *bytes*. Escape sequences are bytes that take no space on screen,
so a painted string would come out short. Pad first, then paint.

`list` and `search` now call `format_row(ctx, entry)`. `tags` paints the tag name:

```lua
      ctx.out(("%4d  %s"):format(row.count, ctx.paint(row.tag, "tag")))
```

### src/stash/main.lua

Require `stash.term` with the other modules (`local term = require("stash.term")`) and add `paint`
to the context:

```lua
  local ctx = {
    store = store,
    config = settings,
    out = print,
    paint = term.painter(term.use_color(settings.color)),
  }
```

### Tests

`test/commands_test.lua` builds its own context, which now needs a `paint`. One that changes
nothing keeps the expected output plain:

```lua
  local ctx = {
    store = store,
    config = config.defaults,
    out = function(line) lines[#lines + 1] = line end,
    paint = function(text) return text end,
  }
```

`test/fs_test.lua` (new) checks `mkdir_p`, including a C error:

```lua
local fs = require("stash.fs")

test("mkdir_p creates parents and accepts existing directories", function()
  local base = tmpdir("mkdir")
  eq(fs.mkdir_p(base .. "/a/b/c"), true)
  eq(fs.mkdir_p(base .. "/a/b"), true)
  ok(fs.exists(base .. "/a/b/c"))
end)

test("mkdir_p reports the C error", function()
  local base = tmpdir("mkdir-file")
  assert(fs.with_file(base .. "/file", "w", function() end))
  local done, err = fs.mkdir_p(base .. "/file/sub")
  eq(done, nil)
  eq(err, base .. "/file/sub: Not a directory")
end)

test("dirname", function()
  eq(fs.dirname("a/b/c.lua"), "a/b")
  eq(fs.dirname("c.lua"), ".")
end)
```

`test/term_test.lua` (new). `auto` depends on where output goes, so only `always` and `never` are
tested directly:

```lua
local term = require("stash.term")

test("always and never ignore the terminal", function()
  eq(term.use_color("always"), true)
  eq(term.use_color("never"), false)
end)

test("the painter wraps text in escape codes only when enabled", function()
  eq(term.painter(true)("7", "id"), "\27[33m7\27[0m")
  eq(term.painter(false)("7", "id"), "7")
end)
```

`test/config_test.lua` gets one test, with a fixture `test/fixtures/config_choice.lua` containing
`color = "sometimes"`:

```lua
test("some settings only accept a few values", function()
  eq(select(2, config.load("test/fixtures/config_choice.lua")),
     "test/fixtures/config_choice.lua: 'color' must be one of auto, always, never")
end)
```

`test/e2e_test.lua` checks real colored output end to end. Add at the end:

```lua
test("color = \"always\" in the config paints the list", function()
  assert(require("stash.fs").write_atomic(HOME .. "/config.lua", 'color = "always"\n'))
  eq(stash("list"),
     "\27[33m  2\27[0m  example.com                           \27[36mweb             \27[0m  "
     .. "\27[2m2026-01-01\27[0m\n")
  os.remove(HOME .. "/config.lua")
end)
```

And register the new files in `test/run.lua`:

```lua
local FILES = {
  "util_test", "cli_test", "entry_test", "iter_test", "memstore_test", "config_test",
  "commands_test", "json_test", "html_test", "fs_test", "filestore_test", "term_test",
  "e2e_test",
}
```

### Checkpoint

`cat -v` shows the escape byte as `^[`, making the codes visible. In your terminal the plain
`./stash list` is colored; here it isn't, because the output was captured to a file. `demo/blocker`
is a file, so creating a directory below it fails with the C error.

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
term_test        2 tests, 0 failed
e2e_test         4 tests, 0 failed

57 passed, 0 failed
$ export STASH_HOME=demo STASH_NOW=1767225600
$ PAGES=file://$PWD/test/fixtures
$ ./stash add $PAGES/lua.html -t lua,lang
added #1 The Programming Language Lua
$ ./stash add $PAGES/luajit.html -t lua,jit
added #2 LuaJIT: a Just-In-Time Compiler & FFI
$ ./stash list
  1  The Programming Language Lua          lang,lua          2026-01-01
  2  LuaJIT: a Just-In-Time Compiler &...  jit,lua           2026-01-01
$ echo 'color = "always"' > demo/config.lua
$ ./stash list | cat -v
^[[33m  1^[[0m  The Programming Language Lua          ^[[36mlang,lua        ^[[0m  ^[[2m2026-01-01^[[0m
^[[33m  2^[[0m  LuaJIT: a Just-In-Time Compiler &...  ^[[36mjit,lua         ^[[0m  ^[[2m2026-01-01^[[0m
$ ./stash tags | cat -v
   2  ^[[36mlua^[[0m
   1  ^[[36mjit^[[0m
   1  ^[[36mlang^[[0m
$ echo 'color = "sometimes"' > demo/config.lua
$ ./stash list; echo "exit $?"
stash: demo/config.lua: 'color' must be one of auto, always, never
exit 2
$ rm demo/config.lua
$ touch demo/blocker
$ STASH_HOME=demo/blocker/sub ./stash add https://example.com/; echo "exit $?"
stash: cannot save demo/blocker/sub/entries.lua: demo/blocker/sub: Not a directory
exit 2
```

Try `./stash list | cat` and `NO_COLOR=1 ./stash list` in your terminal: both are plain. Run
`rm -rf demo` when you're done.

The complete project at this point is in `project/ch13/`.

## Summary

- `ffi.cdef` takes C declarations as a string; `ffi.C` calls functions in the C library and anything
  already loaded. No glue code, and the JIT compiles the calls.
- The FFI is not memory-safe: a wrong declaration or pointer crashes the process. Keep FFI code in
  small wrapper modules.
- Numbers convert to `int`/`double` parameters; `const char *` takes Lua strings. 64-bit integer
  results are cdata (`5ULL`); `tonumber` makes a Lua number.
- In variadic arguments a Lua number is a `double`. Pass `ffi.new("int", n)` for `%d`.
- `NULL` is cdata. Test `p == nil`, never `if p`. Don't call `ffi.string` on `NULL`.
- `ffi.typeof`, `ffi.sizeof`, `ffi.alignof`, `ffi.offsetof` and `ffi.istype` describe C types.
- Read `ffi.errno()` right after a failed call; `strerror` gives the message.
- `ffi.os`, `ffi.arch` and `ffi.abi` handle platform differences. There are no `#define`s: use Lua
  constants, enums or `static const`.
- A struct can be defined only once. Function redeclarations are silently ignored.
- `stash`: `ffi/libc.lua`, `mkdir_p` through C, and `term.lua` colors only on a terminal.

## Exercises

1. Print the `strerror` messages for `errno` values 1 to 10.

<details><summary>Solution</summary>

```lua
local ffi = require("ffi")
ffi.cdef [[
char *strerror(int errnum);
]]

for errno = 1, 10 do
  print(errno, ffi.string(ffi.C.strerror(errno)))
end
```

```console
$ luajit strerror.lua
1	Operation not permitted
2	No such file or directory
3	No such process
4	Interrupted system call
5	Input/output error
6	No such device or address
7	Argument list too long
8	Exec format error
9	Bad file descriptor
10	No child processes
```

This is the output on Linux with glibc. Other systems word some messages differently.

</details>

2. Standard Lua can read environment variables but not set them. Declare `setenv` and `unsetenv`
   (from `<stdlib.h>`) and show that `os.getenv` sees the changes.

<details><summary>Solution</summary>

```lua
local ffi = require("ffi")
ffi.cdef [[
int setenv(const char *name, const char *value, int overwrite);
int unsetenv(const char *name);
]]

print(os.getenv("STASH_GREETING"))
assert(ffi.C.setenv("STASH_GREETING", "hello", 1) == 0)
print(os.getenv("STASH_GREETING"))
ffi.C.setenv("STASH_GREETING", "ignored", 0)       -- 0: keep an existing value
print(os.getenv("STASH_GREETING"))
ffi.C.unsetenv("STASH_GREETING")
print(os.getenv("STASH_GREETING"))
```

```console
nil
hello
hello
nil
```

`os.getenv` calls C's `getenv`, which reads the environment `setenv` changed. Programs started later
with `os.execute` or `io.popen` inherit the change too.

</details>

3. Predict what this prints when stdout is *not* a terminal (for example `luajit quiz.lua | cat`),
   then check:

   ```lua
   local ffi = require("ffi")
   ffi.cdef [[
   size_t strlen(const char *s);
   int isatty(int fd);
   char *getenv(const char *name);
   ]]
   local n = ffi.C.strlen("abc")
   print(n == 3, n + 1, type(n))
   print(ffi.C.isatty(1), ffi.C.isatty(1) and "tty?" or "no")
   print(ffi.C.getenv("NOPE") and "set" or "unset")
   ```

<details><summary>Solution</summary>

```console
true	4ULL	cdata
0	tty?
set
```

- `n` is a `uint64_t` cdata. `==` with a Lua number works; `n + 1` stays cdata.
- `isatty` returns `0`, which is true in Lua. That's why `term.is_tty` compares with `== 1`.
- `getenv` returns a `NULL` pointer: cdata, therefore true. Write `ffi.C.getenv("NOPE") ~= nil`.

</details>

4. The [NO_COLOR](https://no-color.org/) convention says color is turned off when `NO_COLOR` is set
   *to a non-empty value*. `term.use_color` treats `NO_COLOR=` (empty) as "off" too. Fix it.

<details><summary>Solution</summary>

In `term.use_color`:

```lua
  if setting == "auto" then
    local no_color = os.getenv("NO_COLOR")
    return M.is_tty(1) and (no_color == nil or no_color == "") and os.getenv("TERM") ~= "dumb"
  end
```

The tests can't reach this branch, since their stdout isn't a terminal. Check in a terminal:
`NO_COLOR= ./stash list` is colored, `NO_COLOR=1 ./stash list` plain.

</details>

5. Make `show` print the title in bold (SGR code `1`) when color is on.

<details><summary>Solution</summary>

Add a style to `STYLES` in `term.lua`:

```lua
  title = "1",                               -- bold
```

And paint the title in `show` (in `commands.lua`):

```lua
    ctx.out(("%-6s %s"):format("title:", ctx.paint(entry.title, "title")))
```

The tests still pass, because `commands_test` paints nothing. With `color = "always"` in the config:

```console
$ ./stash show 1 | cat -v
id:    1
title: ^[[1mwww.lua.org^[[0m
url:   https://www.lua.org/
tags:  
added: 2026-01-01 00:00 UTC
```

Nothing is padded after the title, so painting it can't break the alignment.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-13--ffi-basics)
