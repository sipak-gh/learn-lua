# Chapter 17 — Binary Data and zlib

Not all data is text. Compressed pages, checksums and file headers are raw bytes with a layout fixed
down to the bit. This chapter covers bytes, bits, byte order, zlib and SQLite BLOBs, and `stash`
starts saving every downloaded page, compressed, for `show --body`. It builds on
[Chapter 15](15-wrapping-sqlite.md) and [Chapter 16](16-callbacks-and-curl.md);
[Chapter 18](18-performance-and-the-jit.md) then makes the code fast.

## Bytes in Lua

A Lua string is a sequence of bytes, not characters. It may hold any byte, zero included, and `#`
counts bytes. So strings suit binary data, except that they can't be changed. For bytes you want to
modify, use a C array: `ffi.new("uint8_t[?]", n)`.

`examples/ch17/bytes.lua`

```lua
-- Two ways to hold bytes: Lua strings (immutable) and uint8_t arrays (mutable).
local ffi = require("ffi")

local s = "A\0B\255"                       -- a string may hold any byte, even zero
print(#s, s:byte(1, -1))                   -- # counts bytes; byte() gives their values
print(string.char(72, 105))                -- and back

local buf = ffi.new("uint8_t[?]", 8)       -- 8 zero bytes, mutable
ffi.copy(buf, s, #s)                       -- copy the string's 4 bytes in
buf[4] = 0x43                              -- 'C'
ffi.fill(buf + 5, 3, 0x2e)                 -- three '.' after it
print(buf[1], buf[3], buf[4])

print(#ffi.string(buf))                    -- without a length: stops at the first zero
print(#ffi.string(buf, 8))                 -- with a length: all 8 bytes
-- Show unprintable bytes as \ddd escapes.
print((ffi.string(buf, 8):gsub("[^%g ]", function(c) return "\\" .. c:byte() end)))
```

```console
$ luajit examples/ch17/bytes.lua
4	65	0	66	255
Hi
0	255	67
1
8
A\0B\255C...
```

- `s:byte(i, j)` returns the bytes as numbers; `string.char(...)` builds a string from numbers.
- `ffi.copy(dst, src, n)` copies `n` bytes; a Lua string converts to a pointer to its bytes.
- `ffi.fill(dst, n, byte)` sets `n` bytes. `buf + 5` is pointer arithmetic: the address 5 bytes in.
- `ffi.string(ptr)` stops at the first zero byte (it treats memory as a C string);
  `ffi.string(ptr, n)` copies exactly `n` bytes. For binary data, always pass the length.

## The `bit` library

Binary formats pack numbers into bits and bytes. LuaJIT has the `bit` library for that:

`examples/ch17/bitops.lua`

```lua
-- LuaJIT's bit library: 32-bit integer operations on Lua numbers.
local bit = require("bit")
local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift

print(band(0xF0, 0x3C), bor(0xF0, 0x0F), bxor(0xFF, 0x0F))
print(lshift(1, 4), rshift(256, 4))

-- Results are signed 32-bit numbers:
print(lshift(1, 31), bit.tobit(0xFFFFFFFF), rshift(-1, 28), bit.arshift(-256, 4))

-- tohex shows the 32 bits; tobit wraps any number into that range.
print(bit.tohex(-1), bit.tohex(255), bit.tohex(255, 2), bit.tohex(255, -4))
print(bit.tobit(2^32 + 5))

-- Flags: one bit each.
local READ, WRITE, EXEC = 1, 2, 4
local mode = bor(READ, EXEC)
print(band(mode, WRITE) ~= 0, band(mode, EXEC) ~= 0)

-- On 64-bit cdata, the same functions work on all 64 bits.
print(bit.tohex(bit.band(0xFFFF00000000LL, 0xF0F000000000LL)), bit.lshift(1LL, 40))
```

```console
$ luajit examples/ch17/bitops.lua
48	255	240
16	16
-2147483648	-1	15	-16
ffffffff	000000ff	ff	00FF
5
false	true
0000f0f000000000	1099511627776LL
```

| Function | Does |
|----------|------|
| `band(a, b, ...)`, `bor`, `bxor` | bitwise AND, OR, XOR |
| `bnot(a)` | flips every bit |
| `lshift(a, n)`, `rshift(a, n)` | shift left or right, filling with zeros |
| `arshift(a, n)` | shift right, copying the sign bit |
| `rol(a, n)`, `ror(a, n)` | rotate |
| `bswap(a)` | reverse the 4 bytes |
| `tobit(a)` | wrap a number into the signed 32-bit range |
| `tohex(a [, n])` | hex digits; `n` digits, negative `n` for upper case |

The catch is the result range. Lua numbers are doubles, but `bit` works on **32-bit signed**
integers: `lshift(1, 31)` is `-2147483648`, and `0xFFFFFFFF` comes back as `-1`. The bits are right;
only the Lua number reading them is signed. Compare results with other `bit` results or `tobit(x)`,
never with a plain large number. `tohex` is the easy way to look at them.

