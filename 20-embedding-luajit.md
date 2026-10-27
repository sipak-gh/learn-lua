# Chapter 20 — Embedding LuaJIT

So far `stash` has been a Lua script run by `luajit`. Users need LuaJIT, SQLite and zlib
installed, plus the `src/` folder next to the launcher. This chapter turns it into one program
file: a small C host that starts LuaJIT, with every `stash` module compiled to bytecode and
linked in, along with SQLite and zlib. On the way you'll learn the Lua C API, which every
program that embeds Lua uses, and the linker details that decide what `ffi.C` can see.
[Chapter 19](19-plugins-and-scripting.md) made `stash` scriptable;
[Chapter 21](21-design-and-next-steps.md) looks back at the whole design.

## A host program

Lua is a C library. The `luajit` command is a small C program around it, and your program can
be one too. The library is the language; the host decides what the language can touch.

`examples/ch20/embed.c`

```c
/* The smallest useful host: create a Lua state, open the standard
   libraries, run some Lua code, report errors. */
#include <stdio.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/* Compiles and runs `code`; returns 0 on success. */
static int run(lua_State *L, const char *name, const char *code)
{
  int status = luaL_loadbuffer(L, code, strlen(code), name);  /* chunk */
  if (status == 0)
    status = lua_pcall(L, 0, 0, 0);       /* call it: 0 args, 0 results */
  if (status != 0) {
    fflush(stdout);                       /* keep print() output in order */
    fprintf(stderr, "error: %s\n", lua_tostring(L, -1));  /* the message */
    lua_pop(L, 1);
  }
  return status;
}

int main(void)
{
  lua_State *L = luaL_newstate();         /* a new, empty Lua world */
  if (L == NULL)
    return 1;
  luaL_openlibs(L);                       /* string, table, io, ffi, jit, ... */

  run(L, "=hello", "print('hello from ' .. jit.version)");
  run(L, "=math", "x = 6 * 7  print('x =', x)");
  run(L, "=again", "print('x is still', x)");   /* same state, same globals */
  run(L, "=syntax", "print('oops'");
  run(L, "=runtime", "local t = nil; print(t.field)");

  lua_close(L);                           /* frees everything, runs __gc */
  return 0;
}
```

`pkg-config` knows where LuaJIT's headers and library are:

```console
$ pkg-config --cflags --libs luajit
-I/usr/local/include/luajit-2.1 -L/usr/local/lib -lluajit-5.1
$ cc -Wall -o embed examples/ch20/embed.c $(pkg-config --cflags --libs luajit)
$ ./embed
hello from LuaJIT 2.1.1792588164
x =	42
x is still	42
error: syntax:1: ')' expected near '<eof>'
error: runtime:1: attempt to index local 't' (a nil value)
```

The paths depend on where LuaJIT is installed (here, `/usr/local`), and the version number on
your build.

The whole API in five calls:

| Call | What it does |
|------|--------------|
| `luaL_newstate()` | Creates a **state**: one independent Lua world with its own globals, GC and stack. |
| `luaL_openlibs(L)` | Adds the standard libraries. Without it there is no `print`, no `string`. |
| `luaL_loadbuffer(L, code, len, name)` | Compiles a chunk, like `loadstring`. On error, returns non-zero and pushes a message. |
| `lua_pcall(L, nargs, nresults, handler)` | Calls a function in protected mode, like `pcall`. |
| `lua_close(L)` | Runs all `__gc` metamethods and frees everything. |

What the output shows:

- **Chunk names** work as in [Chapter 19](19-plugins-and-scripting.md): `"=hello"` is used as
  it is.
- **One state keeps its globals.** `x` set by one chunk is there for the next.
- **Errors don't crash the host.** `lua_pcall` returns an error code and leaves the message on
  the stack. A Lua error outside a protected call runs a panic function and exits the program.
- **`luaL_openlibs` is a choice.** A host for untrusted scripts can open only some libraries:
  the Chapter 19 sandbox, one level down.

> **Gotcha: output order.** `print` writes to C's buffered `stdout`. When `stdout` is a pipe or a
> file, the buffer is flushed only when it fills or the program ends. The `fflush(stdout)` keeps
> the lines in order; without it, `./embed 2>&1 | cat` prints both errors first.

The headers are C, not C++. C++ hosts include LuaJIT's `lua.hpp`, which wraps them in
`extern "C"`.

## The stack

C and Lua don't share values directly: a Lua table can move or be collected, and a C pointer to
it would go stale. They talk through a **stack** of Lua values owned by the state. C pushes
values onto it; Lua functions take their arguments from it and leave their results on it. The GC
won't collect a value while it is on the stack.

Positions count from the bottom (1, 2, 3...) or from the top (-1 is the top, -2 below it).

`examples/ch20/stack.c`

```c
/* C and Lua talk through a stack of values. This program pushes values,
   reads them back, calls a Lua function and reads fields of a table. */
#include <stdio.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

static void dump(lua_State *L, const char *when)
{
  int i, top = lua_gettop(L);             /* number of values on the stack */
  printf("%-14s", when);
  for (i = 1; i <= top; i++)
    printf(" [%d]=%s", i, luaL_typename(L, i));
  printf("\n");
}

int main(void)
{
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  dump(L, "empty:");

  lua_pushinteger(L, 42);                 /* [1] */
  lua_pushstring(L, "stash");             /* [2] */
  lua_pushboolean(L, 1);                  /* [3] */
  lua_pushnil(L);                         /* [4] */
  dump(L, "after pushes:");
  printf("[1] as number: %g, [-3] as string: %s\n",
         lua_tonumber(L, 1), lua_tostring(L, -3));
  lua_settop(L, 0);                       /* drop everything */

  /* Define a Lua function, then call it from C. */
  if (luaL_dostring(L, "function greet(name, n) "
                       "  return ('hi ' .. name):rep(n, ', '), n * 2 end"))
    return 1;
  lua_getglobal(L, "greet");              /* push the function */
  lua_pushstring(L, "lua");               /* first argument */
  lua_pushinteger(L, 2);                  /* second argument */
  dump(L, "before call:");
  if (lua_pcall(L, 2, 2, 0) != 0) {       /* 2 arguments, 2 results */
    printf("error: %s\n", lua_tostring(L, -1));
    return 1;
  }
  dump(L, "after call:");
  printf("results: %s | %d\n", lua_tostring(L, -2), (int)lua_tointeger(L, -1));
  lua_pop(L, 2);

  /* Read fields of a table returned by Lua code. */
  if (luaL_dostring(L, "return { title = 'LuaJIT', tags = { 'jit', 'ffi' } }"))
    return 1;
  lua_getfield(L, -1, "title");           /* push t.title */
  printf("title: %s\n", lua_tostring(L, -1));
  lua_pop(L, 1);
  lua_getfield(L, -1, "tags");            /* push t.tags */
  printf("#tags: %d, ", (int)lua_objlen(L, -1));
  lua_rawgeti(L, -1, 2);                  /* push t.tags[2] */
  printf("tags[2]: %s\n", lua_tostring(L, -1));
  lua_pop(L, 3);                          /* tags[2], tags, t */
  dump(L, "at the end:");

  lua_close(L);
  return 0;
}
```

