# Chapter 5 — Tables

Tables are Lua's only data structure: one type serves as array, dictionary, record, set, queue,
object and module. You learn to build, change, loop over, sort and copy tables, and you meet the
length operator and its one trap: holes. `stash` gets a real data model: an in-memory list of
bookmarks, a table of commands, and an argument parser that returns a table.
Previous: [Chapter 4](04-functions.md). Next: [Chapter 6](06-strings.md).

## Arrays

A table maps keys to values. With keys 1, 2, 3, ... it works as an array. The constructor
`{ ... }` lists the items in order. **Indexes start at 1**, not 0.

`examples/ch05/arrays.lua`

```lua
-- An array is a table with keys 1, 2, 3, ... Indexes start at 1.
local colors = { "red", "green", "blue" }
print(colors[1], colors[3], colors[4])   -- a missing index is nil
print(#colors)                           -- the length

-- Append: the two common ways.
colors[#colors + 1] = "cyan"
table.insert(colors, "magenta")
print(table.concat(colors, ", "))

-- Insert and remove at a position: later items shift.
table.insert(colors, 1, "black")         -- at the front
local removed = table.remove(colors, 2)  -- returns the removed item
print(removed, table.concat(colors, ", "))
print(table.remove(colors))              -- no position: removes the last
print(#colors)

-- table.concat(t, sep, i, j) joins strings and numbers.
print(table.concat({ 1, 2, 3 }, "+", 2, 3))

-- unpack turns items into separate values.
print(unpack(colors))

-- Loop with a numeric for or with ipairs.
for i = 1, #colors do io.write(i, "=", colors[i], " ") end print()
for i, c in ipairs(colors) do io.write(i, "=", c, " ") end print()
```

```console
$ luajit examples/ch05/arrays.lua
red	blue	nil
3
red, green, blue, cyan, magenta
red	black, green, blue, cyan, magenta
magenta
4
2+3
black	green	blue	cyan
1=black 2=green 3=blue 4=cyan 
1=black 2=green 3=blue 4=cyan 
```

- Reading a missing index gives `nil`, not an error.
- `t[#t + 1] = v` and `table.insert(t, v)` both append.
- `table.insert(t, pos, v)` and `table.remove(t, pos)` shift the later items, which takes time
  proportional to the array's length.
- `table.remove(t)` removes and returns the last item. On an empty table it returns nothing, so
  `local v = table.remove(t)` gives `nil`.
- `table.concat` is the fast way to join many strings. It takes strings and numbers only; anything
  else is an error such as `invalid value (table) at index 2 in table for 'concat'`.
- `unpack(t)` returns the items as separate values. In LuaJIT it is a global, as in Lua 5.1. A
  standard build has no `table.unpack` or `table.pack`.

## Dictionaries

Any value except `nil` (and NaN) can be a key. A table with string keys is a dictionary (a map, a
hash).

`examples/ch05/dicts.lua`

```lua
-- A dictionary maps keys to values. Any value except nil (and NaN) can be a key.
local ages = { ada = 36, ["alan turing"] = 41 }
ages.grace = 85                      -- t.name is sugar for t["name"]
ages["linus"] = 28
print(ages.ada, ages["alan turing"], ages.grace)

-- t.x uses the literal NAME x. t[x] uses the VALUE of the variable x.
local key = "ada"
print(ages.key, ages[key])

-- Assigning nil removes a key. Reading a missing key gives nil.
ages.linus = nil
print(ages.linus)

-- Keys can be numbers, booleans, tables, functions...
local t = { [10] = "ten", [true] = "yes" }
t[print] = "the print function"
print(t[10], t[true], t[print])

-- Numbers are compared by value: 1 and 1.0 are the same key.
-- A string "1" is a different key from the number 1.
t[1] = "number one"
print(t[1.0], t["1"])

-- Test for emptiness with next(): it returns nil for an empty table.
print(next({}) == nil, next(t) ~= nil)
```

```console
$ luajit examples/ch05/dicts.lua
36	41	85
nil	36
nil
ten	yes	the print function
number one	nil
true	true
```

The most common table mistake is mixing up `t.x` and `t[x]`:

- `t.name` means `t["name"]`: the key is the string `"name"`. It only works when the key is a valid
  name (letters, digits, `_`, not a keyword).
- `t[name]` uses the **value** of the variable `name` as the key.
- In a constructor, `{ ada = 36 }` is short for `{ ["ada"] = 36 }`. Use brackets for keys that
  aren't names, such as `["alan turing"]` or `[10]`.

Other key rules:

- Number keys compare by value: `1` and `1.0` are the same key. The string `"1"` is a different key;
  Lua doesn't convert between them.
- `t[nil] = v` fails with `table index is nil`, and `t[0/0] = v` with `table index is NaN`. Reading
  `t[nil]` just gives `nil`.
