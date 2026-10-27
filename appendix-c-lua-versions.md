# Appendix C — Lua Versions

This course uses LuaJIT: Lua 5.1 plus extensions. PUC Lua, the reference implementation from
lua.org, has moved on to 5.2, 5.3, 5.4 and 5.5. This appendix lists what changed, what LuaJIT
took from the newer versions, and how to move LuaJIT code to Lua 5.4 or 5.5.

The official binary is `lua`; here `lua5.4` and `lua5.5` tell the versions apart. In the code,
`expr --> result` means `print(expr)` prints `result` (tabs shown as two spaces), and the first
comment says which versions the block runs on.

## The versions

| Version | Released | Main changes |
|---------|----------|--------------|
| Lua 5.1 | Feb 2006 | `require` and modules, incremental GC, `#` and `%`. The base of LuaJIT |
| Lua 5.2 | Dec 2011 | `_ENV` replaces `setfenv`, `goto`, `bit32`, `__gc` for tables, yield across `pcall` |
| Lua 5.3 | Jan 2015 | integers, bitwise operators, `//`, `utf8`, `string.pack` |
| Lua 5.4 | Jun 2020 | `<const>`, `<close>`, generational GC, `warn`, `coroutine.close` |
| Lua 5.5 | Dec 2025 | `global` declarations, named vararg tables, read-only `for` variables, more compact arrays, incremental major GC |
| LuaJIT 2.1 | rolling releases | Lua 5.1 + JIT + FFI + the extensions below |

Lua 5.4 gets no further releases. Lua 5.5 is the current version.

## What LuaJIT took from later versions

LuaJIT keeps the Lua 5.1 C API and ABI, so C modules for 5.1 work with it, which rules out
changes like `_ENV`. It took the features that don't break existing code:

- **From 5.2:** `goto` and labels; `\x` and `\z` escapes; `load(chunk, name, mode, env)` and
  `loadfile(path, mode, env)`; `math.log(x, base)`; `string.rep(s, n, sep)`; the `%g` pattern
  class; extra arguments to `xpcall`; `io.read("*L")`; `os.exit(true)`;
  `package.searchpath`; yielding across `pcall` and metamethods.
- **From 5.3:** `\u{...}` escapes; `table.move`; `coroutine.isyieldable`; read formats without `*`
  (`f:read("l")`); `assert` with any error value.
- **Its own:** the `ffi`, `bit` and `jit` libraries, `string.buffer`, `table.new`, `table.clear`,
  and 64-bit integer cdata (`1LL`).

Other 5.2 features (`table.pack`, `rawlen`, `__pairs`, `__len` for tables...) exist only in
LuaJIT builds compiled with `-DLUAJIT_ENABLE_LUA52COMPAT`; don't count on them.

### Newer syntax in recent LuaJIT builds

LuaJIT 2.1 builds from July 2026 on (version 2.1.1784535649 or later) also accept some syntax
backported from LuaJIT 3.0:

- bitwise operators `&`, `|`, `~`, `<<`, `>>`, `~>>` (32-bit, like the `bit` library; 64-bit on
  `LL` cdata);
- `!=`, `!`, `&&`, `||`;
- `a ? b : c`, `a ?? b`, `a?.b`;
- `+=`, `-=`, `..=` and the other compound assignments;
- `continue`, `const`, short function expressions, `1_000_000`.

There is still no `//`. Code using this syntax runs only on those builds. PUC Lua 5.3+ has the
bitwise operators (but not `~>>`) and none of the rest. This course uses none of it.

## Feature table

"Old" means deprecated: default builds of that version may still have it (through compatibility
options), but the manual says not to rely on it.

| Feature | LuaJIT 2.1 | 5.2 | 5.3 | 5.4 | 5.5 |
|---------|-----------|-----|-----|-----|-----|
| `goto` | yes | yes | yes | yes | yes |
| `\u{...}` escapes, `table.move` | yes | no | yes | yes | yes |
| `setfenv`, `getfenv` | yes | no | no | no | no |
| `_ENV` | no | yes | yes | yes | yes |
| `unpack`, `loadstring`, `module`, `table.maxn` | yes | old | no | no | no |
| `table.unpack`, `table.pack`, `rawlen` | no | yes | yes | yes | yes |
| `package.loaders` / `package.searchers` | loaders | searchers | searchers | searchers | searchers |
| `__gc`, `__len`, `__pairs` on tables | no | yes | yes | yes | yes |
| `bit` library | yes | no | no | no | no |
| `bit32` library | no | yes | old | no | no |
| bitwise operators | recent builds | no | yes | yes | yes |
| `//`, integer subtype, `math.type` | no | no | yes | yes | yes |
| `utf8`, `string.pack` | no | no | yes | yes | yes |
| `math.pow`, `math.atan2` | yes | yes | old | old | no |
| `<const>`, `<close>`, `coroutine.close`, `warn` | no | no | no | yes | yes |
| `global` declarations, `table.create` | no | no | no | no | yes |
| FFI, JIT compiler | yes | no | no | no | no |