Given 64-bit cdata (`1LL`, `0x...ULL`, an `int64_t` from C), the same functions work on all 64 bits
and return cdata.

`bit` is LuaJIT's. Lua 5.3+ has operators instead (`&`, `|`, `<<`); Lua 5.1 has neither. LuaJIT 2.1
builds from July 2026 on also accept those operators, but older builds don't, so this course uses `bit`.

## Byte order

A 32-bit number takes 4 bytes. Which comes first in memory depends on the CPU: x86 and most ARM
systems are **little-endian** (least significant byte first); some others are big-endian.

`examples/ch17/endian.lua`

```lua
-- The same 4 bytes read as one 32-bit number: byte order matters.
local ffi = require("ffi")
local bit = require("bit")

print("little-endian CPU:", ffi.abi("le"))

local n = ffi.new("uint32_t[1]", 0x01020304)
local bytes = ffi.cast("uint8_t *", n)       -- look at the same memory byte by byte
print(bytes[0], bytes[1], bytes[2], bytes[3])

-- A file format must pick one order. Big-endian ("network order") puts
-- the most significant byte first. Building the bytes by hand gives the
-- same result on every CPU:
local function u32_be(x)
  return string.char(bit.band(bit.rshift(x, 24), 0xff), bit.band(bit.rshift(x, 16), 0xff),
                     bit.band(bit.rshift(x, 8), 0xff), bit.band(x, 0xff))
end
print(u32_be(0x01020304):byte(1, -1))

-- Copying memory gives the CPU's order, which is why it's not portable:
print(ffi.string(n, 4):byte(1, -1))

-- bit.bswap reverses the bytes of a 32-bit number.
print(bit.tohex(bit.bswap(0x01020304)))

-- Reading back: shift each byte into place.
local function read_u32_be(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(c, 8), d)
end
print(bit.tohex(read_u32_be("\1\2\3\4", 1)), read_u32_be("\255\255\255\254", 1))
```

```console
$ luajit examples/ch17/endian.lua
little-endian CPU:	true
4	3	2	1
1	2	3	4
4	3	2	1
04030201
01020304	-2
```

Output from a little-endian machine:

- `ffi.cast("uint8_t *", n)` views the number's memory byte by byte: `4 3 2 1`.
- A file or network format must name one order. Shifts and masks give the same bytes on every CPU;
  copying memory (`ffi.string(n, 4)`) gives the CPU's order.
- `ffi.abi("le")` tells you the CPU's order; `ffi.abi("be")` is its opposite.
- Reading four bytes back with `bor` and `lshift` gives a signed result: `\255\255\255\254` reads as
  `-2`. For the unsigned value, add `2^32` to negative results. Lengths under 2 GiB never hit this.

## zlib: compress and uncompress

zlib is the compression library behind gzip and PNG, installed nearly everywhere (soname
`libz.so.1`). For data that fits in memory, two calls do the job:

| Function | Does |
|----------|------|
| `compressBound(n)` | the most bytes compressing `n` bytes can produce |
| `compress2(dest, &destLen, src, srcLen, level)` | compresses; level 0 (none) to 9 (best) |
| `uncompress(dest, &destLen, src, srcLen)` | the reverse |

`examples/ch17/zlib.lua`

```lua
-- Compress and uncompress a string with zlib's one-call functions.
local ffi = require("ffi")

ffi.cdef [[
typedef unsigned long uLong;
const char *zlibVersion(void);
uLong compressBound(uLong sourceLen);
int compress2(uint8_t *dest, uLong *destLen, const uint8_t *source, uLong sourceLen, int level);
int uncompress(uint8_t *dest, uLong *destLen, const uint8_t *source, uLong sourceLen);
]]
local z = ffi.load("z")

local function compress(data, level)
  local bound = z.compressBound(#data)        -- the worst case for this length
  local out = ffi.new("uint8_t[?]", bound)
  local out_len = ffi.new("uLong[1]", bound)  -- in: room in out; out: bytes written
  assert(z.compress2(out, out_len, data, #data, level) == 0)
  return ffi.string(out, out_len[0])
end

-- zlib doesn't record the original size; the caller must know it.
local function uncompress(blob, size)
  local out = ffi.new("uint8_t[?]", size)
  local out_len = ffi.new("uLong[1]", size)
  local rc = z.uncompress(out, out_len, blob, #blob)
  if rc ~= 0 then
    return nil, rc
  end
  return ffi.string(out, out_len[0])
end

print("zlib " .. ffi.string(z.zlibVersion()))
local text = assert(io.open(arg[0])):read("*a")  -- this file's own source
for _, level in ipairs({ 0, 1, 6, 9 }) do
  print(("level %d: %d -> %d bytes"):format(level, #text, #compress(text, level)))
end
local same = ("na"):rep(1000)
print(("repeats: %d -> %d bytes"):format(#same, #compress(same, 9)))
print(z.compressBound(#text))

local blob = compress(text, 9)
print(uncompress(blob, #text) == text)
print(uncompress(blob, 100))                 -- too little room
print(uncompress(blob:sub(1, 20), #text))    -- cut short
print(uncompress("not zlib data", #text))    -- not zlib at all
```