- Assigning `nil` deletes the key. A table can't store `nil` as a value.
- `next(t)` returns some key and its value, or `nil` for an empty table. `next(t) == nil` is the
  standard emptiness test; `#t == 0` only works for arrays.

## Records, nested tables and mixed constructors

A table with fixed, named fields is a record (a struct). Values can be tables, so data nests to any
depth.

`examples/ch05/nested.lua`

```lua
-- Tables nest: a value can be another table.
local book = {
  title = "Programming in Lua",
  authors = { "Roberto Ierusalimschy" },
  edition = { number = 4, year = 2016 },
}
print(book.title, book.authors[1], book.edition.year)

-- A matrix is an array of arrays.
local grid = {
  { 1, 2, 3 },
  { 4, 5, 6 },
}
print(grid[2][3], #grid, #grid[1])

-- Constructors can mix array items and named fields.
-- Trailing commas are fine; ; works as a separator too.
local mixed = { "a", "b", n = 2; [10] = "x", }
print(mixed[1], mixed[2], mixed.n, mixed[10], #mixed)

-- Indexing a missing nested table is an error. (pcall: Chapter 9.)
print(pcall(function() return book.publisher.name end))
```

```console
$ luajit examples/ch05/nested.lua
Programming in Lua	Roberto Ierusalimschy	2016
6	2	3
a	b	2	x	2
false	examples/ch05/nested.lua:22: attempt to index field 'publisher' (a nil value)
```

- In a constructor, items without a key get 1, 2, 3, ... in order. Named and `[expr] = value`
  fields can go anywhere in between.
- Fields are separated by `,` or `;`. A trailing separator is allowed, which keeps diffs clean.
- `#mixed` counts only 1 and 2, not the named fields or `[10]`.
- `book.publisher` is `nil`, and indexing `nil` is an error; Lua names the field that was `nil`. For
  optional nested data, test each level: `book.publisher and book.publisher.name`.

## The length operator and holes

`#t` is the number of items **only if the table is a sequence**: keys 1 to n all set, no `nil`
between them. With holes, `#t` can return any *border*: an index n where `t[n]` is not `nil` and
`t[n + 1]` is `nil` (or 0 when `t[1]` is `nil`).

`examples/ch05/length.lua`

```lua
-- # is reliable only for a "sequence": keys 1..n, all non-nil.
local seq = { 10, 20, 30 }
print(#seq)

-- With holes, # returns ANY border: an index n where
-- t[n] ~= nil and t[n + 1] == nil (or 0 if t[1] == nil).
local holes = { 10, 20, 30 }
holes[2] = nil
print(#holes)                  -- 1 or 3 are both valid answers

local sparse = {}
sparse[1], sparse[2], sparse[4] = "a", "b", "d"
print(#sparse)                 -- 2 or 4

-- table.maxn returns the largest positive numeric key (slow: scans all keys).
print(table.maxn(sparse))

-- When nils are possible, store the count yourself.
local results = { n = 0 }
local function push(v)
  results.n = results.n + 1
  results[results.n] = v
end
push("x"); push(nil); push("z")
print(results.n, results[1], results[2], results[3])
```

```console
$ luajit examples/ch05/length.lua
3
1
4
4
3	x	nil	z
```

With holes, the result depends on how the table was built and changed. Another Lua implementation
or build may print different numbers, and both are correct. More cases from this LuaJIT:

| Table | `#t` |
|-------|------|
| `{ 1, 2, nil, 4 }` | 4 |
| `{ nil, nil, 3 }` | 3 |
| `{ 1, 2, 3, 4 }`, then `t[2] = nil` | 4 |

So: **don't put `nil` in arrays.** For "no value" in a list, use a marker such as `false`, or keep
the count in a field like `results.n`. `table.maxn(t)` scans every key for the largest positive
number: correct but slow.

Strings have a length too: `#"abc"` is 3 (bytes, not characters; see [Chapter 6](06-strings.md)).

## Iterating: `ipairs` and `pairs`

The generic `for` has two built-in iterators:

- `ipairs(t)` visits `t[1]`, `t[2]`, ... **in order** and stops at the first `nil`.
- `pairs(t)` visits **every** key, array part included, **in no particular order**.

`examples/ch05/iterate.lua`

```lua
local t = { "a", "b", nil, "d", x = 1, y = 2 }

-- ipairs: 1, 2, 3, ... in order, stopping at the first nil.
for i, v in ipairs(t) do io.write(i, "=", v, " ") end print()

-- pairs: every key, in an unspecified order.
local keys = {}
for k, v in pairs(t) do keys[#keys + 1] = tostring(k) end
print(#keys .. " keys: " .. table.concat(keys, " "))

-- For a stable order, collect the keys and sort them.
local scores = { carol = 7, alice = 9, bob = 8 }
local names = {}
for name in pairs(scores) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do print(name, scores[name]) end

-- While iterating with pairs you may change or clear (set to nil)
-- existing fields, but never add new ones.
for name in pairs(scores) do
  if scores[name] < 9 then scores[name] = nil end
end
print(next(scores))
```