```console
$ cc -Wall -o stack examples/ch20/stack.c $(pkg-config --cflags --libs luajit)
$ ./stack
empty:        
after pushes:  [1]=number [2]=string [3]=boolean [4]=nil
[1] as number: 42, [-3] as string: stash
before call:   [1]=function [2]=string [3]=number
after call:    [1]=string [2]=number
results: hi lua, hi lua | 4
title: LuaJIT
#tags: 2, tags[2]: ffi
at the end:   
```

The rules that matter:

- **Calling a function:** push the function, then its arguments, then `lua_pcall(L, nargs,
  nresults, 0)`. The function and arguments are popped; `nresults` results are pushed.
- **`lua_push*`** pushes a C value. **`lua_to*`** reads one without popping it.
- **`lua_getfield(L, i, "k")`** pushes `t.k` for the table at position `i`, metamethods
  included. `lua_rawgeti(L, i, n)` pushes `t[n]` without metamethods.
- **`lua_objlen`** is `#` in Lua 5.1 and LuaJIT. Lua 5.2 renamed it `lua_rawlen`.
- **Balance the stack.** Every push needs a pop somewhere; a function that leaks one slot per
  call fills the stack in a loop. Print `lua_gettop` when debugging.
- **Strings from `lua_tostring`** point into Lua's memory and stay valid only while the value is
  on the stack. Copy them to keep them.

> **Gotcha: `luaL_dostring` results.** `luaL_dostring` is a macro: `luaL_loadstring(L, s) ||
> lua_pcall(...)`. Ignoring its result makes gcc warn `value computed is not used`. Check it.

## Calling C from Lua

A **C function** for Lua has one signature: `int f(lua_State *L)`. It reads its arguments from
the stack, pushes its results, and returns how many it pushed. All of Lua's standard library is
written this way, and so were C modules before the FFI.

A C function can also own memory through **userdata**: raw memory allocated and collected by
Lua. With a metatable it becomes an object with methods and a `__gc`.

`examples/ch20/cfunc.c`

```c
/* Lua calling C: plain C functions, and a userdata type with methods
   and a __gc finalizer. */
#include <stdio.h>
#include <stdlib.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/* divmod(a, b) -> quotient, remainder.  Errors when b is 0. */
static int l_divmod(lua_State *L)
{
  lua_Integer a = luaL_checkinteger(L, 1);  /* raises a Lua error if not */
  lua_Integer b = luaL_checkinteger(L, 2);
  if (b == 0)
    return luaL_error(L, "division by zero");
  lua_pushinteger(L, a / b);
  lua_pushinteger(L, a % b);
  return 2;                                 /* number of results */
}

/* A counter object, allocated by Lua as a userdata block. */
typedef struct { int count; } Counter;

static int counter_new(lua_State *L)
{
  Counter *c = (Counter *)lua_newuserdata(L, sizeof(Counter));
  c->count = (int)luaL_optinteger(L, 1, 0);
  luaL_getmetatable(L, "demo.Counter");
  lua_setmetatable(L, -2);                  /* give it the methods */
  return 1;
}

static int counter_bump(lua_State *L)
{
  Counter *c = (Counter *)luaL_checkudata(L, 1, "demo.Counter");
  c->count++;
  lua_pushinteger(L, c->count);
  return 1;
}

static int counter_gc(lua_State *L)
{
  Counter *c = (Counter *)luaL_checkudata(L, 1, "demo.Counter");
  printf("__gc: counter at %d\n", c->count);
  return 0;
}

static const luaL_Reg counter_methods[] = {
  { "bump", counter_bump },
  { "__gc", counter_gc },
  { NULL, NULL }
};

static const luaL_Reg demo_functions[] = {
  { "divmod", l_divmod },
  { "counter", counter_new },
  { NULL, NULL }
};

static const char *script =
  "print(demo.divmod(17, 5))\n"
  "print(pcall(demo.divmod, 1, 0))\n"
  "print(pcall(demo.divmod, 'x', 1))\n"
  "local c = demo.counter(10)\n"
  "print(type(c), c:bump(), c:bump())\n"
  "print(pcall(c.bump, {}))\n";

int main(void)
{
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);

  luaL_newmetatable(L, "demo.Counter");     /* registry["demo.Counter"] */
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");           /* mt.__index = mt */
  luaL_register(L, NULL, counter_methods);  /* put methods into mt */
  lua_pop(L, 1);

  luaL_register(L, "demo", demo_functions); /* global table `demo` */
  lua_pop(L, 1);

  if (luaL_dostring(L, script) != 0)
    printf("error: %s\n", lua_tostring(L, -1));
  printf("closing\n");
  lua_close(L);                             /* the counter is collected */
  return 0;
}
```

```console
$ cc -Wall -o cfunc examples/ch20/cfunc.c $(pkg-config --cflags --libs luajit)
$ ./cfunc
3	2
false	division by zero
false	bad argument #1 to '?' (number expected, got string)
userdata	11	12
false	bad argument #1 to '?' (demo.Counter expected, got table)
closing
__gc: counter at 12
```

- **`luaL_check*`** checks an argument and raises a Lua error with a standard message if it is
  wrong. `luaL_opt*` gives a default for a missing one.
- **`luaL_error`** raises a Lua error from C. It never returns; the `return` keeps the compiler
  quiet. The error jumps straight out of your C function, so free C resources (open files,
  `malloc`ed memory) before raising one.
- **`'?'` in the message** is the function's name. Lua finds names by looking at the calling
  code; through `pcall` there is none.
- **`luaL_newmetatable(L, "demo.Counter")`** creates a metatable and stores it in the
  **registry**, a table only C code can reach. `luaL_checkudata` compares an argument's
  metatable with it, so passing `{}` as `self` fails cleanly instead of crashing.
- **`luaL_register(L, "demo", fns)`** creates the global table `demo` and fills it; with `NULL`
  it fills the table on top of the stack. Lua 5.2 replaced it with `luaL_newlib` and
  `luaL_setfuncs`; LuaJIT has both.
- **`__gc` ran at `lua_close`.** The `luajit` program also closes its state at exit, but a
  script ending with `os.exit(code)`, like the `stash` launcher, skips that unless it passes
  `true` as a second argument.

### Userdata vs cdata

LuaJIT has two ways to hold C data in Lua, solving the same problem from opposite ends:

| | userdata (C API) | cdata (FFI) |
|--|------------------|-------------|
| Written in | C, compiled into the host | Lua, with `ffi.cdef` |
| Fields | only through C functions you write | direct: `p.count` |
| Type check | `luaL_checkudata` | the FFI type system |
| Cleanup | `__gc` in the metatable | `ffi.gc(p, f)` or a `ffi.metatype` with `__gc` |
| JIT | each call is a call into C the JIT can't see through | compiled inline |
| Portable to PUC Lua | yes | no |