```console
$ luajit examples/ch17/zlib.lua
zlib 1.2.11
level 0: 1731 -> 1742 bytes
level 1: 1731 -> 758 bytes
level 6: 1731 -> 719 bytes
level 9: 1731 -> 719 bytes
repeats: 2000 -> 24 bytes
1744ULL
true
nil	-5
nil	-3
nil	-3
```

- `destLen` is an in/out parameter: going in, the room in `dest`; coming out, the bytes written.
  `ffi.new("uLong[1]", bound)` makes it.
- `uLong` is C's `unsigned long`, 64 bits on Linux and macOS, so results arrive as `ULL` cdata.
  `ffi.string(out, out_len[0])` accepts that as the length.
- Level 0 stores without compressing: a little larger than the input. Text compresses to about 40%,
  repetitive data to almost nothing.
- **zlib doesn't store the original size.** `uncompress` needs a big enough buffer, so the caller
  must know the size, and a file format must save it.
- Errors: `-5` is `Z_BUF_ERROR` (no room in `dest`), `-3` is `Z_DATA_ERROR` (input damaged or cut
  short). They are `#define`s in `zlib.h`, so the cdef copies them into an `enum`.

## Checksums with CRC-32

A **checksum** is a short fingerprint of data: if the data changes, the fingerprint almost certainly
does too. zlib provides CRC-32, used by gzip, PNG and Ethernet.

`examples/ch17/crc32.lua`

```lua
-- CRC-32 checksums with zlib: a 32-bit fingerprint of some bytes.
local ffi = require("ffi")
local bit = require("bit")

ffi.cdef [[
unsigned long crc32(unsigned long crc, const uint8_t *buf, unsigned int len);
]]
local z = ffi.load("z")

local c = z.crc32(0, "hello", 5)
print(c, type(c))                            -- unsigned long: 64-bit cdata
print(tonumber(c), bit.tohex(tonumber(c)))

-- One changed byte changes the checksum completely.
local d = tonumber(z.crc32(0, "hellp", 5))
print(d, bit.tohex(d))
print(bit.tobit(d))                          -- the same 32 bits, in bit's signed form

-- Feed it in pieces: pass the running value back in.
local running = 0
for _, piece in ipairs({ "he", "ll", "o" }) do
  running = z.crc32(running, piece, #piece)
end
print(running == c)
```

```console
$ luajit examples/ch17/crc32.lua
907060870ULL	cdata
907060870	3610a686
3138956147	bb18ab73
-1156011149
true
```

- `crc32` returns an `unsigned long`; `tonumber` it first. The value fits in 32 bits.
- `bit.tobit` gives the same bits in `bit`'s signed form. Do this before comparing with values built
  by `bit` functions, or `3138956147` won't equal `-1156011149`.
- The first argument is the CRC so far. Start with 0 and feed pieces one at a time: the result equals
  the whole data's, so it works for streams too large for memory.

A CRC detects accidental damage (a bad disk sector, a truncated download), not deliberate changes;
that needs a cryptographic hash.

## Reading binary through a struct