```console
$ luajit examples/ch05/iterate.lua
1=a 2=b 
5 keys: 1 2 4 x y
alice	9
bob	8
carol	7
alice	9
```

- `ipairs` stopped at index 3 (the `nil`) and never reached `"d"`. `pairs` found `4`.
- The language doesn't define the order of `pairs`. It can change when the table changes, with
  another Lua version, or even between two runs of the same script (`x y` or `y x` above). Never
  depend on it. When order matters, collect the keys into an array and sort it, as with `names`.
- During a `pairs` loop you may change existing fields or clear them (set them to `nil`). Adding a
  **new** key is undefined behavior: keys may be skipped or visited twice. Collect new keys in
  another table and add them after the loop.
- `for i = 1, #t do` is the numeric alternative to `ipairs`. It doesn't stop at a hole, but `#t`
  is unreliable with holes.

## Sorting

`table.sort(t)` sorts an array in place with `<`. To change the order, pass `comp(a, b)`, which
returns `true` when `a` must come **before** `b`.

`examples/ch05/sort.lua`

```lua
local nums = { 5, 2, 8, 1 }
table.sort(nums)                       -- ascending, with <
print(table.concat(nums, " "))

table.sort(nums, function(a, b) return a > b end)
print(table.concat(nums, " "))         -- descending

-- Sort records by one field, then by another.
local people = {
  { name = "carol", age = 30 },
  { name = "alice", age = 30 },
  { name = "bob", age = 25 },
}
table.sort(people, function(a, b)
  if a.age ~= b.age then
    return a.age < b.age
  end
  return a.name < b.name
end)
for _, p in ipairs(people) do print(p.age, p.name) end

-- Strings sort byte by byte: upper case before lower case.
local words = { "banana", "apple", "Cherry" }
table.sort(words)
print(table.concat(words, " "))
table.sort(words, function(a, b) return a:lower() < b:lower() end)
print(table.concat(words, " "))
```

```console
$ luajit examples/ch05/sort.lua
1 2 5 8
8 5 2 1
25	bob
30	alice
30	carol
Cherry apple banana
apple banana Cherry
```

- To sort by several fields, compare the first; only when equal, compare the next.
- Strings compare byte by byte, so `"C"` (67) comes before `"a"` (97). Compare `a:lower()` for a
  case-insensitive order (a string method; see [Chapter 6](06-strings.md)).
- All items must be comparable. Sorting a mix of numbers and strings fails with an error such as
  `attempt to compare number with string`.
- `table.sort` is not stable: equal items can end up in any order. Add a tie-breaker field if their
  order matters.

The comparator must be a strict order, returning `false` for equal items. `<=` breaks that rule,
and `table.sort` can fail:

`examples/ch05/badsort.lua`

```lua
-- A comparator must be a strict "less than": false for equal items.
-- Using <= breaks that rule. With repeated values, sort can fail.
local t = {}
for i = 1, 20 do t[i] = 5 end
table.sort(t, function(a, b) return a <= b end)
```

```console
$ luajit examples/ch05/badsort.lua
luajit: examples/ch05/badsort.lua:5: invalid order function for sorting
stack traceback:
	[C]: in function 'sort'
	examples/ch05/badsort.lua:5: in main chunk
	[C]: at 0x59c0526803a0
```

The address on the last line changes from run to run. With other data, a bad comparator may raise
no error and silently give a wrong order, which is worse.

## Sets

A set stores each element as a **key** with the value `true`. Membership is then one table lookup
instead of a loop over an array.

`examples/ch05/sets.lua`

```lua
-- A set: the elements are keys, the values are just `true`.
local function Set(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end

local keywords = Set{ "and", "break", "do", "else", "end" }
print(keywords["do"], keywords["while"])   -- membership is one lookup

local function union(a, b)
  local out = {}
  for k in pairs(a) do out[k] = true end
  for k in pairs(b) do out[k] = true end
  return out
end

local function to_sorted_list(s)
  local list = {}
  for k in pairs(s) do list[#list + 1] = k end
  table.sort(list)
  return list
end

local u = union(Set{ "x", "y" }, Set{ "y", "z" })
print(table.concat(to_sorted_list(u), " "))

-- Remove duplicates while keeping the first-seen order.
local seen, unique = {}, {}
for _, w in ipairs({ "b", "a", "b", "c", "a" }) do
  if not seen[w] then
    seen[w] = true
    unique[#unique + 1] = w
  end
end
print(table.concat(unique, " "))
```

```console
$ luajit examples/ch05/sets.lua
true	nil
x y z
b a c
```

`Set{ ... }` is a function call. When the only argument is a table constructor or a string literal,
the parentheses can be dropped: `f{ ... }` means `f({ ... })`, and `f"text"` means `f("text")`.