`stash` uses the FFI everywhere and the C API only in the host: the usual LuaJIT style, C API to
*start* Lua, FFI to *reach* C. A library that must also run on PUC Lua 5.4 still needs the C API
([Appendix C](appendix-c-lua-versions.md)).

## Bytecode

`luajit` compiles source to **bytecode** before running it; `luajit -b` saves that bytecode to a
file. A small module and a script that uses it:

`examples/ch20/greet.lua`

```lua
-- A tiny module used by the bytecode and preload demos.
local M = {}

function M.hello(name)
  return "hello, " .. name
end

function M.fail()
  error("greet failed", 2)    -- level 2: blame the caller
end

function M.crash()
  local t = nil
  return t.x                  -- line 14: a runtime error
end

return M
```

`examples/ch20/use_greet.lua`

```lua
-- Loads greet from whatever the path finds first (greet.lua or a .luac
-- placed via package.path) and shows how errors are reported.
local greet = require("greet")
print(greet.hello("bytecode"))
print(pcall(greet.crash))
```

Copy both files to the current directory (the course folder). `luajit -b` strips debug
information by default; `-g` keeps it:

```console
$ cp examples/ch20/greet.lua examples/ch20/use_greet.lua .
$ luajit use_greet.lua
hello, bytecode
false	./greet.lua:14: attempt to index local 't' (a nil value)
$ luajit -b greet.lua greet_s.luac
$ luajit -b -g greet.lua greet_g.luac
$ ls -l greet.lua greet_s.luac greet_g.luac | awk '{print $5, $NF}'
315 greet.lua
234 greet_g.luac
171 greet_s.luac
$ head -c 4 greet_s.luac | od -An -c
 033   L   J 002
```

A bytecode file starts with `ESC L J` and a version byte. `loadfile`, `require` and `luajit`
detect it and load it like source. Replace the source with each bytecode file:

```console
$ mv greet.lua greet.src
$ cp greet_s.luac greet.lua
$ luajit use_greet.lua
hello, bytecode
false	./greet.lua:0: attempt to index a nil value
$ cp greet_g.luac greet.lua
$ luajit use_greet.lua
hello, bytecode
false	greet.lua:14: attempt to index local 't' (a nil value)
```

- **Stripped** bytecode has no line numbers (`:0`) and no local names (`a nil value`). It is
  smaller and loads faster.
- **`-g`** keeps both. The message shows the file name saved at compile time (`greet.lua`), not
  the path it was loaded from (`./greet.lua`).

`luajit -bl` lists the bytecode instead of saving it:

```console
$ luajit -bl greet.src | head -18
-- BYTECODE -- greet.src:4-6
0001    KSTR     1   0      ; "hello, "
0002    MOV      2   0
0003    CAT      1   1   2
0004    RET1     1   2

-- BYTECODE -- greet.src:8-10
0001    GGET     0   0      ; "error"
0002    KSTR     2   1      ; "greet failed"
0003    KSHORT   3   2
0004    CALL     0   1   3
0005    RET0     0   1

-- BYTECODE -- greet.src:12-15
0001    KPRI     0   0
0002    TGETS    1   0   0  ; "x"
0003    RET1     1   2

```

Each line is one VM instruction: `GGET` reads a global, `TGETS` reads a table field with a
constant string key, `CAT` joins strings.

Why ship bytecode?

- **No parsing at startup.** Loading bytecode skips the lexer and parser.
- **One file.** Bytecode can become C data linked into a program, as you'll see next.
- **Not secrecy.** Bytecode is easy to list, as you just saw, and tools exist that turn it back
  into Lua. It hides nothing.

The rules for bytecode files:

- **LuaJIT only.** PUC Lua can't load it, and LuaJIT can't load PUC Lua's.
- **Portable across CPUs**, but only within a LuaJIT major.minor version (2.1.x), and 64-bit
  (GC64) builds use a different format from 32-bit ones (`-W`/`-X` choose). Rebuild it when you
  change LuaJIT versions.
- **Untrusted bytecode is unsafe.** A crafted bytecode file can crash the VM or worse. That's
  why `stash` loads plugins with mode `"t"` (text only) in Chapter 19:

```console
$ luajit -e 'print(loadfile("greet_s.luac", "t"))'
nil	attempt to load chunk with wrong mode
```

### Bytecode as C data

`-t` sets the output type, normally picked from the file extension; `-n` sets the module name.
With `-t h` the bytecode becomes a C header:

```console
$ luajit -b greet.src greet.h
$ head -5 greet.h
#define luaJIT_BC_greet_SIZE 171
static const unsigned char luaJIT_BC_greet[] = {
27,76,74,2,10,31,0,1,3,0,1,0,4,39,1,0,0,18,2,0,0,38,1,2,1,76,1,2,0,12,104,101,
108,108,111,44,32,46,0,0,4,0,2,0,5,54,0,0,0,39,2,1,0,41,3,2,0,66,0,3,1,75,0,1,
0,17,103,114,101,101,116,32,102,97,105,108,101,100,10,101,114,114,111,114,21,
```

The array is the bytes of the `.luac` file: 27 is `ESC`, 76 `L`, 74 `J`. C code can pass it to
`luaL_loadbuffer` like any chunk. The output types:

| Type | Gives you |
|------|-----------|
| `raw` (the default) | a bytecode file |
| `h` | a header with a `static const` array and a `_SIZE` define |
| `c` | a C file with an exported array |
| `o` / `obj` | an object file with an exported symbol, ready to link |

## Embedding modules: `require` without files

A program with its modules inside still uses `require`. Two ways make that work.

### Way 1: the built-in `luaJIT_BC_` lookup

Compile a module into an object file. Its symbol is `luaJIT_BC_` plus the module name, with dots
turned into `_`:

```console
$ luajit -b -n greet examples/ch20/greet.lua greet.o
$ nm greet.o
0000000000000000 R luaJIT_BC_greet
```

When `require` finds nothing in `package.preload`, LuaJIT's preload searcher asks the dynamic
linker for a symbol `luaJIT_BC_<name>` and loads the bytes it points to. This host links
`greet.o` in and turns off every search path:

`examples/ch20/preload.c`

```c
/* A host whose Lua module is linked in as bytecode.  Build greet.o with
   `luajit -b -n greet greet.lua greet.o` and link with -Wl,-E: require
   then finds the exported symbol luaJIT_BC_greet without any file. */
#include <stdio.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

int main(void)
{
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  if (luaL_dostring(L, "package.path, package.cpath = '', ''  " /* no files */
                       "local greet = require('greet')  "
                       "print(greet.hello('linked-in bytecode'))") != 0)
    printf("error: %s\n", lua_tostring(L, -1));
  lua_close(L);
  return 0;
}
```

```console
$ cc -o preload examples/ch20/preload.c greet.o $(pkg-config --cflags --libs luajit)
$ ./preload
error: [string "package.path, package.cpath = '', ''  local g..."]:1: module 'greet' not found:
	no field package.preload['greet']
$ cc -o preload -Wl,-E examples/ch20/preload.c greet.o $(pkg-config --cflags --libs luajit)
$ ./preload
hello, linked-in bytecode
```