C programs read binary formats by pointing a struct at the bytes. LuaJIT can too, even on a Lua
string. This example reads the header that `stash.compress` writes
(in [Building stash](#building-stash-compressed-pages) below): the data's size and CRC, 4 bytes
each, big-endian.

`examples/ch17/header.lua`

```lua
-- Reading a binary header through a C struct, and why byte order bites.
package.path = "project/ch17/src/?.lua;" .. package.path
local ffi = require("ffi")
local bit = require("bit")
local compress = require("stash.compress")

ffi.cdef [[
struct blob_header { uint32_t size; uint32_t crc; };
]]

local blob = compress.pack("hello")
print(#blob, ffi.sizeof("struct blob_header"))

-- Point a struct at the string's bytes: no copy. Valid while `blob` lives.
local h = ffi.cast("const struct blob_header *", blob)
print(h.size, bit.tohex(h.crc))                -- read in the CPU's byte order

-- The header is big-endian; on a little-endian CPU, swap.
local function be32(n)
  return ffi.abi("le") and bit.bswap(n) or n
end
print(be32(h.size), bit.tohex(be32(h.crc)))
```

```console
$ luajit examples/ch17/header.lua
21	8
83886080	86a61036
5	3610a686
```

- `ffi.cast("const struct blob_header *", blob)` reads the string's bytes in place, without copying.
  The pointer is valid only while the string is alive, so keep a reference to `blob`.
- Fields are read in the CPU's order. The header is big-endian, so on a little-endian CPU 5 reads as
  83886080 (`0x05000000`) until `bit.bswap` swaps it back.
- Struct fields are aligned as in C. Two `uint32_t` need no padding; a `uint8_t` then a `uint32_t`
  would get 3 padding bytes. Check with `ffi.sizeof` and `ffi.offsetof`.

For two fields, shifting bytes by hand is simpler and portable. Structs pay off for larger headers.

## BLOBs in SQLite

SQLite has two types for byte strings, `TEXT` and `BLOB`. A Lua string can be either, so the wrapper
must choose.

`examples/ch17/blob.lua`

```lua
-- Text or BLOB? The same Lua string, stored two ways in SQLite.
package.path = "project/ch17/src/?.lua;" .. package.path
local Db = require("stash.db")

local db = assert(Db.open(":memory:"))
db:exec("CREATE TABLE t (how TEXT, data)")
local bytes = "ab\0cd"                        -- 5 bytes, one of them zero
db:run("INSERT INTO t VALUES ('text', ?)", { bytes })
db:run("INSERT INTO t VALUES ('blob', ?)", { Db.blob(bytes) })

for row in db:rows("SELECT how, typeof(data) AS type, length(data) AS len, hex(data) AS hex FROM t") do
  print(row.how, row.type, row.len, row.hex)
end
for row in db:rows("SELECT data FROM t") do
  print(#row.data, row.data == bytes)
end
```

```console
$ luajit examples/ch17/blob.lua
text	text	2	6162006364
blob	blob	5	6162006364
5	true
5	true
```

Both rows hold the same 5 bytes, and both come back whole. The difference shows inside SQL:
`length()` counts a TEXT value's characters up to the first zero byte, but a BLOB's bytes. Text
functions like `upper()` or `LIKE` assume UTF-8, and FTS5 indexes text, not blobs. Compressed data
is binary, so it goes in as a BLOB.

`Db.blob(s)` marks a string as binary: it returns `{ blob = s }`, a table `Stmt:bind` recognizes and
binds with `sqlite3_bind_blob` (and `SQLITE_TRANSIENT`, like text). Reading uses
`sqlite3_column_blob`, `sqlite3_column_bytes` and `ffi.string(ptr, len)`, which keeps zero bytes.

## Building stash: compressed pages

`stash add` downloads each page for its title and text, then throws it away. Now it keeps the page,
compressed with zlib, in a new `pages` table:

- `show ID --body` prints the saved page; `show ID` gains a `page:` line with its size.
- `stats` counts entries, tags and pages, and shows how much compression saves.

### The blob format

zlib doesn't record the original length, and a damaged blob should be reported, not printed as
garbage. So each page is stored as an 8-byte header plus the zlib data:

```text
bytes 0-3   length of the original data   (unsigned, big-endian)
bytes 4-7   CRC-32 of the original data   (unsigned, big-endian)
bytes 8-    the zlib stream
```

Big-endian, so a database copied to another machine reads the same.

### `src/stash/ffi/zlib.lua` (new)

```lua
-- Raw bindings to zlib (from zlib.h and zconf.h).

local ffi = require("ffi")
local load = require("stash.ffi.load")

ffi.cdef [[
typedef unsigned char Bytef;
typedef unsigned long uLong;                  /* 64 bits on Linux and macOS, 32 on Windows */
typedef unsigned int uInt;

enum {
  Z_OK = 0,
  Z_DATA_ERROR = -3,
  Z_MEM_ERROR = -4,
  Z_BUF_ERROR = -5,
  Z_BEST_COMPRESSION = 9,
};

const char *zlibVersion(void);
uLong compressBound(uLong sourceLen);
int compress2(Bytef *dest, uLong *destLen, const Bytef *source, uLong sourceLen, int level);
int uncompress(Bytef *dest, uLong *destLen, const Bytef *source, uLong sourceLen);
uLong crc32(uLong crc, const Bytef *buf, uInt len);
]]

return load({ "z", "libz.so.1" })
```

The typedefs copy zlib's names, so the declarations match `zlib.h` word for word. `uLong` is 32 bits
on 64-bit Windows; the typedef is the one place to change.

### `src/stash/compress.lua` (new)

```lua
-- Compressed blobs for page bodies.
--
-- A blob is an 8-byte header followed by zlib data:
--
--   bytes 0-3   length of the original data   (unsigned, big-endian)
--   bytes 4-7   CRC-32 of the original data   (unsigned, big-endian)
--   bytes 8-    the zlib stream
--
-- zlib's uncompress needs to know how much room to make, so we store the
-- length; the checksum catches data that was damaged on the way.

local ffi = require("ffi")
local bit = require("bit")
local Z = require("stash.ffi.zlib")

local band, bor, lshift, rshift, tobit = bit.band, bit.bor, bit.lshift, bit.rshift, bit.tobit

local M = {}

local HEADER = 8

-- CRC-32 as a signed 32-bit number, the form the bit library works with.
-- crc32 returns an unsigned long, which arrives as a 64-bit cdata number.
function M.crc32(data)
  return tobit(tonumber(Z.crc32(0, data, #data)))
end

-- A 32-bit number as 4 bytes, most significant first (big-endian), so
-- the blob reads the same on every machine.
local function u32_bytes(n)
  return string.char(band(rshift(n, 24), 0xff), band(rshift(n, 16), 0xff),
                     band(rshift(n, 8), 0xff), band(n, 0xff))
end

local function u32_at(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d)   -- signed, like tobit
end

function M.pack(data)
  local bound = Z.compressBound(#data)
  local out = ffi.new("Bytef[?]", bound)                     -- a variable-length array
  local out_len = ffi.new("uLong[1]", bound)                 -- in: room, out: bytes used
  local rc = Z.compress2(out, out_len, data, #data, Z.Z_BEST_COMPRESSION)
  if rc ~= Z.Z_OK then
    error("compress2 failed with code " .. rc)
  end
  return u32_bytes(#data) .. u32_bytes(M.crc32(data)) .. ffi.string(out, out_len[0])
end

-- Returns the original data, or nil and a message for a damaged blob.
function M.unpack(blob)
  if #blob < HEADER then
    return nil, "blob too short"
  end
  local size = u32_at(blob, 1)
  local out = ffi.new("Bytef[?]", size)
  local out_len = ffi.new("uLong[1]", size)
  -- A Lua string converts to `const Bytef *` for the call; blob + 8 would
  -- not work on a string, so we pass the zlib part as its own string.
  local stream = blob:sub(HEADER + 1)
  local rc = Z.uncompress(out, out_len, stream, #stream)
  if rc ~= Z.Z_OK or out_len[0] ~= size then
    return nil, "corrupt data (zlib error " .. rc .. ")"
  end
  local data = ffi.string(out, size)
  if M.crc32(data) ~= u32_at(blob, 5) then
    return nil, ("checksum mismatch: %s, expected %s"):format(bit.tohex(M.crc32(data)),
                                                             bit.tohex(u32_at(blob, 5)))
  end
  return data
end

function M.version()
  return ffi.string(Z.zlibVersion())
end

return M
```

- `pack` writes the header with shifts and masks, then the zlib data from a `Bytef[?]` VLA sized by
  `compressBound`.
- `unpack` checks everything it can: the blob holds a header, zlib accepts the stream, the result has
  the promised size, and its CRC matches.
- `blob:sub(HEADER + 1)` copies the zlib part into a new string. In C you'd pass `blob + 8`, but a
  Lua string isn't a pointer and has no `+`. Copying a few kilobytes is cheap. (Without the copy,
  `ffi.cast("const uint8_t *", blob) + 8` works too, while `blob` stays alive.)
- The CRC is kept as a signed 32-bit number, so `crc32` and `u32_at` values compare.

### `src/stash/ffi/sqlite.lua`

Two declarations: `sqlite3_bind_blob` after `sqlite3_bind_text`,

```lua
int sqlite3_bind_blob(sqlite3_stmt *stmt, int i, const void *data, int nbytes,
                      void (*destructor)(void *));
```

and `sqlite3_column_blob` after `sqlite3_column_text`:

```lua
const void *sqlite3_column_blob(sqlite3_stmt *stmt, int i);
```

### `src/stash/db.lua`

Add `Db.blob` before `Stmt:bind`:

```lua
-- Lua strings hold text and binary data alike; SQLite tells them apart.
-- Wrap binary data as Db.blob(s) to store it as a BLOB.
function Db.blob(data)
  return { blob = data }
end
```

In `Stmt:bind`, a new case before the final `else`:

```lua
    elseif type(value) == "table" and type(value.blob) == "string" then
      rc = S.sqlite3_bind_blob(self, index, value.blob, #value.blob, TRANSIENT)
```

In `Stmt:row`, a new case after the `SQLITE_TEXT` one:

```lua
    elseif kind == S.SQLITE_BLOB then
      local data = S.sqlite3_column_blob(self, i)
      row[name] = ffi.string(data, S.sqlite3_column_bytes(self, i))    -- may hold zero bytes
```

### `src/stash/store.lua`

The header comment lists the new methods:

```lua
-- Store: bookmarks in an SQLite database, with full-text search (FTS5).
-- It has the same methods the commands used before, plus the page text:
--   add(entry, text, page) -> entry   get(id) -> entry|nil   remove(id) -> entry|nil
--   list{tag=, limit=} -> array   search(query) -> array   tags() -> array
--   entries() -> iterator over all entries in id order
--   page(id) -> html|nil   page_size(id) -> size, stored | nil   stats() -> table
```

Two new requires:

```lua
local Db = require("stash.db")
local compress = require("stash.compress")
local errors = require("stash.errors")
local Entry = require("stash.entry")
local util = require("stash.util")
```

Migration 2 goes at the end of `MIGRATIONS`. Chapter 15 and 16 databases are at version 1, so they
get the new table the next time `stash` opens them:

```lua
  -- 2: the downloaded pages, compressed (see stash.compress).
  [[
  CREATE TABLE pages (
    entry_id INTEGER PRIMARY KEY REFERENCES entries(id) ON DELETE CASCADE,
    size     INTEGER NOT NULL,                   -- before compression
    data     BLOB NOT NULL
  );
  ]],
}
```

`entry_id` is the primary key (one page per entry); `ON DELETE CASCADE` removes the page with its
entry.

`add` takes the page as a third argument:

```lua
-- text is the page as plain text, for the search index; page is the
-- page itself, kept compressed. Both are optional.
function Store:add(entry, text, page)
  local db = self.db
  db:transaction(function()
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
  end)
  return entry
end
```

And three new methods at the end, before `return Store`:

```lua
-- The saved page of an entry, uncompressed, or nil if there is none.
function Store:page(id)
  local row = self.db:first("SELECT data FROM pages WHERE entry_id = ?", { id })
  if row == nil then
    return nil
  end
  local page, err = compress.unpack(row.data)
  if page == nil then
    errors.fail("the saved page of #%d is damaged: %s", id, err)
  end
  return page
end

-- The size of the saved page and the bytes it takes in the database.
function Store:page_size(id)
  local row = self.db:first("SELECT size, length(data) AS stored FROM pages WHERE entry_id = ?",
                            { id })
  if row then
    return row.size, row.stored
  end
end

function Store:stats()
  return self.db:first([[
    SELECT (SELECT count(*) FROM entries) AS entries,
           (SELECT count(DISTINCT tag) FROM tags) AS tags,
           (SELECT count(*) FROM pages) AS pages,
           (SELECT coalesce(sum(size), 0) FROM pages) AS size,
           (SELECT coalesce(sum(length(data)), 0) FROM pages) AS stored]])
end
```

- `page` turns a damaged blob into a clear error, not garbage on screen.
- `page_size` needs no decompression: `size` is a column, and SQL's `length()` of a BLOB is its byte
  count.
- `stats` gets five numbers in one query, one subquery each. `coalesce(sum(...), 0)` turns the `NULL`
  that `sum` returns for no rows into 0.

### `src/stash/commands.lua`

`add` passes the page body to the store:

```lua
    -- Download the page for its title and the search index.
    local title, text, page
    if not opts.no_fetch then
      local body, info = fetch.get(url, { user_agent = ctx.config.user_agent,
                                          timeout = ctx.config.timeout })
      if body == nil then
        errors.fail("cannot fetch %s: %s", url, info)
      end
      -- file:// URLs have no content type; trust them to be HTML.
      if info.content_type == nil or info.content_type:find("html") then
        title, text, page = html.title(body), html.text(body), body
      end
    end
    local entry = ctx.store:add(Entry.new({ url = url, title = title, tags = tags,
                                            note = opts.note, created = util.now() }),
                                text, page)
    ctx.out("added " .. tostring(entry))
  end,
```

`show` gets `--body` and the `page:` line:

```lua
command "show" {
  usage = "show ID [--body]",
  help = "show one bookmark, or its saved page",
  options = { ["--body"] = { "body", "flag" } },
  run = function(ctx, opts)
    local id = need_id(opts)
    local entry = ctx.store:get(id) or errors.not_found("no entry with id %d", id)
    if opts.body then
      local page = ctx.store:page(id) or errors.not_found("no saved page for #%d", id)
      ctx.out((page:gsub("\n$", "")))        -- out adds the final newline
      return
    end
    ctx.out(("%-6s %d"):format("id:", entry.id))
    ctx.out(("%-6s %s"):format("title:", entry.title))
    ctx.out(("%-6s %s"):format("url:", entry.url))
    ctx.out(("%-6s %s"):format("tags:", entry:tag_string(", ")))
    ctx.out(("%-6s %s"):format("added:", util.datetime(entry.created)))
    local size, stored = ctx.store:page_size(id)
    if size then
      ctx.out(("%-6s %d bytes, %d compressed"):format("page:", size, stored))
    end
    if entry.note ~= "" then
      ctx.out(("%-6s %s"):format("note:", entry.note))
    end
  end,
}
```

`ctx.out` adds a newline, and pages usually end with one, so `--body` strips it to print the page
exactly. The extra parentheses keep only `gsub`'s first result.

A new `stats` command, after `export`:

```lua
command "stats" {
  usage = "stats",
  help = "count entries and the space pages take",
  run = function(ctx)
    local s = ctx.store:stats()
    ctx.out(("entries  %d"):format(s.entries))
    ctx.out(("tags     %d"):format(s.tags))
    ctx.out(("pages    %d"):format(s.pages))
    ctx.out(("size     %d bytes"):format(s.size))
    if s.size > 0 then
      ctx.out(("stored   %d bytes (%d%%)"):format(s.stored,
                         math.floor(s.stored / s.size * 100 + 0.5)))
    end
  end,
}
```

### Tests

`test/run.lua` runs `compress_test` after `fetch_test`:

```lua
local FILES = {
  "util_test", "cli_test", "entry_test", "iter_test", "config_test",
  "commands_test", "json_test", "html_test", "fs_test", "term_test",
  "buffer_test", "db_test", "store_test", "fetch_test", "compress_test",
  "e2e_test",
}
```

`test/compress_test.lua` (new):

```lua
local bit = require("bit")
local compress = require("stash.compress")

test("crc32 of a known string", function()
  eq(bit.tohex(compress.crc32("hello")), "3610a686")
end)

test("the header holds the length and checksum, big-endian", function()
  local blob = compress.pack("hello")
  eq(blob:sub(1, 8), "\0\0\0\5\54\16\166\134")
  eq(compress.unpack(blob), "hello")
end)

test("repetitive data shrinks and comes back intact", function()
  local data = ("<p>stash keeps bookmarks</p>\n"):rep(200)
  local blob = compress.pack(data)
  ok(#blob < #data / 20, #blob)
  eq(compress.unpack(blob), data)
  eq(compress.unpack(compress.pack("")), "")
end)

test("damage is detected", function()
  local blob = compress.pack(("abc"):rep(100))
  local bad_crc = blob:sub(1, 4) .. "\0\0\0\0" .. blob:sub(9)
  eq(select(2, compress.unpack(bad_crc)), "checksum mismatch: d0c4b884, expected 00000000")
  eq(select(2, compress.unpack(blob:sub(1, 12))), "corrupt data (zlib error -3)")
  eq(select(2, compress.unpack("x")), "blob too short")
end)
```

The second test pins the exact header bytes: length 5, then `36 10 a6 86` (as decimal escapes). If
anyone changes the byte order, this test says so.

`test/db_test.lua`: add at the end:

```lua
test("blobs keep every byte", function()
  local db = assert(Db.open(":memory:"))
  db:exec("CREATE TABLE b (data BLOB)")
  local bytes = "\0\1\2\255zero\0inside"
  db:run("INSERT INTO b VALUES (?)", { Db.blob(bytes) })
  local row = db:first("SELECT data, typeof(data) AS kind, length(data) AS n FROM b")
  eq(row.data, bytes)
  eq(row.kind, "blob")
  eq(row.n, #bytes)
end)
```

`test/store_test.lua`: add at the end:

```lua
test("pages are stored compressed and come back whole", function()
  local store = assert(Store.open(":memory:"))
  local page = ("<p>hello</p>\n"):rep(50)
  store:add(Entry.new({ url = "https://a.org/" }), "hello", page)
  store:add(Entry.new({ url = "https://b.org/" }))
  eq(store:page(1), page)
  eq(store:page(2), nil)
  local size, stored = store:page_size(1)
  eq(size, #page)
  ok(stored < size / 10, stored)
  same(store:stats(), { entries = 2, tags = 0, pages = 1, size = #page, stored = stored })
  store:remove(1)
  eq(store:stats().pages, 0)                 -- ON DELETE CASCADE
end)

test("the schema is at the latest version", function()
  eq(assert(Store.open(":memory:")).db:first("PRAGMA user_version").user_version, 2)
end)
```

### Checkpoint

Where the output shows `/path/to/project/ch17`, you'll see your own path.

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
db_test          9 tests, 0 failed
store_test       11 tests, 0 failed
fetch_test       3 tests, 0 failed
compress_test    4 tests, 0 failed
e2e_test         5 tests, 0 failed

78 passed, 0 failed
$ export STASH_HOME=demo STASH_NOW=1767225600
$ PAGES=file://$PWD/test/fixtures
$ ./stash add $PAGES/lua.html -t lua,lang
added #1 The Programming Language Lua
$ ./stash add $PAGES/luajit.html -t lua,jit
added #2 LuaJIT: a Just-In-Time Compiler & FFI
$ ./stash add $PAGES/sqlite.html -t db
added #3 SQLite FTS5 Extension
$ ./stash add https://example.com/ --no-fetch
added #4 example.com
$ ./stash show 2
id:    2
title: LuaJIT: a Just-In-Time Compiler & FFI
url:   file:///path/to/project/ch17/test/fixtures/luajit.html
tags:  jit, lua
added: 2026-01-01 00:00 UTC
page:  278 bytes, 208 compressed
$ ./stash show 2 --body
<!DOCTYPE html>
<html>
<head><title>LuaJIT: a Just-In-Time Compiler &amp; FFI</title></head>
<body>
  <p>LuaJIT runs Lua code very fast with a tracing JIT compiler.</p>
  <p>Its FFI library calls C functions and uses C data structures
  from plain Lua code.</p>
</body>
</html>
$ ./stash show 4 --body; echo "exit $?"
stash: no saved page for #4
exit 1
$ ./stash stats
entries  4
tags     4
pages    3
size     743 bytes
stored   569 bytes (77%)
$ wc -c test/fixtures/*.html
237 test/fixtures/lua.html
278 test/fixtures/luajit.html
228 test/fixtures/sqlite.html
743 total
$ ./stash rm 3
removed #3 SQLite FTS5 Extension
$ ./stash stats
entries  3
tags     3
pages    2
size     515 bytes
stored   389 bytes (76%)
$ LUA_PATH="src/?.lua" luajit -e 'local c = require("stash.compress") local blob = c.pack(("na"):rep(1000)) print(#blob, #c.unpack(blob), require("bit").tohex(c.crc32("hello")), c.version())'
32	2000	3610a686	1.2.11
```

Tiny pages barely compress: zlib needs repetition to find, and the 8-byte header is a large share of
200 bytes. Real web pages are kilobytes of repetitive HTML and shrink much more.

The complete project at this point is in `project/ch17/`.

## Summary

- Lua strings hold any bytes but can't change; `uint8_t[?]` arrays can. Copy with `ffi.copy`, convert
  with `ffi.string(ptr, len)`; always pass the length for binary data.
- `bit` works on 32-bit signed integers: `band`, `bor`, `lshift`, `rshift`, `tobit`, `tohex`,
  `bswap`. On 64-bit cdata it uses all 64 bits.
- Byte order: build and read file formats with shifts and masks. `ffi.abi("le")` gives the CPU's
  order.
- zlib: `compressBound`, `compress2`, `uncompress`, with a `uLong[1]` in/out length. zlib doesn't
  store the original size; store it yourself.
- `crc32(crc, buf, len)` checksums data at once or in pieces. `tobit` both sides before comparing.
- A struct pointer cast onto a string reads binary fields in place, in the CPU's byte order.
- SQLite: bind binary data as a BLOB (`sqlite3_bind_blob`), read it with `sqlite3_column_blob`.

## Exercises

1. Write `u16_le(n)` and `read_u16_le(s, i)` for 16-bit little-endian numbers, and check that
   `read_u16_le(u16_le(513), 1)` is `513`. What bytes does `u16_le(513)` produce?

   <details><summary>Solution</summary>

   ```lua
   local bit = require("bit")

   local function u16_le(n)
     return string.char(bit.band(n, 0xff), bit.band(bit.rshift(n, 8), 0xff))
   end

   local function read_u16_le(s, i)
     local lo, hi = s:byte(i, i + 1)
     return bit.bor(lo, bit.lshift(hi, 8))
   end

   print(u16_le(513):byte(1, -1))
   print(read_u16_le(u16_le(513), 1))
   ```

   ```console
   1	2
   513
   ```

   513 is `0x0201`; little-endian puts the low byte (`0x01`) first. 16-bit values never reach the
   sign bit, so no negative surprises.

   </details>

2. Give `compress.pack` an optional `level` argument (default 9) and measure the `luajit.html`
   fixture at levels 1 and 9. Why is the difference so small?

   <details><summary>Solution</summary>

   In `pack`:

   ```lua
   function M.pack(data, level)
     ...
     local rc = Z.compress2(out, out_len, data, #data, level or Z.Z_BEST_COMPRESSION)
   ```

   ```console
   $ LUA_PATH="src/?.lua" luajit -e 'local c = require("stash.compress") local page = io.open("test/fixtures/luajit.html"):read("*a") print(#page, #c.pack(page, 1), #c.pack(page, 9))'
   278	210	208
   ```

   Higher levels search harder for repeated strings. A 278-byte page has few, so there's little to
   gain. On large pages the gap grows, as does level 9's time.

   </details>

3. Damage a stored page on purpose: change one byte of `pages.data` for entry 1 with SQL, then run
   `stash show 1 --body`. What does `stash` print, and with what exit code?

   <details><summary>Solution</summary>

   After the checkpoint (entry 1 is `lua.html`), replace byte 20 of the blob with a zero byte.
   `substr` and `||` work on blobs, `zeroblob(1)` is one zero byte, and `CAST` keeps the result a
   BLOB (`||` makes text):

   ```console
   $ LUA_PATH="src/?.lua" luajit -e 'local db = require("stash.db").open("demo/stash.db") db:run("UPDATE pages SET data = CAST(substr(data, 1, 19) || zeroblob(1) || substr(data, 21) AS BLOB) WHERE entry_id = 1")'
   $ ./stash show 1 --body; echo "exit $?"
   stash: the saved page of #1 is damaged: corrupt data (zlib error -3)
   exit 2
   ```

   Exit code 2, as for every `errors.fail`. Byte 20 is in the zlib stream, so zlib notices first: the
   stream ends with its own checksum (Adler-32). Damage byte 5 instead, in our CRC field (use
   `substr(data, 1, 4)` and `substr(data, 6)`), and our check reports it:

   ```console
   stash: the saved page of #1 is damaged: checksum mismatch: 8d2a2f62, expected 002a2f62
   ```

   </details>

4. `compress.unpack` copies the zlib part with `blob:sub(9)`. Rewrite that line to pass a pointer
   into the blob instead, without copying. What must stay true for this to be safe?

   <details><summary>Solution</summary>

   ```lua
   local stream = ffi.cast("const Bytef *", blob) + HEADER
   local rc = Z.uncompress(out, out_len, stream, #blob - HEADER)
   ```

   The tests still pass (`luajit test/run.lua compress`). It's safe because `blob` is a local that
   stays alive until `unpack` returns. The pointer points into the string's memory, which the garbage
   collector could free once nothing refers to the string.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-17--binary-data-and-zlib)