## Stacks and queues

An array is already a stack. A queue needs more work, because `table.remove(q, 1)` moves every
other item.

`examples/ch05/stackqueue.lua`

```lua
-- A stack: push and pop at the end. Both are O(1).
local stack = {}
table.insert(stack, "a")
table.insert(stack, "b")
stack[#stack + 1] = "c"
print(table.remove(stack), table.remove(stack), #stack)

-- A queue: table.remove(q, 1) shifts every item (O(n)).
-- Two indexes make both ends O(1).
local queue = { first = 1, last = 0 }

local function push(q, v)
  q.last = q.last + 1
  q[q.last] = v
end

local function pop(q)
  if q.first > q.last then
    return nil                   -- empty
  end
  local v = q[q.first]
  q[q.first] = nil               -- let the item be garbage collected
  q.first = q.first + 1
  return v
end

push(queue, "job1"); push(queue, "job2"); push(queue, "job3")
print(pop(queue), pop(queue))
push(queue, "job4")
print(pop(queue), pop(queue), pop(queue))
```

```console
$ luajit examples/ch05/stackqueue.lua
c	b	1
job1	job2
job3	job4	nil
```

The queue keeps two indexes: pushing grows `last`, popping grows `first`, and the items live at
`q[first]` to `q[last]`. Nothing shifts, so both operations take constant time. `first` and `last`
share the table with the items, which is fine: the items use number keys, the indexes string keys.

## References, identity and copying

A table is an object. A variable holds a **reference** to it, and assigning or passing a table
never copies it.

`examples/ch05/references.lua`

```lua
-- Variables hold REFERENCES to tables. Assignment doesn't copy.
local a = { 1, 2, 3 }
local b = a
b[1] = 100
print(a[1], a == b)

-- Two tables with the same contents are still different tables.
print({ 1 } == { 1 })

-- Functions receive references too, so they can change the caller's table.
local function clear_first(t) t[1] = nil end
clear_first(a)
print(a[1])

-- A shallow copy copies the top level only.
local function shallow_copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- A deep copy copies nested tables too. `seen` handles shared and cyclic tables.
local function deep_copy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local out = {}
  seen[t] = out
  for k, v in pairs(t) do
    out[deep_copy(k, seen)] = deep_copy(v, seen)
  end
  return out
end

local original = { name = "x", tags = { "a", "b" } }
original.self = original         -- a cycle
local s = shallow_copy(original)
local d = deep_copy(original)
original.tags[1] = "CHANGED"
print(s.tags[1], d.tags[1])      -- the shallow copy shares `tags`
print(d.self == d, d.self == original)
```

```console
$ luajit examples/ch05/references.lua
100	true
false
nil
CHANGED	a
true	false
```

- `a == b` is true only if both refer to the **same** table. Separate tables with the same contents
  are not equal. (Chapter 7 changes that with `__eq`.)
- A function that receives a table can change it, and the caller sees the change.
- A **shallow copy** makes a new top-level table, but nested tables are shared: `s.tags` is the
  same table as `original.tags`.
- A **deep copy** copies nested tables too. `seen` maps each original table to its copy, so cycles
  (`original.self = original`) and shared sub-tables work instead of looping forever. Keys can be
  tables, so keys are copied as well.
- Neither copy handles metatables or functions' upvalues. For plain data, this is enough.

## Tables as data: records, config and small DSLs

A table constructor is a readable data format. Lua began as a language for describing data, and
this is still a strength: a config file can simply be a Lua file.

`examples/ch05/datadesc.lua`

```lua
-- Tables plus the f{...} call syntax make a data description language.
-- This file could be written by a user, as a config or data file.
local books = {}

local function Book(fields)
  assert(fields.title, "a book needs a title")  -- assert: Chapter 9
  fields.tags = fields.tags or {}
  books[#books + 1] = fields
end

Book{ title = "Programming in Lua", year = 2016, tags = { "lua" } }
Book{ title = "The C Programming Language", year = 1988, tags = { "c", "classic" } }
Book{ title = "SICP", year = 1985 }

for _, b in ipairs(books) do
  print(b.year, b.title, "[" .. table.concat(b.tags, ",") .. "]")
end

-- A plain table works as a record of settings, with defaults.
local defaults = { width = 80, color = "auto", limit = 20 }
local user = { color = "never" }
local settings = {}
for k, v in pairs(defaults) do settings[k] = v end
for k, v in pairs(user) do settings[k] = v end
print(settings.width, settings.color, settings.limit)
```

```console
$ luajit examples/ch05/datadesc.lua
2016	Programming in Lua	[lua]
1988	The C Programming Language	[c,classic]
1985	SICP	[]
80	never	20
```

- `Book{ ... }` reads like a declaration but is just a call to `Book` with a table. The function
  can check fields, fill in defaults and store the record.