## Numbers: integers and floats (5.3+)

Lua 5.1 and LuaJIT have one number type, a double. Since 5.3 a number is either a 64-bit
integer or a float, and Lua tracks which. Same expressions, three versions:

| Expression | LuaJIT | Lua 5.4 | Lua 5.5 |
|------------|--------|---------|---------|
| `7 / 2` | `3.5` | `3.5` | `3.5` |
| `6 / 2` | `3` | `3.0` | `3.0` |
| `3 == 3.0` | `true` | `true` | `true` |
| `"1" + "2"` | `3` | `3` | `3` |
| `9007199254740993` | `9.007199254741e+15` | `9007199254740993` | `9007199254740993` |
| `2^53` | `9.007199254741e+15` | `9.007199254741e+15` | `9007199254740992.0` |
| `0.1 + 0.2` | `0.3` | `0.3` | `0.30000000000000004` |
| `("%d"):format(3.5)` | `3` | error: `number has no integer representation` | same error |
| `7 // 2` | syntax error | `3` | `3` |
| `1 << 32` | `1` (recent builds) | `4294967296` | `4294967296` |
| `math.maxinteger` | `nil` | `9223372036854775807` | `9223372036854775807` |

- `/` and `^` always give a float. `//` is floor division: integer for integers, float otherwise.
- A float prints with `.0` (`3.0`), so output can change when you port. Use `string.format` when
  the exact text matters.
- Lua 5.5 prints floats with enough digits to read them back exactly.
- Integers wrap around on overflow; floats don't.

```lua
-- Lua 5.4 and 5.5
7 // 2, 7.0 // 2, -7 // 2                 --> 3  3.0  -4
math.type(3), math.type(3.0), math.type("3")   --> integer  float  nil
math.tointeger(3.0), math.tointeger(3.5)  --> 3  nil
math.maxinteger + 1 == math.mininteger    --> true
1.0 // 0, (pcall(function() return 1 // 0 end))   --> inf  false
```

Integer division by zero is an error (`attempt to divide by zero`); float division gives `inf`.

## Bitwise operations

LuaJIT's `bit` library works on **32-bit** numbers. The 5.3+ operators work on **64-bit**
integers. Results differ when a value needs more than 32 bits:

| LuaJIT | Lua 5.3+ | LuaJIT result | 5.3+ result |
|--------|----------|---------------|-------------|
| `bit.band(5, 3)` | `5 & 3` | `1` | `1` |
| `bit.bor(5, 3)`, `bit.bxor(5, 3)` | `5 \| 3`, `5 ~ 3` | `7`, `6` | `7`, `6` |
| `bit.bnot(0)` | `~0` | `-1` | `-1` |
| `bit.lshift(1, 4)`, `bit.rshift(256, 4)` | `1 << 4`, `256 >> 4` | `16`, `16` | `16`, `16` |
| `bit.lshift(1, 32)` | `1 << 32` | `1` | `4294967296` |
| `bit.band(0xffffffff, 0xffffffff)` | `0xffffffff & 0xffffffff` | `-1` | `4294967295` |

Code that must run on both can't contain the operators, since an older LuaJIT won't even
compile the file. Compile them from a string instead:

```lua
-- LuaJIT, Lua 5.3, 5.4 and 5.5
local band
if bit then
  band = bit.band
else
  band = load("return function(a, b) return a & b end")()
end
band(0xff, 0x0f)                          --> 15
```

## Environments: `setfenv` and `_ENV`

In 5.1 every function has an environment table for its globals, which `setfenv(f, env)`
changes ([Chapter 19](19-plugins-and-scripting.md)). Lua 5.2 removed that: a global name `x` now
means `_ENV.x`, where `_ENV` is an ordinary local variable or upvalue.

To run a chunk with its own globals, use the 5.2 form of `load`. LuaJIT supports it too, so it
works everywhere:

```lua
-- LuaJIT, Lua 5.2, 5.3, 5.4 and 5.5
local env = { print = print }
local f = assert(load("x = 1", "=chunk", "t", env))
f()
env.x, x                                  --> 1  nil
```

In 5.2+, code can also pick its globals table with a local `_ENV`:

```lua
-- Lua 5.2, 5.3, 5.4 and 5.5
local function sandboxed()
  local _ENV = { print = print }
  y = 2                                   -- sets _ENV.y
  return y
end
sandboxed(), y                            --> 2  nil
```

There is no direct replacement for `setfenv` on an existing function. Load the code with the
right `env` from the start.

## Strings and UTF-8

Lua 5.3 added a small `utf8` library. Strings are still bytes: `#` counts bytes in every version.

```lua
-- Lua 5.3, 5.4 and 5.5
local s = "héllo"
#s, utf8.len(s)                           --> 6  5
utf8.char(233, 8364), utf8.codepoint("é") --> é€  233
```