The first build fails even though the bytes are in the program. The next section explains the
`-Wl,-E` that fixes it.

### Way 2: a custom searcher

`require` tries the functions in `package.loaders` in order (Lua 5.2 renamed it
`package.searchers`). Each gets the module name and returns a loader function, or a string
saying why not; `require` joins those strings into its "not found" message. You can add your
own searcher, in C or Lua:

- It doesn't depend on exported symbols, so it works the same everywhere.
- You pick the order. `stash` puts its searcher second, so embedded modules win over files.
- It is more code: a table of modules and a loop.

`stash` uses a custom searcher. A third way, filling `package.preload` from C at startup, is
Exercise 2.

## What `ffi.C` can see: `-Wl,-E`

`ffi.C` is not a library. It is the **default symbol namespace**: the program itself plus the
libraries it was linked with (libc, libm...), searched with `dlsym`. Here's a host that defines
a C function and calls it from Lua:

`examples/ch20/exports.c`

```c
/* A C function in the host program, called from Lua through ffi.C.
   ffi.C can only see it if the program exports its symbols (-Wl,-E). */
#include <stdio.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

int host_answer(int x) { return x * 2; }

int main(void)
{
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  if (luaL_dostring(L, "local ffi = require('ffi')  "
                       "ffi.cdef('int host_answer(int x);')  "
                       "print('host_answer(21) =', ffi.C.host_answer(21))") != 0)
    printf("error: %s\n", lua_tostring(L, -1));
  lua_close(L);
  return 0;
}
```

This time, link LuaJIT **statically** by naming the `.a` file instead of `-lluajit-5.1`.
LuaJIT's own code needs `-lm -ldl`:

```console
$ cc -o exports $(pkg-config --cflags luajit) examples/ch20/exports.c \
    -L$(pkg-config --variable=libdir luajit) -l:libluajit-5.1.a -lm -ldl
$ ./exports
error: [string "local ffi = require('ffi')  ffi.cdef('int hos..."]:1: ./exports: undefined symbol: host_answer
$ cc -o exports -Wl,-E $(pkg-config --cflags luajit) examples/ch20/exports.c \
    -L$(pkg-config --variable=libdir luajit) -l:libluajit-5.1.a -lm -ldl
$ ./exports
host_answer(21) =	42
$ nm -D exports | grep -E 'host_answer|lua_pcall'
0000000000008769 T host_answer
000000000000c9c0 T lua_pcall
```

(Addresses differ on your machine.)

A program's functions are normally private. Only shared libraries publish theirs, in a
**dynamic symbol table** that `dlsym` searches. `-Wl,-E` (short for `--export-dynamic`) passes
`-E` to the linker, which then puts *all* the program's global symbols in that table; `nm -D`
lists it. Now `ffi.C` finds `host_answer`, the `luaJIT_BC_greet` array from the last section,
and LuaJIT's own `lua_*` functions. Those matter too: a C module loaded with `require` calls
`lua_*` functions and expects the program to have them.

`-l:libluajit-5.1.a` is GNU ld syntax for "this exact file name". With plain `-lluajit-5.1` the
linker prefers the `.so`.

## Static vs dynamic linking

The `exports` program you just built has LuaJIT inside. Compare it with a dynamic build:

```console
$ cc -o exports_dyn -Wl,-E examples/ch20/exports.c $(pkg-config --cflags --libs luajit)
$ ls -l exports exports_dyn | awk '{print $5, $NF}'
661880 exports
16224 exports_dyn
$ ldd exports | awk '{print $1}'
linux-vdso.so.1
libm.so.6
libgcc_s.so.1
libc.so.6
/lib64/ld-linux-x86-64.so.2
$ ldd exports_dyn | grep luajit
	libluajit-5.1.so.2 => not found
```

(Sizes vary by compiler and LuaJIT build.)

- **Static** copies the library's code into the program: bigger, but it runs anywhere with a
  compatible libc. `ldd` (which lists the shared libraries a program needs) shows no LuaJIT.
- **Dynamic** records only the library's **soname**, `libluajit-5.1.so.2`, as a `NEEDED` entry,
  and the dynamic loader finds the file at run time. You met sonames in
  [Chapter 15](15-wrapping-sqlite.md).

### When the loader can't find a library

Here LuaJIT is installed under a prefix outside the loader's search path. `ldd` said
`not found`, and `exports_dyn` can't start:

```console
$ ./exports_dyn
./exports_dyn: error while loading shared libraries: libluajit-5.1.so.2: cannot open shared object file: No such file or directory
$ echo $?
127
$ readelf -d exports_dyn | grep NEEDED
 0x0000000000000001 (NEEDED)             Shared library: [libluajit-5.1.so.2]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]
```

If yours runs, LuaJIT is in a standard place like `/usr/local/lib`. The fixes, worst to best:

- **`LD_LIBRARY_PATH=dir`** on each run. Fine for a test, bad for users.
- **An rpath:** `-Wl,-rpath,DIR` writes `DIR` into the program as `RUNPATH`, and the loader
  looks there first. Good for programs installed to a fixed place.
- **Link statically**, as `stash` will. Nothing to find.

```console
$ cc -o exports_dyn -Wl,-E -Wl,-rpath,$(pkg-config --variable=libdir luajit) \
    examples/ch20/exports.c $(pkg-config --cflags --libs luajit)
$ readelf -d exports_dyn | grep RUNPATH
 0x000000000000001d (RUNPATH)            Library runpath: [/opt/luajit/lib]
$ ./exports_dyn
host_answer(21) =	42
```

(`RUNPATH` shows your LuaJIT library directory; here LuaJIT lives in `/opt/luajit`.)

### Linked-in vs `ffi.load`

The same choice applies to the C libraries your Lua code uses:

| | Linked into the program, found with `ffi.C` | Loaded at run time with `ffi.load` |
|--|----|----|
| Needs `-Wl,-E` | yes | no |
| Needs the library installed | no | yes |
| Shows in `ldd` | no (static) | no: `ldd` only sees `NEEDED` |
| Can be missing and handled | no | yes: `pcall(ffi.load, ...)` |
| Upgrades with the system | no: rebuild to get security fixes | yes |

`stash` links SQLite and zlib, which it can't work without. It keeps `ffi.load` for libcurl: a
large library with many dependencies and frequent security fixes, which the system should
update.