- `assert(cond, message)` raises an error with `message` when `cond` is false or `nil`
  ([Chapter 9](09-errors.md)).
- Defaults: copy the default table, then copy the user's values over it.
- Loading such a file as a config, in a restricted environment, comes in
  [Chapter 8](08-modules.md).

## LuaJIT extras: `table.new` and `table.clear`

A growing table allocates a bigger block and moves its items. If you know the final size, LuaJIT can
allocate once. These two LuaJIT extensions aren't loaded by default; `require` makes them available
([Chapter 8](08-modules.md)).

`examples/ch05/tablenew.lua`

```lua
-- LuaJIT extensions: pre-sized tables and clearing in place.
-- require loads a library (Chapter 8); these two add table.new/table.clear.
require("table.new")
require("table.clear")

-- table.new(narray, nhash) reserves room, so the table never has to grow.
local squares = table.new(1000, 0)
for i = 1, 1000 do squares[i] = i * i end
print(#squares, squares[1000])

-- table.clear removes every key but keeps the allocated room for reuse.
table.clear(squares)
print(#squares, next(squares))
```

```console
$ luajit examples/ch05/tablenew.lua
1000	1000000
0	nil
```

- `table.new(narray, nhash)` creates an empty table with room for `narray` array items and `nhash`
  other keys, like the C function `lua_createtable`.
- `table.clear(t)` removes all keys but keeps the memory for refilling without new allocations.
  Every reference to `t` sees the empty table.
- Both matter only for big tables in hot code; most code should just use `{}`. Code that must also
  run on plain Lua can't use them.

## Building stash: tables everywhere

So far `stash` stored nothing and parsed arguments by hand. Tables fix both, and most of
`stash.lua` is rewritten:

| Piece | Concept |
|-------|---------|
| `entries` | an array of records; each record has a nested `tags` array |
| `find_entry(id)` | `ipairs` and a linear search; returns the entry and its position |
| `parse_args(args, first, spec)` | a spec table in, an options table out |
| `commands` | a dispatch table: command name → record with `usage`, `options` and `run` |
| `order` | an array that fixes the order of the help text |
| `tags` | a dictionary of counts, then an array sorted with a comparator |
| `main(args)` | looks up the command with `commands[name]` instead of an `if` chain |

The bookmarks live only in memory. Every run starts with the same three sample entries, and
**changes are lost when the process ends**: `add` and `rm` work, but the next run forgets them.
Saving to a file comes in [Chapter 12](12-io-and-os.md).

`search` is gone until [Chapter 6](06-strings.md) brings string searching. Replace `stash.lua` with
the code below, shown in four parts; put them one after the other in a single file.

### Part 1: the store

`stash.lua`

```lua
#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 5: tables everywhere. The commands live in a table, parsed
-- options come back as a table, and the bookmarks are a table of tables.

local VERSION = "0.1.0"

---------------------------------------------------------------------------
-- The store: an array of entries, each entry a record-like table.
-- Nothing is saved yet (files arrive in Chapter 12), so every run starts
-- from these sample entries.
---------------------------------------------------------------------------

local entries = {
  { id = 1, url = "https://www.lua.org/", title = "The Programming Language Lua",
    tags = { "lang", "lua" }, note = "official site" },
  { id = 2, url = "https://luajit.org/", title = "LuaJIT",
    tags = { "jit", "lua" }, note = "" },
  { id = 3, url = "https://sqlite.org/fts5.html", title = "SQLite FTS5 Extension",
    tags = { "db", "search" }, note = "full-text search" },
}
local next_id = #entries + 1

-- Returns the entry with this id and its position in `entries`, or nil.
local function find_entry(id)
  for i, entry in ipairs(entries) do
    if entry.id == id then
      return entry, i
    end
  end
  return nil
end

local function has_tag(entry, tag)
  for _, t in ipairs(entry.tags) do
    if t == tag then
      return true
    end
  end
  return false
end
```

Each entry is a record with fields `id`, `url`, `title`, `tags` (a nested array) and `note`.
`next_id` starts after the last sample entry. `find_entry` returns the entry and its index, because
`rm` needs the index for `table.remove`, or `nil` when nothing matches. For new entries the title is
just the URL; [Chapter 6](06-strings.md) derives a title from it.

### Part 2: the argument parser

`stash.lua` (continued)

```lua

---------------------------------------------------------------------------
-- Argument parsing
---------------------------------------------------------------------------

local function fail(message)
  print("stash: " .. message)
end

-- Parses args[first], args[first+1], ... using a spec that maps each flag
-- to { field, kind }. Kinds: "flag" (no value), "value", "number", "list"
-- (may repeat). Returns an options table: named fields for flags, and the
-- remaining (positional) arguments at 1, 2, 3...
-- On a bad argument it returns nil plus a message.
local function parse_args(args, first, spec)
  local opts = {}
  local i = first
  while i <= #args do
    local a = args[i]
    local option = spec[a]
    if option == nil then
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
          table.insert(opts[field], value)
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

`fail` now takes one message. In the parser, each command describes its options in a **spec**
table. The spec for `add` is:

```lua
{ ["-t"] = { "tags", "list" }, ["-n"] = { "note", "value" } }
```

The keys are flags. Each value is a small array: the field to store the result in, and the kind of
option. `spec[a]` looks up the current argument in one step. A non-flag argument is positional and
goes to the array part of `opts`. So for
`add https://www.lua.org/pil/ -t book -t lua -n "Programming in Lua"`, `parse_args` returns:

```lua
{ "https://www.lua.org/pil/", tags = { "book", "lua" }, note = "Programming in Lua" }
```

One table holds the positional arguments (`opts[1]`) and the named options (`opts.tags`). Errors
return `nil` plus a message, a common Lua convention ([Chapter 9](09-errors.md)).

`parse_args` reads `args[i]` and `#args`, which is safe on the global `arg` table: a proper
sequence from 1 to the number of arguments.

### Part 3: the commands

`stash.lua` (continued)

```lua

---------------------------------------------------------------------------
-- Commands: a dispatch table from name to a record describing the command.
---------------------------------------------------------------------------

local commands = {}

-- Help lists the commands in this order (pairs() would give no fixed order).
local order = { "add", "list", "show", "rm", "tags", "help", "version" }

commands.add = {
  usage = "add URL [-t TAG]... [-n NOTE]   save a bookmark",
  options = { ["-t"] = { "tags", "list" }, ["-n"] = { "note", "value" } },
  run = function(opts)
    local url = opts[1]
    if url == nil then
      return fail("add: missing URL")
    end
    local tags = opts.tags or {}
    table.sort(tags)
    local entry = { id = next_id, url = url, title = url, tags = tags, note = opts.note or "" }
    next_id = next_id + 1
    entries[#entries + 1] = entry
    print("added " .. entry.id .. ": " .. entry.title)
  end,
}

commands.list = {
  usage = "list [-t TAG] [--limit N]       list bookmarks",
  options = { ["-t"] = { "tag", "value" }, ["--limit"] = { "limit", "number" } },
  run = function(opts)
    local shown = 0
    for _, entry in ipairs(entries) do
      if opts.limit and shown >= opts.limit then
        break
      end
      if opts.tag == nil or has_tag(entry, opts.tag) then
        print(entry.id .. "  " .. entry.title .. "  [" .. table.concat(entry.tags, ",") .. "]")
        shown = shown + 1
      end
    end
  end,
}

commands.show = {
  usage = "show ID                         show one bookmark",
  options = {},
  run = function(opts)
    local id = tonumber(opts[1])
    if id == nil then
      return fail("show: missing or bad ID")
    end
    local entry = find_entry(id)
    if entry == nil then
      return fail("no entry with id " .. id)
    end
    print("id:    " .. entry.id)
    print("title: " .. entry.title)
    print("url:   " .. entry.url)
    print("tags:  " .. table.concat(entry.tags, ", "))
    if entry.note ~= "" then
      print("note:  " .. entry.note)
    end
  end,
}

commands.rm = {
  usage = "rm ID                           delete a bookmark",
  options = {},
  run = function(opts)
    local id = tonumber(opts[1])
    if id == nil then
      return fail("rm: missing or bad ID")
    end
    local entry, index = find_entry(id)
    if entry == nil then
      return fail("no entry with id " .. id)
    end
    table.remove(entries, index)
    print("removed " .. id .. ": " .. entry.title)
  end,
}

commands.tags = {
  usage = "tags                            count bookmarks per tag",
  options = {},
  run = function()
    -- A dictionary from tag to count...
    local counts = {}
    for _, entry in ipairs(entries) do
      for _, tag in ipairs(entry.tags) do
        counts[tag] = (counts[tag] or 0) + 1
      end
    end
    -- ...turned into an array so it can be sorted: most used first, then by name.
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
    for _, row in ipairs(rows) do
      print(row.tag .. " (" .. row.count .. ")")
    end
  end,
}

commands.help = {
  usage = "help                            show this help",
  options = {},
  run = function()
    print("usage: stash <command> [arguments]")
    print()
    print("commands:")
    for _, name in ipairs(order) do
      print("  " .. commands[name].usage)
    end
  end,
}

commands.version = {
  usage = "version                         print the version",
  options = {},
  run = function()
    print("stash " .. VERSION)
  end,
}
```

`commands` is a **dispatch table**: `commands[name]` finds the command record, and
`record.run(opts)` runs it. A new command is one new entry, not another `if` branch. The record
also holds the help line and the option spec, so everything about a command is in one place.

Things to notice:

- `commands.add = { ... }` is the same as `commands["add"] = { ... }`. The `run` fields hold
  anonymous functions.