Without `utf8`, a pattern can match one UTF-8 character: a lead byte, then continuation bytes.

```lua
-- LuaJIT, Lua 5.2, 5.3, 5.4 and 5.5
local chars = {}
for ch in ("hé!"):gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
table.concat(chars, "|")                  --> h|é|!
select(2, ("héllo"):gsub("[^\128-\191]", ""))   --> 5
```

`%z` matches a zero byte. 5.2+ prefers a literal `\0` in patterns, but LuaJIT rejects that
(`malformed pattern`), and `%z` still works everywhere. For binary data, 5.3+ has `string.pack`
and `string.unpack`; in LuaJIT, use the FFI ([Chapter 17](17-binary-data-and-zlib.md)).

## Constants and to-be-closed variables (5.4+)

`<const>` makes a local read-only. `<close>` calls the value's `__close` metamethod when the
variable goes out of scope: at the end of the block, on `break` or `return`, or on an error.
Files have `__close`, so this closes a file in every case:

```lua
-- Lua 5.4 and 5.5
local path <const> = "close-demo.txt"
do
  local f <close> = assert(io.open(path, "w"))
  f:write("hello\n")
end                                       -- f:close() runs here
io.open(path):read("l")                   --> hello
os.remove(path)

local log = {}
local function resource(name)
  return setmetatable({}, { __close = function() log[#log + 1] = "closed " .. name end })
end
do
  local a <close> = resource("a")
  local b <close> = resource("b")
end
table.concat(log, ", ")                   --> closed b, closed a
```

Assigning to a `<const>` local is a compile error: `attempt to assign to const variable 'path'`.
In LuaJIT, `<const>` is a syntax error. Close resources with explicit calls and `pcall`, or use
`ffi.gc` as a safety net.

## Lua 5.5: `global` declarations and more

A `global` declaration lists the globals a chunk may use. After it, any other free name is a
compile error, which catches typos before the program runs:

```lua
global print, string
global count = 0                          -- declare and initialize

count = count + 1
print(count)
total = 1                                 -- not declared
```

```console
$ lua5.5 glob.lua
lua5.5: glob.lua:6: variable 'total' not declared
```

Nothing ran: the error comes from the compiler. `global<const> *` makes every global read-only
instead (`math = nil` then fails with `attempt to assign to const variable 'math'`).

Other 5.5 changes:

```lua
-- Lua 5.5
local function count(...args)            -- named vararg table: args.n is the count
  return args.n, args[1]
end
count("a", nil, "c")                      --> 3  a
```

- The `for` loop variable is read-only: `for i = 1, 3 do i = i * 2 end` fails with
  `attempt to assign to const variable 'i'`. Write `local i = i * 2` instead.
- `global` is a reserved word. Default builds still let old code use it as a name.
- `<=` no longer falls back to `__lt`: define `__le` too. (5.4 still did it in default builds.)
- `table.create(n)` makes a pre-sized table, like LuaJIT's `table.new`.

## Moving LuaJIT code to Lua 5.4 or 5.5

Most stash modules that don't touch C load unchanged in Lua 5.4 ([Chapter 21](21-design-and-next-steps.md)
shows which). The checklist:

1. **`unpack`:** write `local unpack = table.unpack or unpack` at the top of the file.
2. **`setfenv` sandboxes:** use `load(code, name, "t", env)`, which works in both.
3. **`loadstring(s)`:** use `load(s)`.
4. **`module(...)`:** return a table from the file (the style this course uses).
5. **`bit.*`:** use the operators, and check values that need more than 32 bits.
6. **`math.pow(x, y)`, `math.atan2(y, x)`, `math.log10(x)`:** use `x ^ y`, `math.atan(y, x)`,
   `math.log(x, 10)`.
7. **Number output:** `3.0` now prints as `3.0`, and `%d` rejects `3.5`. Format numbers
   explicitly, and use `//` or `math.floor` where you need integers.
8. **The FFI:** PUC Lua has none. Write a C module with the C API ([Chapter 20](20-embedding-luajit.md)),
   or use an existing binding from LuaRocks.
9. **LuaJIT-only modules** (`jit`, `string.buffer`, `table.new`): load them with `pcall(require, ...)`
   and fall back to plain Lua.
10. **Random numbers:** LuaJIT gives the same sequence on every run unless you call
    `math.randomseed`; 5.4+ seeds randomly. Seed explicitly in tests.
11. **Names:** `goto` is a keyword in 5.2+, so `t.goto` must become `t["goto"]`. LuaJIT
    accepts both.
12. **Test on both:** run the test suite with `luajit` and with `lua5.4`.

To write one file for several versions, test for features, not versions:
`if setfenv then ... end`, `math.type and math.type(x)`, `jit and jit.version`
([Chapter 21](21-design-and-next-steps.md) has an example).

Sources for this appendix: [REFERENCES.md](REFERENCES.md#appendix-c--lua-versions)
