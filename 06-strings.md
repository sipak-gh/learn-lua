# Chapter 6 — Strings and Patterns

`stash` works mostly with text. This chapter covers the string library, escapes, long strings,
**patterns** (Lua's small, fast alternative to regular expressions), building big strings, and
UTF-8. `stash` learns to split tag lists, check URLs and tags, make titles from URLs, search, and
print columns. After tables ([Chapter 5](05-tables.md)) come objects
([Chapter 7](07-metatables-and-objects.md)).

## Strings are values

Recap from [Chapter 2](02-values-and-types.md):

- **Immutable**: no function changes a string; they all return a new one.
- **Interned**: equal strings share one copy, so `a == b` and string keys are cheap.
- **8-bit clean**: any bytes, even zero, so binary data fits (zlib, SQLite blobs later).
- `#s` is the length in **bytes**.

## The string library

String functions live in the `string` table. `s:upper()` is method syntax for
`string.upper(s)`. It works because all strings share a metatable whose `__index` is `string`
([Chapter 7](07-metatables-and-objects.md)); for now, just use the colon.

`examples/ch06/basics.lua`

```lua
-- The string library, called as functions and as methods.
local s = "Hello, Lua"

print(#s, string.len(s))          -- length in bytes
print(string.upper(s), s:lower()) -- s:lower() is string.lower(s)
print(s:sub(1, 5))                -- characters 1 to 5 (inclusive)
print(s:sub(-3))                  -- negative = count from the end
print(s:sub(8, 100), s:sub(5, 2) == "") -- out of range is clamped
print(("ab"):rep(3), ("ab"):rep(3, "-"))
print(s:reverse())
print(s:byte(1), s:byte(-1), s:byte(1, 3)) -- byte codes
print(string.char(76, 117, 97))           -- and back
print(("%d items"):format(3))             -- literal: needs parentheses
print(s, "unchanged")                     -- strings never change in place
```

```console
$ luajit examples/ch06/basics.lua
10	10
HELLO, LUA	hello, lua
Hello
Lua
Lua	true
ababab	ab-ab-ab
auL ,olleH
72	97	72	101	108
Lua
3 items
Hello, Lua	unchanged
```

| Function | Returns |
|----------|---------|
| `s:sub(i [, j])` | Bytes `i`..`j`, inclusive (default `j = -1`). Negative counts from the end. Out of range is clamped, not an error. |
| `s:upper()`, `s:lower()` | Copy with ASCII letters changed. |
| `s:rep(n [, sep])` | `n` copies joined by `sep` (`sep`: LuaJIT, from 5.2). |
| `s:reverse()` | Bytes reversed. |
| `s:byte(i [, j])` | Byte codes `i`..`j` (defaults: `i = 1`, `j = i`). |
| `string.char(...)` | String from byte codes. |
| `s:len()` | Same as `#s`. |

- **Indices start at 1**; the end is **inclusive**: `s:sub(1, 5)` is five bytes.
- A **literal** needs parentheses before a method: `("%d items"):format(3)`. `"x":upper()` is a
  syntax error (`')' expected near ':'`).

## Escapes and long strings

Short strings use `"..."` or `'...'` (no difference). A backslash starts an escape:

| Escape | Meaning |
|--------|---------|
| `\n` `\t` `\r` | newline, tab, carriage return |
| `\\` `\"` `\'` | backslash, quotes |
| `\ddd` | byte with **decimal** code `ddd` (1–3 digits): `\65` is `A` |
| `\xhh` | byte with hex code `hh` (LuaJIT, from 5.2) |
| `\u{XXXX}` | UTF-8 bytes of a Unicode code point (LuaJIT, from 5.3) |
| `\z` | skip the following line break and spaces (LuaJIT, from 5.2) |

**Long strings** `[[ ... ]]` span lines and process **no escapes**. A newline right after `[[` is
dropped. If the text contains `]]`, add equal signs: `[==[ ... ]==]` ends only at `]==]` (same rule
as block comments, [Chapter 1](01-getting-started.md)).

`examples/ch06/escapes.lua`

```lua
-- Escape sequences and long strings.
print("tab:\t|  quote:\"  backslash:\\  newline:\nnext line")
print("decimal \65\066\067 and hex \x41\x42\x43")  -- \ddd is DECIMAL
print("unicode \u{20AC} is " .. #"\u{20AC}" .. " bytes")
print("one \z
       line")                     -- \z skips the line break and spaces
print([[
Long string: the first newline is dropped.
No escapes here: \n stays as typed.]])
print([==[It may contain ]] safely.]==])
local embedded = "a\0b"
print(#embedded)                  -- strings may hold any byte, even zero
```

```console
$ luajit examples/ch06/escapes.lua
tab:	|  quote:"  backslash:\  newline:
next line
decimal ABC and hex ABC
unicode € is 3 bytes
one line
Long string: the first newline is dropped.
No escapes here: \n stays as typed.
It may contain ]] safely.
3
```

Long strings suit help texts, SQL, HTML and test data.

## Finding text: `string.find`

`s:find(pattern [, init [, plain]])` searches from byte `init` (default 1). It returns the first
match's start and end (then any captures), or `nil`.

`examples/ch06/find.lua`

```lua
-- string.find returns where a match starts and ends, or nil.
local s = "one.two.three"

print(s:find("two"))         -- 5  7
print(s:find("four"))        -- nil
print(s:find("t", 6))        -- start looking at position 6
print(s:find(".", 1, true))  -- plain: "." is just a dot
print(s:find("."))           -- pattern: "." means any character
print(s:find("(%a+)%.(%a+)")) -- captures come after the positions
if s:find("three", 1, true) then
  print("contains three")
end
```

```console
$ luajit examples/ch06/find.lua
5	7
nil
9	9
4	4
1	1
1	7	one	two
contains three
```

Without `plain`, the text is a **pattern**: `.`, `%`, `-`, `+`, `(` and others are special.
`plain = true` searches it as is (pass `init` too: `s:find(text, 1, true)`).

**Rule:** search user text with `find(text, 1, true)`. Otherwise `c++` or `50%` breaks the search
or raises an error.

## `string.format`

`string.format(fmt, ...)` is C's `printf`: each `%` directive takes the next argument.

`examples/ch06/format.lua`

```lua
-- string.format: printf-style formatting.
local fmt = string.format

print(fmt("%d apples, %5d|, %-5d|, %05d", 3, 42, 42, 42))
print(fmt("%.2f  %8.3f|  %e  %g  %g", math.pi, math.pi, 12345.678, 0.1, 1e20))
print(fmt("%x %X %o %c", 255, 255, 8, 65))
print(fmt("[%s] [%10s] [%-10s] [%.3s]", "lua", "lua", "lua", "luajit"))
print(fmt("%q", 'say "hi"\n'))    -- quoted so Lua can read it back
print(fmt("%s %s %s", nil, true, 12)) -- %s calls tostring
print(fmt("100%% done"))
print(fmt("%d", 3.99))                -- %d cuts the fraction
```

```console
$ luajit examples/ch06/format.lua
3 apples,    42|, 42   |, 00042
3.14     3.142|  1.234568e+04  0.1  1e+20
ff FF 10 A
[lua] [       lua] [lua       ] [lua]
"say \"hi\"\
"
nil true 12
100% done
3
```

| Directive | Meaning |
|-----------|---------|
| `%d` | integer (LuaJIT drops the fraction: `3.99` → `3`) |
| `%5d`, `%-5d`, `%05d` | width 5: right-aligned, left-aligned, zero-padded |
| `%f`, `%.2f`, `%8.3f` | fixed-point, with precision and width |
| `%e`, `%g` | exponent form; shorter of `%f`/`%e` |
| `%x`, `%X`, `%o` | hex (lower/upper case), octal |
| `%c` | the character with this code |
| `%s`, `%10s`, `%-10s`, `%.3s` | string; width pads, precision cuts |
| `%q` | quoted so Lua can read it back (escapes quotes, `\`, newlines, control bytes) |
| `%%` | a literal `%` |

- `%s` calls `tostring` on any value.
- Widths count **bytes**: a UTF-8 `é` (2 bytes) makes a column one space short.
- `stash` uses the method style: `("%d items"):format(n)`.

## Patterns

A **pattern** describes a set of strings, like a regular expression. `find`, `match`, `gmatch` and
`gsub` take patterns.

Why not POSIX regexes? Size. A regex engine is thousands of lines of C, more than Lua's whole
standard library; Lua's matcher is a few hundred and covers everyday jobs. For more, add Lua code,
or call a C regex library through the FFI ([Part II](13-ffi-basics.md)).

`s:match(pattern [, init])` returns the match (or its captures), or `nil`. Try patterns with it:

`examples/ch06/patterns.lua`

```lua
-- Lua patterns: a table of examples. Each row: pattern, subject, match.
local examples = {
  { "%d+",           "order 66 shipped" },  -- one or more digits
  { "%a+",           "123abc456" },         -- letters
  { "%s",            "no-space here" },     -- whitespace
  { "%u%l+",         "hello World" },       -- upper then lowers
  { "%x+",           "color #ff8800" },     -- the FIRST match wins: c!
  { "%p",            "end." },              -- punctuation
  { "%W+",           "a, b" },              -- uppercase class = complement
  { "[aeiou]+",      "queueing" },          -- a set
  { "[^%s,]+",       "  alpha, beta" },     -- a negated set
  { "[0-9a-f]+",     "ID: 3fa9" },          -- ranges in a set
  { "colou?r",       "my colour" },         -- ? = optional
  { "a.c",           "abc" },               -- . = any character
  { "%.",            "x.y" },               -- %. = a literal dot
  { "^%d+",          "42 is 6*7" },         -- ^ anchors at the start
  { "%d+$",          "6*7 is 42" },         -- $ anchors at the end
  { "^%d+$",         "42x" },               -- whole string must match
}

for _, ex in ipairs(examples) do
  local pattern, subject = ex[1], ex[2]
  print(("%-10s %-20s -> [%s]"):format(pattern, '"' .. subject .. '"', tostring(subject:match(pattern))))
end
```

```console
$ luajit examples/ch06/patterns.lua
%d+        "order 66 shipped"   -> [66]
%a+        "123abc456"          -> [abc]
%s         "no-space here"      -> [ ]
%u%l+      "hello World"        -> [World]
%x+        "color #ff8800"      -> [c]
%p         "end."               -> [.]
%W+        "a, b"               -> [, ]
[aeiou]+   "queueing"           -> [ueuei]
[^%s,]+    "  alpha, beta"      -> [alpha]
[0-9a-f]+  "ID: 3fa9"           -> [3fa9]
colou?r    "my colour"          -> [colour]
a.c        "abc"                -> [abc]
%.         "x.y"                -> [.]
^%d+       "42 is 6*7"          -> [42]
%d+$       "6*7 is 42"          -> [42]
^%d+$      "42x"                -> [nil]
```

### The pieces

**Character classes** match one character:

| Class | Matches |
|-------|---------|
| `.` | any character |
| `%a` | letters (`A-Z`, `a-z`) |
| `%d` | digits (`0-9`) |
| `%l`, `%u` | lowercase, uppercase letters |
| `%s` | whitespace (space, tab, newline, ...) |
| `%w` | letters and digits |
| `%x` | hex digits |
| `%p` | punctuation |
| `%c` | control characters |
| `%g` | printable characters except space (LuaJIT, from 5.2) |
| `%A`, `%D`, `%S`, ... | uppercase = **complement** ("anything but") |
| `%x`, x not a letter | the character `x` itself: `%.` is a dot, `%%` a percent sign |
| `[set]` | any character in the set: `[aeiou]`, `[0-9a-f]`, `[%w_]`, `[%-+]` |
| `[^set]` | any character **not** in the set |

LuaJIT's classes are fixed ASCII (PUC Lua asks the C locale), so `%a` never matches `é`.

**Magic characters** `^ $ ( ) % . [ ] * + - ?` need a `%` to match literally. The pattern escape is
`%`, not `\` (string literals already use `\`).

**Quantifiers** follow a single class:

| Quantifier | Meaning |
|------------|---------|
| `*` | 0 or more, as many as possible |
| `+` | 1 or more, as many as possible |
| `-` | 0 or more, **as few as possible** |
| `?` | 0 or 1 |

**Anchors:** a leading `^` matches only at the subject's start, a trailing `$` only at its end.
Elsewhere they are plain characters.

### Greedy `*` and lazy `-`

`*` takes as much as it can, `-` as little. It matters when the text after it appears twice:

`examples/ch06/lazy.lua`

```lua
-- The four quantifiers. They apply to ONE character class only.
local s = "<b>bold</b> and <b>more</b>"

print(s:match("<b>.*</b>"))   -- *  longest:  0 or more
print(s:match("<b>.-</b>"))   -- -  shortest: 0 or more
print(("aaa"):match("a+"))    -- +  1 or more, longest
print(("ab"):match("a?b"), ("b"):match("a?b")) -- ?  0 or 1
print(("key=   value"):match("=%s*(.*)"))
```

```console
$ luajit examples/ch06/lazy.lua
<b>bold</b> and <b>more</b>
<b>bold</b>
aaa
ab	b
value
```

Usually you want `.-`: "anything, up to the first ...".

### Captures

Parentheses **capture** what they match; `match` then returns the captures. Captures are strings
(use `tonumber`). An empty `()` captures a **position** (a number).

`examples/ch06/captures.lua`

```lua
-- Captures pull pieces out of a match.
local date = "2026-01-31"
local y, m, d = date:match("(%d+)-(%d+)-(%d+)")
print(y, m, d, type(y))                      -- captures are strings

print(("name = Ada"):match("^(%w+)%s*=%s*(%w+)$"))
print(("hello"):match("()ll()"))             -- () captures a position
print(("say 'hi' or \"bye\""):match("([\"'])(.-)%1")) -- %1 = same quote again

-- %b() matches balanced pairs: here, a parenthesized group with nesting.
print(("f(a, g(b, c)) + 1"):match("%b()"))

-- %f[set] is a frontier: the spot where the previous char is NOT in set
-- and the next char IS. %f[%w] is "start of a word".
print(("cat concat cat"):gsub("%f[%w]cat%f[%W]", "dog"))
```

```console
$ luajit examples/ch06/captures.lua
2026	01	31	string
name	Ada
3	5
'	hi
(a, g(b, c))
dog concat dog	2
```

- `%1` ... `%9` match capture 1..9's text again (back-reference): the closing quote above
  matches the opening one.
- `%bxy` matches a balanced run from `x` to `y`, with nesting: `%b()`, `%b[]`, `%b{}`. Regexes
  can't do this.
- `%f[set]` is a **frontier**: an empty match where the previous character is not in `set` and the
  next one is. `%f[%w]` = word start, `%f[%W]` = word end. The string's ends count as `\0`.
  (Undocumented in 5.1, works in LuaJIT, official since 5.2.)

### Patterns versus regular expressions

What bites regex users:

| Regex | Lua pattern |
|-------|-------------|
| `\d`, `\w`, `\s` | `%d`, `%w`, `%s` |
| `\.` | `%.` |
| `.*?` (lazy) | `.-` |
| `(ab)+` (quantified group) | not possible: quantifiers apply to **one** class |
| `a{2,4}` | not possible: write `aa?a?a?`, or check the length in Lua |
| `cat|dog` (alternation) | not possible: try two patterns, or use a set for single chars |
| `\b` | `%f[%w]` / `%f[%W]` |
| — | `%b()` balanced pairs |

Rarely a problem: use two simpler matches, or a Lua loop.

### A malformed pattern is an error

A broken pattern raises an error:

`examples/ch06/bad_pattern.lua`

```lua
-- A malformed pattern is a runtime error.
print(("price: $5"):find("$5"))     -- fine: $ is only special at the end
print(("100%"):find("100%"))        -- error: % must be followed by something
```

```console
$ luajit examples/ch06/bad_pattern.lua
8	9
luajit: examples/ch06/bad_pattern.lua:3: malformed pattern (ends with '%')
stack traceback:
	[C]: in function 'find'
	examples/ch06/bad_pattern.lua:3: in main chunk
	[C]: at 0x5c419ff273a0
[exit 1]
```

(The `0x...` address varies.) Others: `malformed pattern (missing ']')` for `[a`,
`unfinished capture` for `(a`, `invalid capture index` for `%2` with one capture.

## Iterating: `string.gmatch`

`s:gmatch(pattern)` returns an iterator for a generic `for`: each step gives the next match (or
its captures).

`examples/ch06/gmatch.lua`

```lua
-- gmatch returns an iterator over all matches.
for word in ("the quick brown fox"):gmatch("%a+") do
  io.write("[", word, "] ")
end
print()

-- With captures, each step returns the captures.
local settings = {}
for key, value in ("width=80, height=24, title=stash"):gmatch("(%w+)=(%w+)") do
  settings[key] = value
end
print(settings.width, settings.height, settings.title)

-- Splitting lines: match "everything that is not a newline".
local text = "first\nsecond\n\nfourth"
for line in text:gmatch("[^\n]+") do
  print("line:", line)          -- note: the empty line is skipped
end
```

```console
$ luajit examples/ch06/gmatch.lua
[the] [quick] [brown] [fox] 
80	24	stash
line:	first
line:	second
line:	fourth
```

- `[^\n]+` = a run of non-newlines; `[^,]+` splits on commas. `+` skips empty pieces (usually
  what you want).
- Gotcha: in `gmatch`, a leading `^` is a literal `^`, **not** an anchor (that would stop after one
  match).

## Replacing: `string.gsub`

`s:gsub(pattern, replacement [, n])` replaces every match (or the first `n`) and returns **two**
values: the new string and the count. The replacement can be:

- **a string:** `%0` = whole match, `%1`..`%9` = captures, `%%` = `%`.
- **a table:** looked up with the match (or first capture) as key.
- **a function:** called with the captures (or the match); returns the replacement.

A `nil` or `false` from the table or function keeps the match.

`examples/ch06/gsub.lua`

```lua
-- gsub = global substitution. It returns the new string AND the count.
print(("hello world"):gsub("o", "0"))
print(("hello world"):gsub("o", "0", 1))            -- at most 1 replacement

-- In a replacement string, %0 is the whole match, %1.. the captures.
print(("John Smith"):gsub("(%w+) (%w+)", "%2, %1"))
print(("a b c"):gsub("%w", "<%0>"))

-- A table replacement looks the match (or first capture) up.
local vars = { name = "Ada", lang = "Lua" }
print(("$name writes $lang, not $cobol"):gsub("%$(%w+)", vars)) -- missing: kept

-- A function replacement is called for each match.
print(("3 apples and 12 pears"):gsub("%d+", function(n)
  return tostring(tonumber(n) * 2)
end))

-- Keep only the string: wrap the call in parentheses.
local clean = (("  lots   of   space  "):gsub("%s+", " "))
print("[" .. clean .. "]")

-- To use user text as a pattern, escape the magic characters first.
local function escape(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end
print(escape("1+1=2?"), ("is 1+1=2?"):find(escape("1+1=2?")))
```

```console
$ luajit examples/ch06/gsub.lua
hell0 w0rld	2
hell0 world	1
Smith, John	1
<a> <b> <c>	3
Ada writes Lua, not $cobol	3
6 apples and 24 pears	2
[ lots of space ]
1%+1=2%?	4	9
```

Gotchas:

- Both values go into `print(s:gsub(...))` or `f(s:gsub(...))`. Write `(s:gsub(...))` to keep
  only the string ([Chapter 4](04-functions.md)'s truncation rule).
- `%` is special in the **replacement** too. Escape user text with `text:gsub("%%", "%%%%")`, or
  use a function.

Idiom: `select(2, s:gsub("%a+", ""))` counts words.

## Building strings efficiently

`s = s .. x` copies all of `s` into a **new** string. In a loop the cost grows with the square of
the length. Collect pieces in a table and join once with `table.concat`.

`examples/ch06/build.lua`

```lua
-- Building a big string: collect pieces, join once.
local N = 20000

-- Slow: every .. makes a new string and copies everything so far.
local t0 = os.clock()
local s = ""
for i = 1, N do
  s = s .. i .. ","
end
local slow = os.clock() - t0

-- Fast: put the pieces in a table, then table.concat.
t0 = os.clock()
local parts = {}
for i = 1, N do
  parts[#parts + 1] = i .. ","
end
local s2 = table.concat(parts)
local fast = os.clock() - t0

print(#s, #s2, s == s2)
print(("concat in a loop: %.1f ms, table.concat: %.1f ms"):format(slow * 1000, fast * 1000))
print(table.concat({ "a", "b", "c" }, ", "))
print(table.concat({ 1, 2, 3 }, " + ", 2, 3))   -- items 2..3 only

-- LuaJIT's string.buffer does the same job without the table (Chapter 18).
local buffer = require("string.buffer")
local buf = buffer.new()
for i = 1, 3 do
  buf:put("item ", i, "; ")
end
print(buf:tostring())
```

```console
$ luajit examples/ch06/build.lua
108894	108894	true
concat in a loop: 42.4 ms, table.concat: 1.3 ms
a, b, c
2 + 3
item 1; item 2; item 3; 
```

Timings vary; the gap doesn't. Rules:

- `a .. b .. c` in one expression is fine: it compiles to one concatenation.
- In a loop, append to a table, then `table.concat(parts, sep)`.
- LuaJIT's `string.buffer` is a growable byte buffer for this job: `buf:put(...)` appends,
  `buf:tostring()` returns the result ([Chapter 18](18-performance-and-the-jit.md)).

## UTF-8

Lua strings are bytes with no encoding; LuaJIT has no `utf8` library (PUC Lua 5.3 added one).
UTF-8 still passes through: reading, storing, comparing, joining and printing work. Watch out:

- `#s`, `sub`, `byte` and `format` widths count **bytes**.
- `upper`/`lower` and `%a` only know ASCII letters.
- `sub` can cut a multi-byte character in half.

A UTF-8 character is a lead byte (`0`–`127` or `194`–`244`) plus continuation bytes
(`128`–`191`). As a pattern:

`examples/ch06/utf8.lua`

```lua
-- Lua strings are bytes. UTF-8 text works, but # and sub count bytes.
local s = "naïve café"
print(#s)                          -- 12 bytes, 10 characters
print(s:upper())                   -- only ASCII letters change
print(s:sub(1, 3))                 -- cuts the ï in half

-- One UTF-8 character: a lead byte, then 0 or more continuation bytes.
local CHAR = "[%z\1-\127\194-\244][\128-\191]*"
local count = 0
for ch in s:gmatch(CHAR) do
  count = count + 1
end
print(count)                       -- 10

-- A UTF-8 aware length, from the same pattern.
local function ulen(str)
  return select(2, str:gsub(CHAR, ""))
end
print(ulen("€uro"), #"€uro")
```

```console
$ luajit examples/ch06/utf8.lua
12
NAïVE CAFé
na�
10
4	6
```

(The cut `ï` shows as `�` or garbage, depending on your terminal.)

`stash` just counts bytes: accented titles line up slightly off, nothing breaks.

## Building stash: tags, titles, search and columns

Start from `project/ch05/stash.lua`. Six changes:

1. A `split` helper turns `-t "Book, lua"` into `{ "Book", "lua" }`.
2. `title_from_url` makes a title such as `www.lua.org/pil` from a URL.
3. `add` checks that the URL has a scheme and that tags use safe characters.
4. A new `search TERM` command does a case-insensitive plain search.
5. `list`, `search`, `tags`, `show` and `help` print columns with `string.format`.
6. `fail` takes a format and arguments.

### String helpers

Update the comment at the top of the file:

```lua
#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 6: strings. Tags are split on commas, titles come from URLs,
-- `search` matches text, and output is lined up in columns.
```

Add a new section after `find_entry` and before `has_tag`:

```lua
---------------------------------------------------------------------------
-- String helpers
---------------------------------------------------------------------------

-- Splits "a, b,,c" into { "a", "b", "c" }: pieces are trimmed, empty ones dropped.
local function split(s, sep)
  local parts = {}
  for piece in s:gmatch("[^" .. sep .. "]+") do
    piece = piece:match("^%s*(.-)%s*$")      -- trim: `.-` is the lazy `.*`
    if piece ~= "" then
      parts[#parts + 1] = piece
    end
  end
  return parts
end

-- Shortens s to at most `width` characters, marking the cut with "...".
-- (Counts bytes: fine for ASCII, see the UTF-8 notes in this chapter.)
local function truncate(s, width)
  if #s <= width then
    return s
  end
  return s:sub(1, width - 3) .. "..."
end

-- "https://www.lua.org/pil/?x=1" -> "www.lua.org/pil": the best title we
-- can make without downloading the page.
local function title_from_url(url)
  local rest = url:match("^%a[%w+.-]*://([^?#]*)") or url
  return (rest:gsub("/+$", ""))              -- parentheses: keep only the string
end
```

How the patterns work:

- `"[^" .. sep .. "]+"` builds `[^,]+`: runs of non-separators. (Only for a `sep` that isn't
  magic in a set, like `,` or space: all `stash` needs.)
- `^%s*(.-)%s*$` trims: leading spaces, then the shortest run that lets trailing spaces reach the
  end. A greedy `(.*)` would swallow them.
- `^%a[%w+.-]*://` is a URL scheme: a letter, then letters, digits, `+`, `.` or `-` (a final `-`
  in a set is literal), then `://`. `([^?#]*)` captures up to a query (`?`) or fragment (`#`).
- `/+$` removes trailing slashes.

### `fail` with a format

Replace `fail` so it formats its message:

```lua
-- string.format works like C's printf.
local function fail(fmt, ...)
  print("stash: " .. fmt:format(...))
end
```

`fail("add: missing URL")` still works: a format without `%` prints as is.

### The argument parser

`parse_args` changes in two places:

- Unknown options (anything starting with `-`, except `-` alone) are now errors.
- `"list"` values are split on commas, so `-t a,b -t c` gives `{ "a", "b", "c" }`.

The whole function:

```lua
-- Parses args[first], args[first+1], ... using a spec that maps each flag
-- to { field, kind }. Kinds: "flag" (no value), "value", "number", "list"
-- (may repeat, values may be comma-separated). Returns an options table: named fields for flags, and the
-- remaining (positional) arguments at 1, 2, 3...
-- On a bad argument it returns nil plus a message.
local function parse_args(args, first, spec)
  local opts = {}
  local i = first
  while i <= #args do
    local a = args[i]
    local option = spec[a]
    if option == nil then
      -- "-" alone usually means stdin, so it counts as a positional argument.
      if a:sub(1, 1) == "-" and a ~= "-" then
        return nil, "unknown option " .. a
      end
      opts[#opts + 1] = a                    -- positional argument
    else
      local field, kind = option[1], option[2]
      if kind == "flag" then
        opts[field] = true
      else
        i = i + 1
        local value = args[i]
        if value == nil then
          return nil, a .. " needs a value"
        end
        if kind == "number" then
          value = tonumber(value)
          if value == nil then
            return nil, a .. " needs a number"
          end
        end
        if kind == "list" then
          opts[field] = opts[field] or {}
          for _, item in ipairs(split(value, ",")) do
            table.insert(opts[field], item)
          end
        else
          opts[field] = value
        end
      end
    end
    i = i + 1
  end
  return opts
end
```

### The commands

Each command gets a short `usage` plus a separate `help` text, so `help` can align them. Add
`"search"` to `order`:

```lua
local order = { "add", "list", "search", "show", "rm", "tags", "help", "version" }
```

Replace `commands.add`, and add `format_row` after it:

```lua
commands.add = {
  usage = "add URL [-t TAGS] [-n NOTE]",
  help = "save a bookmark",
  options = { ["-t"] = { "tags", "list" }, ["-n"] = { "note", "value" } },
  run = function(opts)
    local url = opts[1]
    if url == nil then
      return fail("add: missing URL")
    end
    -- A scheme like "https:" or "file:", then "//".
    if not url:find("^%a[%w+.-]*://") then
      return fail("add: '%s' does not look like a URL", url)
    end
    local tags = {}
    for i, tag in ipairs(opts.tags or {}) do
      tag = tag:lower()
      if not tag:find("^[%w_-]+$") then
        return fail("add: bad tag '%s' (use letters, digits, - and _)", tag)
      end
      tags[i] = tag
    end
    table.sort(tags)
    local entry = { id = next_id, url = url, title = title_from_url(url), tags = tags,
                    note = opts.note or "" }
    next_id = next_id + 1
    entries[#entries + 1] = entry
    print(("added %d: %s"):format(entry.id, entry.title))
  end,
}

-- One line per entry: id right-aligned, title padded to a fixed width.
local function format_row(entry)
  return ("%3d  %-36s  %s"):format(entry.id, truncate(entry.title, 36),
                                   table.concat(entry.tags, ","))
end
```

`^[%w_-]+$`: the anchors force **every** character to be a letter, digit, `_` or `-`.

In `commands.list`, change `usage`, add `help`, and print with `format_row`:

```lua
commands.list = {
  usage = "list [-t TAG] [--limit N]",
  help = "list bookmarks",
  options = { ["-t"] = { "tag", "value" }, ["--limit"] = { "limit", "number" } },
  run = function(opts)
    local shown = 0
    for _, entry in ipairs(entries) do
      if opts.limit and shown >= opts.limit then
        break
      end
      if opts.tag == nil or has_tag(entry, opts.tag) then
        print(format_row(entry))
        shown = shown + 1
      end
    end
  end,
}
```

After `commands.list`, add the `matches` helper and the `search` command:

```lua
-- Case-insensitive substring search. The `true` argument to find()
-- turns off patterns, so "c++" or "50%" are searched literally.
local function matches(entry, term)
  term = term:lower()
  local fields = { entry.title, entry.url, entry.note, table.concat(entry.tags, " ") }
  for _, field in ipairs(fields) do
    if field:lower():find(term, 1, true) then
      return true
    end
  end
  return false
end

commands.search = {
  usage = "search TERM",
  help = "find bookmarks containing TERM",
  options = {},
  run = function(opts)
    local term = opts[1]
    if term == nil then
      return fail("search: missing TERM")
    end
    local found = 0
    for _, entry in ipairs(entries) do
      if matches(entry, term) then
        print(format_row(entry))
        found = found + 1
      end
    end
    if found == 0 then
      fail("nothing matches '%s'", term)
    end
  end,
}
```

Lowercasing both sides makes the search case-insensitive.

Replace `commands.show` and `commands.rm`. Labels are padded with `%-6s`:

```lua
commands.show = {
  usage = "show ID",
  help = "show one bookmark",
  options = {},
  run = function(opts)
    local id = tonumber(opts[1])
    if id == nil then
      return fail("show: missing or bad ID")
    end
    local entry = find_entry(id)
    if entry == nil then
      return fail("no entry with id %d", id)
    end
    print(("%-6s %d"):format("id:", entry.id))
    print(("%-6s %s"):format("title:", entry.title))
    print(("%-6s %s"):format("url:", entry.url))
    print(("%-6s %s"):format("tags:", table.concat(entry.tags, ", ")))
    if entry.note ~= "" then
      print(("%-6s %s"):format("note:", entry.note))
    end
  end,
}

commands.rm = {
  usage = "rm ID",
  help = "delete a bookmark",
  options = {},
  run = function(opts)
    local id = tonumber(opts[1])
    if id == nil then
      return fail("rm: missing or bad ID")
    end
    local entry, index = find_entry(id)
    if entry == nil then
      return fail("no entry with id %d", id)
    end
    table.remove(entries, index)
    print(("removed %d: %s"):format(id, entry.title))
  end,
}
```

In `commands.tags`, split `usage`/`help` and right-align the count. Only these lines change:

```lua
commands.tags = {
  usage = "tags",
  help = "count bookmarks per tag",
  options = {},
  run = function()
    -- ... counting and sorting unchanged ...
    for _, row in ipairs(rows) do
      print(("%4d  %s"):format(row.count, row.tag))
    end
  end,
}
```

Replace `commands.help` and `commands.version`:

```lua
commands.help = {
  usage = "help",
  help = "show this help",
  options = {},
  run = function()
    print("usage: stash <command> [arguments]")
    print()
    print("commands:")
    for _, name in ipairs(order) do
      local command = commands[name]
      print(("  %-28s  %s"):format(command.usage, command.help))
    end
  end,
}

commands.version = {
  usage = "version",
  help = "print the version",
  options = {},
  run = function()
    print("stash " .. VERSION)
  end,
}
```

Finally, the two `fail` calls in `main` use formats:

```lua
  local command = commands[name]
  if command == nil then
    return fail("unknown command '%s' (try 'stash help')", name)
  end
  local opts, err = parse_args(args, 2, command.options)
  if opts == nil then
    return fail("%s: %s", name, err)
  end
  command.run(opts)
```

### Checkpoint

```console
$ luajit stash.lua help
usage: stash <command> [arguments]

commands:
  add URL [-t TAGS] [-n NOTE]   save a bookmark
  list [-t TAG] [--limit N]     list bookmarks
  search TERM                   find bookmarks containing TERM
  show ID                       show one bookmark
  rm ID                         delete a bookmark
  tags                          count bookmarks per tag
  help                          show this help
  version                       print the version
$ luajit stash.lua list
  1  The Programming Language Lua          lang,lua
  2  LuaJIT                                jit,lua
  3  SQLite FTS5 Extension                 db,search
$ luajit stash.lua search LUA
  1  The Programming Language Lua          lang,lua
  2  LuaJIT                                jit,lua
$ luajit stash.lua search "full-text"
  3  SQLite FTS5 Extension                 db,search
$ luajit stash.lua search python
stash: nothing matches 'python'
$ luajit stash.lua add "https://www.lua.org/pil/?ref=x" -t "Book, lua"
added 4: www.lua.org/pil
$ luajit stash.lua add www.lua.org
stash: add: 'www.lua.org' does not look like a URL
$ luajit stash.lua add https://example.com/ -t "c++"
stash: add: bad tag 'c++' (use letters, digits, - and _)
$ luajit stash.lua list --verbose
stash: list: unknown option --verbose
$ luajit stash.lua tags
   2  lua
   1  db
   1  jit
   1  lang
   1  search
```

Notice:

- `search LUA` ignores case.
- `search "full-text"` works because `find` is plain; in a pattern, `-` is a quantifier.
- `-t "Book, lua"` became `book` and `lua`: split, trimmed, lowercased.
- The title `www.lua.org/pil` came from the URL, minus the query.
- All in memory: the next run starts again from the three sample entries.

The complete project at this point is in `project/ch06/`.

## Summary

- Strings are immutable, interned, 8-bit clean bytes. `#s` counts bytes.
- `s:f(...)` is `string.f(s, ...)`. Literals need parentheses: `("x"):rep(3)`.
- `sub`: 1-based, inclusive, clamped; negative counts from the end.
- `[[...]]`/`[==[...]==]` are raw long strings. `\ddd` is decimal.
- `string.format` is `printf`; widths count bytes; `%q` quotes for Lua; `%s` takes anything.
- Patterns: classes (`%a %d %s %w %p ...`, uppercase = complement, `[set]`), quantifiers
  `* + - ?` on one class, anchors `^ $`, captures `()`, back-references `%1`, `%b()`, `%f[set]`.
  Escape with `%`.
- No alternation, `{n,m}` or quantified groups: combine simple patterns with Lua code.
- `find(text, 1, true)` searches literally: use it for user input.
- `match` returns captures, `gmatch` iterates, `gsub` replaces (string, table or function) and
  returns a count; `( )` keeps just the string.
- Build big strings with `table.concat` or `string.buffer`, not `..` in a loop.
- UTF-8 passes through, but lengths, `sub` and case functions work on bytes.

## Exercises

1. Write `count_words(s)` (words = runs of letters). Try `"Lua is small, fast; and embeddable!"`.
   Then do it in one line with `gsub`.

<details><summary>Solution</summary>

```lua
local function count_words(s)
  local n = 0
  for _ in s:gmatch("%a+") do
    n = n + 1
  end
  return n
end
print(count_words("Lua is small, fast; and embeddable!"))
-- one line: gsub's second result is the number of matches
print(select(2, ("Lua is small, fast; and embeddable!"):gsub("%a+", "")))
```

```console
6
6
```

</details>

2. Write `capitalize(s)` to upper-case the first letter of each word:
   `"hello lua world, it's 2026"` → `"Hello Lua World, It's 2026"`. Why does
   `s:gsub("%f[%a]%a", string.upper)` get `it's` wrong?

<details><summary>Solution</summary>

```lua
local function capitalize(s)
  return (s:gsub("(%a)([%w']*)", function(first, rest)
    return first:upper() .. rest
  end))
end
print(capitalize("hello lua world, it's 2026"))
```

```console
Hello Lua World, It's 2026
```

With `%f[%a]%a`, the `s` after the apostrophe is at a frontier too (`'` isn't a letter), giving
`It'S`. Matching "a letter, then letters, digits and apostrophes" keeps `'s` inside the word.

</details>

3. Write `parse_kv(s)`: `"name = stash; version=0.1.0 ;  note = a  b "` →
   `{ name = "stash", version = "0.1.0", note = "a  b" }`. Pairs are split by `;`; spaces around
   keys and values are ignored.

<details><summary>Solution</summary>

```lua
local function parse_kv(s)
  local t = {}
  for k, v in s:gmatch("([%w_]+)%s*=%s*([^;]*)") do
    t[k] = v:match("^(.-)%s*$")          -- drop trailing spaces
  end
  return t
end
local t = parse_kv("name = stash; version=0.1.0 ;  note = a  b ")
print(t.name, t.version, "[" .. t.note .. "]")
```

```console
stash	0.1.0	[a  b]
```

</details>

4. `truncate` can split a UTF-8 character. Write `utruncate(s, width)` that moves a cut inside a
   character back to its start (continuation bytes: `128`–`191`).
   `utruncate("naïve café au lait", 6)` should give `na...`.

<details><summary>Solution</summary>

```lua
local function utruncate(s, width)
  if #s <= width then
    return s
  end
  local cut = width - 3
  -- While the byte after the cut is a continuation byte, the cut is
  -- inside a character: move it back.
  while cut > 0 and s:byte(cut + 1) >= 128 and s:byte(cut + 1) < 192 do
    cut = cut - 1
  end
  return s:sub(1, cut) .. "..."
end
print(utruncate("naïve café au lait", 6), utruncate("naïve", 10), utruncate("aïbcdef", 5))
```

```console
na...	naïve	a...
```

Still byte-based: maybe shorter than `width` characters, but valid UTF-8.

</details>

5. Let `stash search` take several words; an entry must contain **all** of them:
   `search lua jit` finds only LuaJIT.

<details><summary>Solution</summary>

Loop over the positional arguments in `opts`, in `commands.search`:

```lua
  run = function(opts)
    if opts[1] == nil then
      return fail("search: missing TERM")
    end
    local found = 0
    for _, entry in ipairs(entries) do
      local all = true
      for _, term in ipairs(opts) do
        if not matches(entry, term) then
          all = false
          break
        end
      end
      if all then
        print(format_row(entry))
        found = found + 1
      end
    end
    if found == 0 then
      fail("nothing matches '%s'", table.concat(opts, " "))
    end
  end,
```

```console
$ luajit stash.lua search lua jit
  2  LuaJIT                                jit,lua
$ luajit stash.lua search lua sqlite
stash: nothing matches 'lua sqlite'
```

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-6--strings-and-patterns)