- `help` loops over `order`, not `commands`; `pairs(commands)` would give an unpredictable order.
- `add` sorts its tags, so `-t lua -t book` and `-t book -t lua` store the same entry.
  `opts.tags or {}` gives a fresh empty array when no `-t` was given.
- `list` uses `ipairs` to keep the entries in order. `opts.limit and shown >= opts.limit` compares
  only when a limit was given.
- `show` prints the note only when there is one.
- `rm` passes the index from `find_entry` to `table.remove`, which shifts later entries down.
- `tags` uses the usual two steps: count into a dictionary
  (`counts[tag] = (counts[tag] or 0) + 1`), then copy the counts into an array of records and sort
  it. Most used tags come first; ties sort by name.
- `help`'s `run` can use `commands[name]` because `commands` is an upvalue, fully built by the time
  `run` is called.

### Part 4: main

`stash.lua` (continued)

```lua

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------

local function main(args)
  local name = args[1]
  if name == nil or name == "-h" or name == "--help" then
    name = "help"
  elseif name == "--version" then
    name = "version"
  end

  local command = commands[name]
  if command == nil then
    return fail("unknown command '" .. name .. "' (try 'stash help')")
  end
  local opts, err = parse_args(args, 2, command.options)
  if opts == nil then
    return fail(name .. ": " .. err)
  end
  command.run(opts)
end

main(arg)
```

`main` receives the `arg` table. The command name is always `args[1]`; parsing starts at `args[2]`.
Unknown commands and option errors go through `fail`.