When you're done, clean up (`rm embed stack cfunc preload exports exports_dyn greet*
use_greet.lua`).

## Building stash: one program

`stash` becomes one file, `build/stash`:

- `host/main.c`: a C host that does what the `stash` launcher script does.
- Every module in `src/` compiled to bytecode with `-g`, as a C header, found by a custom
  searcher.
- LuaJIT, SQLite and zlib linked in statically and exported with `-Wl,-E`.
- `ffi/load.lua` looks in `ffi.C` before calling `ffi.load`.
- A `Makefile` builds it all; `make test` runs the tests against both `./stash` and
  `build/stash`.

You need the static libraries `libsqlite3.a` and `libz.a`. On Debian and Ubuntu they come with
the development packages `libsqlite3-dev` and `zlib1g-dev`. The `./stash` launcher keeps
working. Start from your `project/ch19` code: five files change and three are new.

### `src/stash/ffi/load.lua`: try `ffi.C` first

Inside `build/stash`, SQLite and zlib are already part of the program; loading
`libsqlite3.so.0` would add a second copy. So `load` takes one more argument, `symbol`: the name
of any function in the library. If `ffi.C` has it, the library is linked in:

```lua
-- Loads a shared C library, trying several names in turn.
--
-- ffi.load("sqlite3") looks for libsqlite3.so (Linux) or libsqlite3.dylib
-- (macOS). On Linux that unversioned name often comes only with the
-- development package, so we also try the versioned name ("soname")
-- that every installed copy has: libsqlite3.so.0.
--
-- First, though, we look in ffi.C: the single-file stash program
-- (Chapter 20) has SQLite and zlib linked in, and exports their
-- functions, so there is nothing to load. `symbol` is any function the
-- library has; finding it in ffi.C means the library is there.

local ffi = require("ffi")

return function(names, symbol)
  if pcall(function() return ffi.C[symbol] end) then
    return ffi.C
  end
  local problems = {}
  for _, name in ipairs(names) do
    local ok, lib = pcall(ffi.load, name)
    if ok then
      return lib
    end
    problems[#problems + 1] = lib
  end
  error("cannot load C library: " .. table.concat(problems, "; "), 2)
end
```

`ffi.C[symbol]` raises an error when the symbol is missing, hence the `pcall`. The `symbol` must
already be declared with `ffi.cdef`, and it is: each binding declares its functions before
calling `load`.

Under `luajit`, `ffi.C` is the `luajit` program, which has no SQLite, so the old path runs.

### `src/stash/ffi/sqlite.lua`, `zlib.lua`, `curl.lua`: name a symbol

Change the last line of each binding:

```lua
return load({ "sqlite3", "libsqlite3.so.0" }, "sqlite3_libversion")
```

```lua
return load({ "z", "libz.so.1" }, "zlibVersion")
```

```lua
return load({ "curl", "libcurl.so.4" }, "curl_version")
```

`build/stash` doesn't link libcurl, so in `curl.lua` the probe fails and `ffi.load` runs. But
you could link it in later without touching the Lua code.

### `host/main.c`: the host (new)

The host does exactly what the launcher script does: set up `require`, set `arg`, require
`stash.strict` and run `stash.main`. The one new part is `embedded_searcher`.

```c
/*
 * stash as one program: a small C host that starts LuaJIT, makes stash's
 * Lua modules (compiled to bytecode and linked in) available to require,
 * and runs stash.main -- just like the `stash` launcher script does.
 */
#include <stdio.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/* One embedded module: its name for require, and its bytecode. */
struct module {
  const char *name;
  const unsigned char *code;
  size_t size;
};

/* Generated by the Makefile: `static const struct module modules[]`,
   ending with a { NULL } entry. */
#include "modules.h"

/*
 * A searcher for package.loaders. require("stash.db") calls it with
 * "stash.db"; it returns the module's loader (the compiled chunk), or a
 * string saying why not -- require collects those for its error message.
 */
static int embedded_searcher(lua_State *L)
{
  const char *name = luaL_checkstring(L, 1);
  const struct module *m;
  for (m = modules; m->name != NULL; m++) {
    if (strcmp(m->name, name) == 0) {
      if (luaL_loadbuffer(L, (const char *)m->code, m->size, m->name) != 0)
        return lua_error(L);               /* the message is on the stack */
      return 1;
    }
  }
  lua_pushfstring(L, "\n\tno embedded module '%s'", name);
  return 1;
}

/* Inserts the searcher at package.loaders[2], right after the one for
   package.preload: embedded modules win over files on package.path. */
static void add_searcher(lua_State *L)
{
  int i;
  lua_getglobal(L, "package");             /* package */
  lua_getfield(L, -1, "loaders");          /* package, loaders */
  for (i = (int)lua_objlen(L, -1); i >= 2; i--) {
    lua_rawgeti(L, -1, i);                 /* move loaders[i]... */
    lua_rawseti(L, -2, i + 1);             /* ...to loaders[i + 1] */
  }
  lua_pushcfunction(L, embedded_searcher);
  lua_rawseti(L, -2, 2);
  lua_pop(L, 2);                           /* (empty) */
}

/* Message handler for lua_pcall: adds a traceback to the error. */
static int traceback(lua_State *L)
{
  const char *message = lua_tostring(L, 1);
  luaL_traceback(L, L, message ? message : "(error object is not a string)", 1);
  return 1;
}

int main(int argc, char **argv)
{
  lua_State *L = luaL_newstate();
  int i, status, code;
  if (L == NULL) {
    fputs("stash: cannot create a Lua state\n", stderr);
    return 2;
  }
  luaL_openlibs(L);
  add_searcher(L);

  /* The global `arg`, as luajit sets it: arg[0] is the program. */
  lua_createtable(L, argc, 0);
  for (i = 0; i < argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i);
  }
  lua_setglobal(L, "arg");

  /* require("stash.strict"); return require("stash.main").run(arg) */
  lua_pushcfunction(L, traceback);         /* traceback */
  lua_getglobal(L, "require");
  lua_pushstring(L, "stash.strict");
  status = lua_pcall(L, 1, 0, 1);          /* traceback */
  if (status == 0) {
    lua_getglobal(L, "require");
    lua_pushstring(L, "stash.main");
    status = lua_pcall(L, 1, 1, 1);        /* traceback, main */
  }
  if (status == 0) {
    lua_getfield(L, -1, "run");            /* traceback, main, run */
    lua_getglobal(L, "arg");               /* traceback, main, run, arg */
    status = lua_pcall(L, 1, 1, 1);        /* traceback, main, exit code */
  }
  if (status != 0) {                       /* stash.main reports its own errors;
                                              this is for everything else */
    fprintf(stderr, "stash: %s\n", lua_tostring(L, -1));
    code = 2;
  } else {
    code = (int)lua_tointeger(L, -1);
  }
  lua_close(L);                            /* runs __gc: closes the database */
  return code;
}
```

What each part does:

- **`embedded_searcher`** compiles the matching module with `luaL_loadbuffer` and returns the
  chunk; `require` calls it with the module name, as for a file. Broken bytecode raises an
  error instead of being skipped.
- **`add_searcher`** shifts `loaders[2..n]` up by one, from the end down so nothing is
  overwritten, and puts the searcher at 2. `loaders[1]` is still `package.preload`.
- **The comments on the right** show the stack after each line. Writing them is the easiest way
  to keep a C API function balanced.
- **`lua_pcall(L, 1, 0, 1)`**: the last argument is the stack position of a **message handler**.
  Lua calls it before the stack unwinds, so `luaL_traceback` can still see where the error
  happened: `xpcall` from [Chapter 9](09-errors.md), in C.
- **The exit code** comes back from `run` as a number. `lua_close` runs before `return`, so the
  database's `__gc` closes it properly. The launcher's `os.exit` skips that and leaves cleanup to
  the operating system.

### `host/modules.lua`: generate the module table (new)

`main.c` includes `modules.h`, a header listing every module, written by a Lua script. The
Makefile passes the module paths as arguments:

```lua
-- Writes modules.h for host/main.c: includes the bytecode headers that
-- `luajit -b -t h` made, and lists them in a table.
--
--   luajit host/modules.lua stash/main stash/db ... > build/modules.h