One change in behavior: `-h`, `--help` and `--version` now work **only as the first argument**.
`stash --version` prints the version, but `stash list --version` treats `--version` as positional
and just lists the entries. (Chapter 4's `scan` found them anywhere.) Many tools with subcommands,
such as `git`, work this way: global options go before the command.

### Checkpoint

```console
$ luajit stash.lua help
usage: stash <command> [arguments]

commands:
  add URL [-t TAG]... [-n NOTE]   save a bookmark
  list [-t TAG] [--limit N]       list bookmarks
  show ID                         show one bookmark
  rm ID                           delete a bookmark
  tags                            count bookmarks per tag
  help                            show this help
  version                         print the version
$ luajit stash.lua list
1  The Programming Language Lua  [lang,lua]
2  LuaJIT  [jit,lua]
3  SQLite FTS5 Extension  [db,search]
$ luajit stash.lua list -t lua --limit 1
1  The Programming Language Lua  [lang,lua]
$ luajit stash.lua show 3
id:    3
title: SQLite FTS5 Extension
url:   https://sqlite.org/fts5.html
tags:  db, search
note:  full-text search
$ luajit stash.lua show 9
stash: no entry with id 9
$ luajit stash.lua tags
lua (2)
db (1)
jit (1)
lang (1)
search (1)
$ luajit stash.lua add https://www.lua.org/pil/ -t book -t lua -n "Programming in Lua"
added 4: https://www.lua.org/pil/
$ luajit stash.lua rm 2
removed 2: LuaJIT
$ luajit stash.lua list --limit
stash: list: --limit needs a value
```

Each command is a separate run that starts from the three samples, so neither the added bookmark
nor the removal shows up in a later `list`.

The complete project at this point is in `project/ch05/`.

## Summary

- Tables are the only data structure: array, dictionary, record, set and queue.
- Arrays start at index 1. Append with `t[#t + 1] = v` or `table.insert(t, v)`.
- `t.x` is `t["x"]`. `t[x]` uses the value of `x`. `nil` and NaN can't be keys; assigning `nil`
  deletes a key.
- `#t` is reliable only for sequences. With holes it returns any border. Don't store `nil` in
  arrays; keep a count if you must.
- `ipairs` goes 1, 2, 3, ... and stops at `nil`. `pairs` visits every key in an undefined order.
  Don't add keys during `pairs`.
- `table.sort(t, comp)`: `comp(a, b)` returns true if `a` goes first. It must be strict: never `<=`.
- Sets use elements as keys. Queues use two indexes.
- Tables are passed by reference. `==` compares identity. Copy explicitly, shallow or deep.
- `f{ ... }` calls `f` with one table; it makes data description easy.
- `require("table.new")` and `require("table.clear")` add LuaJIT's pre-sizing and clearing.

## Exercises

1. Write `invert(t)` that returns a new table with the keys and values swapped. What happens with
   `invert({ "red", "green", "blue" })`? Then invert the result again.

<details><summary>Solution</summary>

```lua
local function invert(t)
  local out = {}
  for k, v in pairs(t) do
    out[v] = k
  end
  return out
end

local codes = invert({ "red", "green", "blue" })
print(codes.red, codes.green, codes.blue)
local back = invert(codes)
print(back[1], back[2], back[3])
```

```console
$ luajit invert.lua
1	2	3
red	green	blue
```

Inverting an array gives a lookup table from value to index. If two keys share a value, one is
lost, because a key can appear only once.

</details>

2. Write `deep_equal(a, b)` that returns `true` when two values have the same contents, comparing
   nested tables recursively.

<details><summary>Solution</summary>

```lua
local function deep_equal(a, b)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  for k, v in pairs(a) do
    if not deep_equal(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

print(deep_equal({ 1, { 2, 3 }, x = "y" }, { 1, { 2, 3 }, x = "y" }))
print(deep_equal({ 1, 2 }, { 1, 2, 3 }))
print(deep_equal({ a = { b = 1 } }, { a = { b = 2 } }))
print(deep_equal("x", "x"), deep_equal(1, "1"))
```

```console
$ luajit deq.lua
true
false
false
true	false
```

The first loop checks that every key of `a` has an equal value in `b`. The second catches keys only
in `b`; without it, `{ 1, 2 }` would equal `{ 1, 2, 3 }`. (Cyclic tables would loop forever; a
`seen` table as in `deep_copy` fixes that.)

</details>

3. `stash`: add a `-r` flag to `list` that lists the entries in reverse order. It must still work
   with `-t` and `--limit`.

<details><summary>Solution</summary>

Replace `commands.list` in `stash.lua`:

```lua
commands.list = {
  usage = "list [-t TAG] [--limit N] [-r]  list bookmarks",
  options = {
    ["-t"] = { "tag", "value" },
    ["--limit"] = { "limit", "number" },
    ["-r"] = { "reverse", "flag" },
  },
  run = function(opts)
    local shown = 0
    local first, last, step = 1, #entries, 1
    if opts.reverse then
      first, last, step = #entries, 1, -1
    end
    for i = first, last, step do
      local entry = entries[i]
      if opts.limit and shown >= opts.limit then
        break
      end
      if opts.tag == nil or has_tag(entry, opts.tag) then
        print(entry.id .. "  " .. entry.title .. "  [" .. table.concat(entry.tags, ",") .. "]")
        shown = shown + 1
      end
    end
  end,
}
```

```console
$ luajit stash.lua list -r
3  SQLite FTS5 Extension  [db,search]
2  LuaJIT  [jit,lua]
1  The Programming Language Lua  [lang,lua]
$ luajit stash.lua list -r --limit 2 -t lua
2  LuaJIT  [jit,lua]
1  The Programming Language Lua  [lang,lua]
```

`parse_args` already supports the `"flag"` kind, so the new option is one spec line. A numeric
`for` with step -1 walks the array backwards.

</details>

4. `stash`: let `rm` take several ids, as in `stash rm 3 1`. Report each id that doesn't exist, but
   keep going with the others.

<details><summary>Solution</summary>

```lua
commands.rm = {
  usage = "rm ID...                        delete bookmarks",
  options = {},
  run = function(opts)
    if #opts == 0 then
      return fail("rm: missing ID")
    end
    for _, text in ipairs(opts) do
      local id = tonumber(text)
      local entry, index = find_entry(id)
      if entry == nil then
        fail("no entry with id " .. text)
      else
        table.remove(entries, index)
        print("removed " .. id .. ": " .. entry.title)
      end
    end
  end,
}
```

```console
$ luajit stash.lua rm 3 x 1
removed 3: SQLite FTS5 Extension
stash: no entry with id x
removed 1: The Programming Language Lua
$ luajit stash.lua rm
stash: rm: missing ID
```

The ids are in the array part of `opts`, so `#opts` counts them and `ipairs` walks them.
`tonumber("x")` is `nil` and `find_entry(nil)` matches nothing, so a bad id gets the same message
as a missing one.

</details>

5. Write a function `group_by_tag(entries)` that returns a dictionary from each tag to an array of
   entry titles. Print it with the tags in sorted order. Use the three sample entries from `stash`.

<details><summary>Solution</summary>

```lua
local entries = {
  { title = "The Programming Language Lua", tags = { "lang", "lua" } },
  { title = "LuaJIT", tags = { "jit", "lua" } },
  { title = "SQLite FTS5 Extension", tags = { "db", "search" } },
}

local function group_by_tag(list)
  local groups = {}
  for _, entry in ipairs(list) do
    for _, tag in ipairs(entry.tags) do
      groups[tag] = groups[tag] or {}
      table.insert(groups[tag], entry.title)
    end
  end
  return groups
end

local groups = group_by_tag(entries)
local tags = {}
for tag in pairs(groups) do tags[#tags + 1] = tag end
table.sort(tags)
for _, tag in ipairs(tags) do
  print(tag .. ": " .. table.concat(groups[tag], "; "))
end
```

```console
$ luajit group.lua
db: SQLite FTS5 Extension
jit: LuaJIT
lang: The Programming Language Lua
lua: The Programming Language Lua; LuaJIT
search: SQLite FTS5 Extension
```

`groups[tag] = groups[tag] or {}` creates each inner array the first time a tag is seen, a common
"get or create" idiom.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-5--tables)