print("/* Generated by host/modules.lua. Do not edit. */")
for _, path in ipairs(arg) do
  print(('#include "%s.h"'):format(path))
end
print("")
print("static const struct module modules[] = {")
for _, path in ipairs(arg) do
  local name = path:gsub("/", ".")                    -- stash/ffi/sqlite -> stash.ffi.sqlite
  local symbol = "luaJIT_BC_" .. name:gsub("%.", "_")  -- what -n name gives the array
  print(('  { "%s", %s, %s_SIZE },'):format(name, symbol, symbol))
end
print("  { NULL, NULL, 0 }")
print("};")
```

Try it with two modules:

```console
$ luajit host/modules.lua stash/cli stash/ffi/zlib
/* Generated by host/modules.lua. Do not edit. */
#include "stash/cli.h"
#include "stash/ffi/zlib.h"

static const struct module modules[] = {
  { "stash.cli", luaJIT_BC_stash_cli, luaJIT_BC_stash_cli_SIZE },
  { "stash.ffi.zlib", luaJIT_BC_stash_ffi_zlib, luaJIT_BC_stash_ffi_zlib_SIZE },
  { NULL, NULL, 0 }
};
```

> **Gotcha: `gsub` returns two values.** `path:gsub("/", ".")` returns the new string *and* the
> number of replacements; `local name = ...` keeps only the first. Passing `path:gsub(...)`
> straight into `format` would pass the count too (harmless here, as an extra argument).

Each module gets its own header, made with `-t h`. `-g` keeps line numbers for error messages,
and `-n` names the array:

```console
$ luajit -b -g -t h -n stash.clock src/stash/clock.lua - | head -3
#define luaJIT_BC_stash_clock_SIZE 371
static const unsigned char luaJIT_BC_stash_clock[] = {
27,76,74,2,8,20,64,115,114,99,47,115,116,97,115,104,47,99,108,111,99,107,46,
```

`-` means standard output. Bytes 64, 115, 114, 99... spell `@src/stash/clock.lua`, the chunk
name saved by `-g`, so errors in `build/stash` point at the source file.

### `Makefile`: build it all (new)

```make
# Builds stash as a single program: build/stash.
#
#   make          build it
#   make test     run the tests with luajit, then the end-to-end tests
#                 against build/stash
#   make clean    remove build/
#
# LuaJIT is linked in statically, and so are SQLite and zlib; libcurl is
# loaded at run time with ffi.load, like before.

LUAJIT ?= luajit
# The LuaJIT installation that `luajit` on the PATH comes from.
LUAJIT_PREFIX ?= $(abspath $(dir $(shell command -v $(LUAJIT)))..)

CC ?= cc
CFLAGS ?= -O2 -Wall
CPPFLAGS += -I$(LUAJIT_PREFIX)/include/luajit-2.1 -Ibuild -Ibuild/bc
# -E (--export-dynamic): put the program's own functions in its dynamic
# symbol table, so dlsym -- and so ffi.C -- can find them.
# --whole-archive: link all of libsqlite3.a and libz.a, not just the parts
# main.c calls (none!): the Lua code calls them through the FFI.
LDFLAGS += -Wl,-E
LDLIBS += $(LUAJIT_PREFIX)/lib/libluajit-5.1.a \
          -Wl,--whole-archive -l:libsqlite3.a -l:libz.a -Wl,--no-whole-archive \
          -lm -ldl -lpthread

# src/stash/ffi/sqlite.lua -> stash/ffi/sqlite
MODULES := $(patsubst src/%.lua,%,$(sort $(shell find src -name '*.lua')))
HEADERS := $(MODULES:%=build/bc/%.h)

build/stash: host/main.c build/modules.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ host/main.c $(LDLIBS)

# Each module as bytecode in a C header; -g keeps the line numbers for
# error messages, -n sets the module name.
build/bc/%.h: src/%.lua
	@mkdir -p $(dir $@)
	$(LUAJIT) -b -g -t h -n $(subst /,.,$*) $< $@

build/modules.h: $(HEADERS) host/modules.lua
	$(LUAJIT) host/modules.lua $(MODULES) > $@

test: build/stash
	$(LUAJIT) test/run.lua
	STASH_BIN=build/stash $(LUAJIT) test/run.lua e2e

clean:
	rm -rf build

.PHONY: test clean
```

Recipe lines must start with a **tab**, not spaces; otherwise make says `missing separator`.

How the pieces fit:

- **Rules:** `target: prerequisites`, then the commands that make the target. Make rebuilds a
  target when a prerequisite is newer: change `src/stash/db.lua` and only `build/bc/stash/db.h`,
  `modules.h` and the program are rebuilt.
- **`build/bc/%.h: src/%.lua`** is a pattern rule. `$*` is the part `%` matched
  (`stash/ffi/sqlite`), `$<` the first prerequisite, `$@` the target.
- **`MODULES`** finds every `.lua` file under `src/`, sorts the list (so the build is the same
  everywhere) and strips `src/` and `.lua`.
- **`LUAJIT_PREFIX`** comes from where `luajit` is: `/usr/local/bin/luajit` gives `/usr/local`.
  Override it with `make LUAJIT_PREFIX=...` if your headers live elsewhere.
- **`?=` and `+=`** allow overrides: `make CFLAGS=-O0` replaces `CFLAGS`. A variable given on
  the command line wins even over `+=` in the file.

Two details are easy to get wrong:

- **Headers go in `build/bc/`, not `build/`.** `build/stash` is the program, so a header for
  `stash/cli` at `build/stash/cli.h` would need a *directory* `build/stash`.
- **`--whole-archive`.** The linker normally copies only the parts of a `.a` file that already
  linked code calls. `main.c` calls nothing in SQLite or zlib; only the Lua code does, at run
  time, through `ffi.C`. Without `--whole-archive` they'd be left out. `-l:libz.a` names the
  static library so the linker doesn't pick `libz.so`.

### `test/e2e_test.lua`: test either program

The end-to-end tests ran `./stash`. Now they run `$STASH_BIN` if it is set:

```lua
-- End-to-end tests: run the real program in a shell and check its output
-- and exit code. The program is ./stash, or $STASH_BIN: `make test` runs
-- these tests against the single-file build/stash too.

local BIN = os.getenv("STASH_BIN") or "./stash"
local HOME = tmpdir("e2e")
local PAGES = "file://" .. os.getenv("PWD") .. "/test/fixtures"

-- Runs `stash ARGS` (with extra environment variables `env`, like
-- "COLUMNS=100") and returns its output (stdout and stderr) and exit code.
-- io.popen's close() does not report the exit code in LuaJIT, so the
-- shell prints it after the output.
local function stash(args, env)
  local command = ("%s STASH_HOME=%s STASH_NOW=1767225600 %s %s 2>&1; echo \"[exit $?]\"")
                  :format(env or "", HOME, BIN, args)
  local pipe = assert(io.popen(command))
  local output = pipe:read("*a")
  pipe:close()
  local text, code = output:match("^(.-)%[exit (%d+)%]\n$")
  return text, tonumber(code)
end
```

The unit tests still `require` the modules from `src/` with `luajit`; the end-to-end tests prove
the program works.

Add `build/` to your `.gitignore` if you use git.

### Checkpoint

Build, check what's inside, and run the tests:

```console
$ make
luajit -b -g -t h -n stash.buffer src/stash/buffer.lua build/bc/stash/buffer.h
luajit -b -g -t h -n stash.cli src/stash/cli.lua build/bc/stash/cli.h
luajit -b -g -t h -n stash.clock src/stash/clock.lua build/bc/stash/clock.h
luajit -b -g -t h -n stash.commands src/stash/commands.lua build/bc/stash/commands.h
luajit -b -g -t h -n stash.compress src/stash/compress.lua build/bc/stash/compress.h
luajit -b -g -t h -n stash.config src/stash/config.lua build/bc/stash/config.h
luajit -b -g -t h -n stash.db src/stash/db.lua build/bc/stash/db.h
luajit -b -g -t h -n stash.entry src/stash/entry.lua build/bc/stash/entry.h
luajit -b -g -t h -n stash.errors src/stash/errors.lua build/bc/stash/errors.h
luajit -b -g -t h -n stash.fetch src/stash/fetch.lua build/bc/stash/fetch.h
luajit -b -g -t h -n stash.ffi.curl src/stash/ffi/curl.lua build/bc/stash/ffi/curl.h
luajit -b -g -t h -n stash.ffi.libc src/stash/ffi/libc.lua build/bc/stash/ffi/libc.h
luajit -b -g -t h -n stash.ffi.load src/stash/ffi/load.lua build/bc/stash/ffi/load.h
luajit -b -g -t h -n stash.ffi.sqlite src/stash/ffi/sqlite.lua build/bc/stash/ffi/sqlite.h
luajit -b -g -t h -n stash.ffi.zlib src/stash/ffi/zlib.lua build/bc/stash/ffi/zlib.h
luajit -b -g -t h -n stash.fs src/stash/fs.lua build/bc/stash/fs.h
luajit -b -g -t h -n stash.html src/stash/html.lua build/bc/stash/html.h
luajit -b -g -t h -n stash.iter src/stash/iter.lua build/bc/stash/iter.h
luajit -b -g -t h -n stash.json src/stash/json.lua build/bc/stash/json.h
luajit -b -g -t h -n stash.main src/stash/main.lua build/bc/stash/main.h
luajit -b -g -t h -n stash.plugins src/stash/plugins.lua build/bc/stash/plugins.h
luajit -b -g -t h -n stash.store src/stash/store.lua build/bc/stash/store.h
luajit -b -g -t h -n stash.strict src/stash/strict.lua build/bc/stash/strict.h
luajit -b -g -t h -n stash.term src/stash/term.lua build/bc/stash/term.h
luajit -b -g -t h -n stash.util src/stash/util.lua build/bc/stash/util.h
luajit host/modules.lua stash/buffer stash/cli stash/clock stash/commands stash/compress stash/config stash/db stash/entry stash/errors stash/fetch stash/ffi/curl stash/ffi/libc stash/ffi/load stash/ffi/sqlite stash/ffi/zlib stash/fs stash/html stash/iter stash/json stash/main stash/plugins stash/store stash/strict stash/term stash/util > build/modules.h
cc -I/usr/local/include/luajit-2.1 -Ibuild -Ibuild/bc -O2 -Wall -Wl,-E -o build/stash host/main.c /usr/local/lib/libluajit-5.1.a -Wl,--whole-archive -l:libsqlite3.a -l:libz.a -Wl,--no-whole-archive -lm -ldl -lpthread
$ ls -l build/stash | awk '{print $5, $9}'
2317856 build/stash
$ ldd build/stash | awk '{print $1}'
linux-vdso.so.1
libm.so.6
libgcc_s.so.1
libc.so.6
/lib64/ld-linux-x86-64.so.2
$ nm -D build/stash | grep -E ' T (luaL_newstate|sqlite3_open_v2|compress2)$' | awk '{print $2, $3}'
T compress2
T luaL_newstate
T sqlite3_open_v2
$ make test
luajit test/run.lua
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
plugins_test     6 tests, 0 failed
e2e_test         6 tests, 0 failed

86 passed, 0 failed
STASH_BIN=build/stash luajit test/run.lua e2e
e2e_test         6 tests, 0 failed

6 passed, 0 failed
```

Machine-specific parts:

- The `cc` line shows your LuaJIT prefix (here `/usr/local`).
- The size depends on your compiler and the SQLite and zlib versions.
- The `ldd` list depends on your system. What matters is what's *not* there: `libluajit`,
  `libsqlite3`, `libz`.

`nm -D` proves the exports: SQLite, zlib and LuaJIT functions are all in the program's dynamic
symbol table, where `ffi.C` finds them.

Now copy the program somewhere with no `src/` folder and use it:

```console
$ export STASH_HOME=$PWD/demo STASH_NOW=1767225600
$ mkdir -p demo/elsewhere && cp build/stash demo/elsewhere/ && cd demo/elsewhere
$ ./stash add file://$OLDPWD/test/fixtures/luajit.html -t jit
added #1 LuaJIT: a Just-In-Time Compiler & FFI
$ ./stash list
  1  LuaJIT: a Just-In-Time Compiler &...  jit               2026-01-01
$ ./stash nosuchcommand
stash: unknown command 'nosuchcommand' (try 'stash help')
$ echo $?
2
$ cd $OLDPWD
```

`STASH_HOME` is an absolute path this time because you change directory. `$OLDPWD` is the
directory you came from.

Which shared libraries does the program load while it runs? `LD_DEBUG=libs` makes the loader
report each one:

```console
$ LD_DEBUG=libs build/stash stats 2>&1 | grep -oE 'calling init: \S*(sqlite|libz|curl)\S*'
calling init: /lib/x86_64-linux-gnu/libz.so.1
calling init: /lib/x86_64-linux-gnu/libzstd.so.1
calling init: /lib/x86_64-linux-gnu/libcurl.so
```

- **No `libsqlite3`.** SQLite came from `ffi.C`.
- **`libcurl`** is loaded by `ffi.load`, as planned. The name depends on your system.
- **`libz.so.1` is there**, but not for `stash`: libcurl needs zlib, so the loader brings it in.
  libcurl's zlib calls still go to the copy inside `stash`, because the loader looks in the
  program first and `-Wl,-E` made the program's zlib visible. Two copies in one process are
  harmless here, but worth knowing about.

Finally, build without `-Wl,-E` (a variable set on the command line replaces the file's `+=`)
and watch the fallback work:

```console
$ make clean
rm -rf build
$ make LDFLAGS= 2>&1 | tail -1
cc -I/usr/local/include/luajit-2.1 -Ibuild -Ibuild/bc -O2 -Wall  -o build/stash host/main.c /usr/local/lib/libluajit-5.1.a -Wl,--whole-archive -l:libsqlite3.a -l:libz.a -Wl,--no-whole-archive -lm -ldl -lpthread
$ nm -D build/stash | grep -c ' T sqlite3_'
0
$ LD_DEBUG=libs build/stash stats 2>&1 | grep -oE 'calling init: \S*(sqlite|libz|curl)\S*'
calling init: /lib/x86_64-linux-gnu/libz.so.1
calling init: /lib/x86_64-linux-gnu/libzstd.so.1
calling init: /lib/x86_64-linux-gnu/libcurl.so
calling init: /lib/x86_64-linux-gnu/libsqlite3.so
$ make clean
rm -rf build
$ rm -r demo
```

SQLite is in the program but not exported, so `ffi.C` can't see it and `load` falls back to
`ffi.load`. It works, but carries over a megabyte of dead code and needs SQLite installed.
That's why the build uses `-Wl,-E`.

(`grep -c` exits with status 1 when it counts 0 matches; in a script with `set -e`, that would
stop the script.)

The complete project at this point is in `project/ch20/`.

## Summary

- A **host** creates a state with `luaL_newstate`, opens libraries with `luaL_openlibs`,
  compiles with `luaL_loadbuffer`, runs with `lua_pcall`, and ends with `lua_close`.
- C and Lua exchange values through the **stack**: push arguments, call, read results, pop.
  Keep it balanced.
- A **C function** is `int f(lua_State *L)`: it reads arguments, pushes results, returns how
  many. **Userdata** hands C memory to Lua's GC. In LuaJIT, use the C API to start Lua and the
  FFI to reach C.
- **`luajit -b`** saves bytecode: `-g` keeps line numbers, `-t h` makes a C header, `-n` names
  the module. Bytecode is LuaJIT-only, version-bound, and never safe to load from strangers.
- `require` finds embedded modules through **`luaJIT_BC_<name>`** symbols or a **custom
  searcher** in `package.loaders`.
- **`-Wl,-E`** exports a program's symbols so `dlsym`, and so `ffi.C`, can find them.
  `--whole-archive` keeps library code that only Lua calls.
- **Static** linking needs no installed library; **dynamic** linking needs the soname to be
  found (system path, rpath or `LD_LIBRARY_PATH`). `ldd`, `nm -D`, `readelf -d` and
  `LD_DEBUG=libs` show what a program needs and loads.
- `build/stash` is one file with LuaJIT, SQLite, zlib and all of `stash` inside.

## Exercises

1. Give the `Counter` type in `examples/ch20/cfunc.c` a `__tostring` metamethod, so that
   `print(c)` prints `Counter(12)`.

<details><summary>Solution</summary>

Add a C function to `counter_methods`. `lua_pushfstring` is a small `sprintf` that pushes the
result; it knows `%d`, `%s` and a few other formats:

```c
static int counter_tostring(lua_State *L)
{
  Counter *c = (Counter *)luaL_checkudata(L, 1, "demo.Counter");
  lua_pushfstring(L, "Counter(%d)", c->count);
  return 1;
}

static const luaL_Reg counter_methods[] = {
  { "__tostring", counter_tostring },
  { "bump", counter_bump },
  { "__gc", counter_gc },
  { NULL, NULL }
};
```

Add `"print(c, tostring(c) == 'Counter(12)')\n"` to the end of `script`; the output gains a line
before `closing`:

```text
Counter(12)	true
```

`luaL_register` puts every entry into the metatable. `__tostring` and `__gc` are found there as
metamethods; `bump` through `__index`, which points at the same table.

</details>

2. Replace the custom searcher in `host/main.c` with `package.preload`: at startup, compile
   every embedded module and store the chunk in `package.preload[name]`. What does this cost
   compared to the searcher?

<details><summary>Solution</summary>

Replace `embedded_searcher` and `add_searcher` with:

```c
/* Puts every embedded module's compiled chunk into package.preload,
   where require looks first. */
static void add_preloads(lua_State *L)
{
  const struct module *m;
  lua_getglobal(L, "package");
  lua_getfield(L, -1, "preload");          /* package, preload */
  for (m = modules; m->name != NULL; m++) {
    if (luaL_loadbuffer(L, (const char *)m->code, m->size, m->name) != 0) {
      fprintf(stderr, "stash: %s\n", lua_tostring(L, -1));
      lua_pop(L, 1);
      continue;
    }
    lua_setfield(L, -2, m->name);          /* preload[name] = chunk */
  }
  lua_pop(L, 2);
}
```

and call `add_preloads(L)` in `main` instead of `add_searcher(L)`. `make test` still passes,
and the program still runs from a folder with no `src/`.

The cost: every module is compiled at startup, even ones a command never requires (`stash list`
never needs `stash.clock` or `stash.iter`). Loading bytecode is fast, so for 25 small modules
you won't notice. The searcher compiles each module only when it is first required, and its
`require` error says `no embedded module 'x'`, which helps when debugging.

</details>

3. Add a `make install` target that copies `build/stash` to `$(PREFIX)/bin`, with `PREFIX`
   defaulting to `/usr/local`. Support `DESTDIR`, which packaging tools use to install into a
   staging folder.

<details><summary>Solution</summary>

Add to the Makefile, before `clean` (recipe lines start with a tab):

```make
PREFIX ?= /usr/local

install: build/stash
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 build/stash $(DESTDIR)$(PREFIX)/bin/stash
```

and add `install` to `.PHONY`. Try it without touching the system:

```console
$ make install DESTDIR=$PWD/pkg | tail -1
install -m 755 build/stash /home/you/stash/pkg/usr/local/bin/stash
$ pkg/usr/local/bin/stash version
stash 0.1.0
$ rm -r pkg
```

(The path shows your own directory.) `install -d` creates the directory; `install -m 755`
copies and sets the permissions in one step. `DESTDIR` goes *before* `PREFIX` and is empty by
default, so a normal `sudo make install` writes to `/usr/local/bin`.

</details>

4. `ldd build/stash` doesn't list libcurl, yet `stash add` downloads pages with it. Why? How can
   you see that libcurl is used?

<details><summary>Solution</summary>

`ldd` lists the program's `NEEDED` entries: libraries the linker recorded at build time, which
the loader opens before `main` runs. libcurl isn't one. `stash.ffi.curl` calls `ffi.load`, which
calls `dlopen` while the program runs. The linker never saw it.

To see it, watch the program run:

- `LD_DEBUG=libs build/stash stats` reports every library the loader opens, including
  `dlopen`ed ones, as in the checkpoint.
- While it runs, `/proc/<pid>/maps` lists every mapped file.

That's also why a missing libcurl gives `stash`'s own error, `cannot load C library: ...`, raised
by Lua code when `stash.fetch` is first required. A missing `NEEDED` library gives the loader's
error instead, before `main` even starts.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-20--embedding-luajit)
