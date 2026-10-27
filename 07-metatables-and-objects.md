# Chapter 7 — Metatables and Objects

Lua has no classes, operator overloading or properties; one mechanism, the **metatable**, gives
you all of them. This chapter explains metatables, then builds classes, inheritance, read-only
tables, default values, strict globals and caches. In the project, bookmarks become
`Entry` objects inside a `MemoryStore` object. After strings ([Chapter 6](06-strings.md)) comes
splitting `stash` into modules ([Chapter 8](08-modules.md)).

## What a metatable is

A **metatable** is an ordinary table attached to another table. When Lua can't do an operation
alone (read a missing key, add two tables, call a table), it looks in the metatable for a
**metamethod**, a field such as `__index` or `__add`, calls it, and uses its result.

- `setmetatable(t, mt)` attaches `mt` to `t` and returns `t`.
- `getmetatable(t)` returns the metatable, or `nil`.

This is "mechanisms, not policies" ([Chapter 1](01-getting-started.md)): Lua gives you a hook, not
objects or classes; you build the policy.

Lua code can only set the metatable of a **table**. Strings share one metatable (its `__index` is
`string`, which makes `s:upper()` work). Other types have none by default.

## `__index`: missing keys

When you read `t[k]` and `t` has no key `k`, Lua checks the metatable's `__index`:

- A **table**: Lua looks up `k` there (and follows that table's own `__index`, and so on).
- A **function**: Lua returns `__index(t, k)`.

Keys that exist in `t` never trigger `__index`.

`examples/ch07/metatable.lua`

```lua
-- A metatable changes how a table behaves. Here: missing keys get defaults.
local defaults = { color = "auto", width = 80 }
local settings = { width = 120 }

print(settings.color)                      -- nil: no metatable yet
setmetatable(settings, { __index = defaults })
print(settings.color, settings.width)      -- auto 120
print(rawget(settings, "color"))           -- nil: the table itself has no color
print(getmetatable(settings).__index == defaults)
print(getmetatable({}))                    -- a plain table has no metatable
```

```console
$ luajit examples/ch07/metatable.lua
nil
auto	120
nil
true
nil
```

`rawget(t, k)` reads **without** metamethods: `settings` has no `color` of its own; it comes from
`defaults`, which can cheaply serve many tables.

A function `__index` can compute, load or cache values:

`examples/ch07/index_function.lua`

```lua
-- __index can be a function: it runs for every missing key.
local squares = setmetatable({}, {
  __index = function(t, n)
    print("  computing " .. n)
    local value = n * n
    rawset(t, n, value)          -- cache it: next time the key exists
    return value
  end,
})

print(squares[12])
print(squares[12])               -- cached: __index is not called again

-- A default value for every missing key.
local counts = setmetatable({}, { __index = function() return 0 end })
for _, word in ipairs({ "a", "b", "a" }) do
  counts[word] = counts[word] + 1
end
print(counts.a, counts.b, counts.zzz)
```

```console
$ luajit examples/ch07/index_function.lua
  computing 12
144
144
2	1	0
```

`rawset(t, k, v)` stores without metamethods. Once stored, the key is real and the next lookup
skips `__index`. The second table is the **default value** pattern: missing keys read as `0`, so
counting needs no `or 0`.

## `__newindex`: new keys

Assigning `t[k] = v` when `t` has **no** key `k` calls `__newindex(t, k, v)` instead of storing.
Existing keys are stored normally. If `__newindex` is a table, the value goes there.

`examples/ch07/newindex.lua`

```lua
-- __newindex runs when you assign to a key the table does NOT have.
local log = {}
local t = setmetatable({}, {
  __newindex = function(tbl, key, value)
    log[#log + 1] = ("set %s = %s"):format(tostring(key), tostring(value))
    rawset(tbl, key, value)      -- store it for real (t[key] = value would recurse)
  end,
})

t.x = 1        -- new key: logged
t.x = 2        -- key exists now: plain assignment, not logged
t.y = 3        -- new key: logged
print(t.x, t.y)
print(table.concat(log, "; "))

-- __newindex can also be a table: new keys go THERE instead.
local store = {}
local front = setmetatable({}, { __newindex = store })
front.a = 10
print(rawget(front, "a"), store.a)
```

```console
$ luajit examples/ch07/newindex.lua
2	3
set x = 1; set y = 3
nil	10
```

Inside `__newindex`, store with `rawset`. `t[key] = value` would call `__newindex` again, until
the stack overflows.

`rawequal(a, b)` compares without `__eq` (next section). Lua 5.1 has no `rawlen` (added in 5.2).

## Operators

Metamethods define operators on tables:

| Metamethod | Operator | Notes |
|------------|----------|-------|
| `__add` `__sub` `__mul` `__div` `__mod` `__pow` | `+ - * / % ^` | Used if either operand is a table with it. |
| `__unm` | unary `-` | |
| `__concat` | `..` | Used if either operand isn't a string or number. |
| `__eq` | `==`, `~=` | Only when **both** are tables with the **same** `__eq`. |
| `__lt` | `<`, `>` | `a > b` is evaluated as `b < a`. |
| `__le` | `<=`, `>=` | Without `__le`, Lua tries `not (b < a)` with `__lt`. |
| `__call` | `t(...)` | Makes the table callable: `__call(t, ...)`. |
| `__tostring` | `tostring(t)`, `print(t)` | Must return a string. |

`examples/ch07/vector.lua`

```lua
-- Operators on tables: arithmetic, comparison, tostring, concat, call.
local Vec = {}
Vec.__index = Vec

local function vec(x, y)
  return setmetatable({ x = x, y = y }, Vec)
end

Vec.__add = function(a, b) return vec(a.x + b.x, a.y + b.y) end
Vec.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y) end
Vec.__mul = function(a, b)                 -- number * vec or vec * number
  if type(a) == "number" then return vec(a * b.x, a * b.y) end
  return vec(a.x * b, a.y * b)
end
Vec.__unm = function(a) return vec(-a.x, -a.y) end
Vec.__eq = function(a, b) return a.x == b.x and a.y == b.y end
Vec.__lt = function(a, b) return a:length() < b:length() end
Vec.__le = function(a, b) return a:length() <= b:length() end
Vec.__tostring = function(a) return ("(%g, %g)"):format(a.x, a.y) end
Vec.__concat = function(a, b) return tostring(a) .. tostring(b) end
Vec.__call = function(a, f) return vec(f(a.x), f(a.y)) end

function Vec:length()
  return math.sqrt(self.x ^ 2 + self.y ^ 2)
end

local a, b = vec(1, 2), vec(3, 4)
print(tostring(a + b), tostring(a - b), tostring(2 * a), tostring(-a))
print(a == vec(1, 2), a ~= b, rawequal(a, vec(1, 2)))
print(a < b, a <= b, a > b)               -- a > b is b < a
print("a is " .. a, a .. b)
print(tostring(b(math.sqrt)))             -- __call: the table is callable
print(b:length())
```

```console
$ luajit examples/ch07/vector.lua
(4, 6)	(-2, -2)	(2, 4)	(-1, -2)
true	true	false
true	true	false
a is (1, 2)	(1, 2)(3, 4)
(1.73205, 2)
5
```

Notice:

- `2 * a` works: Lua tries the left operand's metamethod, then the right's. `__mul` gets the
  operands in their original order, so it checks which is the number.
- `a == vec(1, 2)` is `true` through `__eq`; `rawequal` says they are different tables.
- `__eq` runs only between two tables with the same `__eq`. A table never equals a number, and
  `{} == {}` is always `false`.
- `__lt` and `__le` run only when both operands are tables (with the same metamethod). Mixed types
  are an error: `vec(1, 2) < 1` gives `attempt to compare table with number`.
- `~=` is `not ==`; `>` swaps operands and uses `<`. There is no `__ne` or `__gt`.

Without metamethods these are errors: `attempt to perform arithmetic on a table value`,
`attempt to compare two table values`, `attempt to concatenate a table value`.

## Classes

A **class** in Lua is a pattern, not a feature:

1. A table `Account` holds the methods.
2. Set `Account.__index = Account`.
3. A constructor makes a table with `Account` as its metatable.

Objects hold only their data. Method lookups miss in the object and go through `__index` to the
class, so all objects share each method.

`examples/ch07/class.lua`

```lua
-- A class: a table of methods that is also the metatable of its objects.
local Account = {}
Account.__index = Account          -- objects look up missing keys here

-- The constructor. By convention it is called new.
function Account.new(owner, balance)
  local self = setmetatable({}, Account)
  self.owner = owner
  self.balance = balance or 0
  return self
end

function Account:deposit(amount)   -- same as Account.deposit(self, amount)
  self.balance = self.balance + amount
end

function Account:withdraw(amount)
  if amount > self.balance then
    error("insufficient funds")
  end
  self.balance = self.balance - amount
end

function Account:__tostring()
  return ("%s: %d"):format(self.owner, self.balance)
end

local a = Account.new("Ada", 100)
local b = Account.new("Bob")
a:deposit(50)                      -- a.deposit(a, 50)
b:deposit(10)
print(tostring(a), tostring(b))
print(a.deposit == b.deposit)      -- one function, shared through __index
print(pcall(b.withdraw, b, 99))
print(getmetatable(a) == Account, rawget(a, "deposit"))
```

```console
$ luajit examples/ch07/class.lua
Ada: 150	Bob: 10
true
false	examples/ch07/class.lua:19: insufficient funds
true	nil
```

The colon ([Chapter 4](04-functions.md)) makes it read like other languages:

- `function Account:deposit(amount)` defines `Account.deposit(self, amount)`.
- `a:deposit(50)` calls `a.deposit(a, 50)`, found through `__index`.

Metamethods such as `__tostring` also go in the class table, since it is the metatable: one table,
both roles, hence `Account.__index = Account`.

Conventions: capitalized class names, a constructor called `new`, first parameter `self`. `stash`
writes `Account.new(...)` (a plain function); `Account:new(...)` also exists in Lua code.

Common mistake: `a.deposit(50)` with a dot. Then `self` is `50`, `amount` is `nil`, and you get
`attempt to index local 'self' (a number value)`.

## Inheritance and mixins

A subclass is a class whose own metatable's `__index` points at the base class. Lookups walk the
chain: object → subclass → base class.

`examples/ch07/inherit.lua`

```lua
-- Inheritance: a subclass whose metatable points (via __index) to the base.
local Shape = {}
Shape.__index = Shape

function Shape.new(name)
  return setmetatable({ name = name }, Shape)
end

function Shape:area()
  return 0
end

function Shape:describe()
  return ("%s with area %.2f"):format(self.name, self:area())
end

-- Circle "is a" Shape: missing keys in Circle are looked up in Shape.
local Circle = setmetatable({}, { __index = Shape })
Circle.__index = Circle

function Circle.new(r)
  local self = Shape.new("circle")      -- build the base part...
  self.r = r
  return setmetatable(self, Circle)     -- ...then make it a Circle
end

function Circle:area()                  -- override
  return math.pi * self.r ^ 2
end

function Circle:describe()              -- extend: call the base version
  return Shape.describe(self) .. " and radius " .. self.r
end

-- A mixin: copy functions into a class instead of inheriting them.
local Comparable = {
  bigger_than = function(self, other) return self:area() > other:area() end,
}
for name, fn in pairs(Comparable) do
  Shape[name] = fn
end

local s, c = Shape.new("dot"), Circle.new(1)
print(s:describe())
print(c:describe())
print(c:bigger_than(s), s:bigger_than(c))
-- The lookup chain: c -> Circle -> Shape
print(rawget(c, "area"), rawget(Circle, "bigger_than"), Shape.bigger_than ~= nil)
```

```console
$ luajit examples/ch07/inherit.lua
dot with area 0.00
circle with area 3.14 and radius 1
true	false
nil	nil	true
```

- **Override** a method by defining it in the subclass.
- Call the base version through the base table with an explicit `self`: `Shape.describe(self)`.
  There is no `super`.
- The constructor builds the base part (`Shape.new`), adds fields, then switches the metatable.

A **mixin** copies functions into a class: simpler than inheritance, and a class can mix several.
Each lookup level costs a little time, so keep hierarchies flat: one level plus mixins is plenty.

## Read-only tables

`__newindex` fires only for **missing** keys. To guard every key, hand out an **empty proxy**:
`__index` reads from the real table, `__newindex` refuses:

`examples/ch07/readonly.lua`

```lua
-- A read-only view: an empty proxy whose metatable reads from the real table
-- and refuses writes.
local function readonly(t)
  return setmetatable({}, {
    __index = t,
    __newindex = function(_, key)
      error("attempt to change read-only key '" .. tostring(key) .. "'", 2)
    end,
    __metatable = false,          -- getmetatable() returns false; setmetatable() fails
  })
end

local DAYS = readonly({ "Mon", "Tue", "Wed" })
print(DAYS[2])
print(pcall(function() DAYS[4] = "Thu" end))
print(pcall(setmetatable, DAYS, nil))
print(getmetatable(DAYS))

-- The catch: the proxy itself is empty.
print(#DAYS, next(DAYS))
```

```console
$ luajit examples/ch07/readonly.lua
Tue
false	examples/ch07/readonly.lua:15: attempt to change read-only key '4'
false	cannot change a protected metatable
false
0	nil
```

- `__metatable` protects a metatable: `getmetatable` returns that field instead, and
  `setmetatable` fails with `cannot change a protected metatable`.
- The `2` in `error(..., 2)` blames the assigning line, not the metamethod
  ([Chapter 9](09-errors.md) explains levels).
- **The catch:** the proxy is empty. `#DAYS` is `0`; `pairs`/`next` see nothing (Lua 5.1 has no
  `__len` or `__pairs` for tables, see below). Use proxies for config-style lookups, not lists you
  loop over.

## Strict mode: catching global typos

Globals live in a table: `_G`. A misspelled name silently reads a missing global and gets `nil`.
A metatable on `_G` fixes that:

`examples/ch07/strict.lua`

```lua
-- Strict mode: make undeclared globals an error. _G is a table like any other.
setmetatable(_G, {
  __newindex = function(_, name)
    error("assignment to undeclared global '" .. tostring(name) .. "'", 2)
  end,
  __index = function(_, name)
    error("undeclared global '" .. tostring(name) .. "'", 2)
  end,
})

local count = 0
print(pcall(function() count = count + 1 end))   -- a local: fine
print(pcall(function() conut = 1 end))          -- typo: caught
print(pcall(function() return coutn end))        -- typo: caught
rawset(_G, "DEBUG", false)                       -- declare a global on purpose
print(DEBUG)
```

```console
$ luajit examples/ch07/strict.lua
true
false	examples/ch07/strict.lua:13: assignment to undeclared global 'conut'
false	examples/ch07/strict.lua:14: undeclared global 'coutn'
false
```

Reading an undefined global or assigning a new one is now an error. Locals aren't in `_G`, so
they're unaffected. Create a global on purpose with `rawset(_G, ...)`.

Strict mode is cheap insurance for a program, but not for a library: `_G` belongs to the whole
program.

## Weak tables

A table normally keeps its keys and values alive. A **weak table** holds references the garbage
collector ignores. Set `__mode` in its metatable:

| `__mode` | Weak part | Typical use |
|----------|-----------|-------------|
| `"k"` | keys | Extra data attached to objects you don't own. |
| `"v"` | values | Caches: entries vanish when nothing else uses them. |
| `"kv"` | both | Both. |

When a weak key or value is freed, its whole entry is removed.

`examples/ch07/weak.lua`

```lua
-- Weak tables: references that don't keep a value alive.
local cache = setmetatable({}, { __mode = "k" })   -- weak keys

local key1, key2 = {}, {}
cache[key1] = "one"
cache[key2] = "two"

key1 = nil                       -- the only strong reference is gone
collectgarbage()                 -- run a full collection

local n = 0
for _ in pairs(cache) do n = n + 1 end
print(n)                         -- 1: key1's entry was removed

-- __mode = "v": weak values. Strings and numbers are values, not objects,
-- so they are never removed.
local names = setmetatable({}, { __mode = "v" })
names[1] = {}                    -- a table with no other reference
names[2] = "a string"
collectgarbage()
print(names[1], names[2])
```

```console
$ luajit examples/ch07/weak.lua
1
nil	a string
```

Only **objects** (tables, functions, coroutines, userdata) are removed; strings and numbers never
vanish. The collector normally runs when it decides; `collectgarbage()` forces a cycle for the
demo.

## What metatables can't do on tables (5.1)

LuaJIT follows Lua 5.1: two metamethods only work on other types.

`examples/ch07/limits.lua`

```lua
-- Two metamethods that do NOT work on tables in Lua 5.1 / LuaJIT.
local t = setmetatable({ 1, 2, 3 }, {
  __len = function() return 99 end,          -- ignored for tables
  __gc = function() print("collected") end,  -- ignored for tables
})
print(#t)                    -- 3, not 99
t = nil
collectgarbage()             -- prints nothing
print("done")
```

```console
$ luajit examples/ch07/limits.lua
3
done
```

- `__len` is ignored for tables: `#t` uses the real array part (Lua 5.2 changed this).
- `__gc` is ignored for tables. Lua 5.1 runs it only for **userdata** (C objects); LuaJIT also for
  **cdata** (FFI C data). `stash` frees C memory that way in [Chapter 14](14-c-data.md).
- No `__pairs`/`__ipairs`: `pairs` and `ipairs` always use raw access.

(A LuaJIT built with `-DLUAJIT_ENABLE_LUA52COMPAT` has `__len`, `__pairs` and other 5.2 behaviors.
Standard builds don't; don't rely on them.)

## Building stash: Entry and MemoryStore classes

In `project/ch06/stash.lua`, entries are bare tables and each command loops over `entries`. This
step adds:

- **Strict mode**: a misspelled variable name is an error.
- An **`Entry` class**: `has_tag`, `matches`, `tag_string`, `__tostring` (messages print
  `#4 www.lua.org/pil`) and `__lt` (`table.sort` sorts by id, no comparator).
- A **`MemoryStore` class**: `add`, `get`, `remove`, `list`, `search`, `tags`. Commands only talk to
  the store. A file store with the same methods replaces it in [Chapter 12](12-io-and-os.md), an
  SQLite one in [Chapter 15](15-wrapping-sqlite.md); the commands won't change.

The store keeps a dictionary `by_id` (id → entry), so `get(id)` is one lookup, not a loop.

### The top of the file

Replace everything from the top of `stash.lua` down to the `Argument parsing` section with the code
below. This removes the old `entries` array, `next_id`, `find_entry` and `has_tag`. The string
helpers move up, right after `VERSION`, because `Entry` uses `title_from_url`; only their comments
get shorter.

```lua
#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 7: metatables. Entries become objects of an Entry class, the
-- bookmarks live in a MemoryStore object, and strict mode catches typos
-- in global names.

-- Strict mode: reading or assigning an undeclared global is an error.
-- Without this, a typo such as `entires` silently reads nil.
setmetatable(_G, {
  __newindex = function(_, name)
    error("assignment to undeclared global '" .. tostring(name) .. "'", 2)
  end,
  __index = function(_, name)
    error("undeclared global '" .. tostring(name) .. "'", 2)
  end,
})

local VERSION = "0.1.0"

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
local function truncate(s, width)
  if #s <= width then
    return s
  end
  return s:sub(1, width - 3) .. "..."
end

-- "https://www.lua.org/pil/?x=1" -> "www.lua.org/pil"
local function title_from_url(url)
  local rest = url:match("^%a[%w+.-]*://([^?#]*)") or url
  return (rest:gsub("/+$", ""))
end
```

Strict mode comes first, before other code runs. The script uses only locals, so nothing else
changes for it.

Next, the `Entry` class:

```lua
---------------------------------------------------------------------------
-- Entry: one bookmark. The class table doubles as the metatable of its
-- instances; __index = Entry makes instances find their methods there.
---------------------------------------------------------------------------

local Entry = {}
Entry.__index = Entry

function Entry.new(fields)
  local self = setmetatable({}, Entry)
  self.id = fields.id                        -- nil until a store assigns one
  self.url = fields.url
  self.title = fields.title or title_from_url(fields.url)
  self.note = fields.note or ""
  self.tags = {}
  for i, tag in ipairs(fields.tags or {}) do
    self.tags[i] = tag                       -- copy: never share the caller's table
  end
  table.sort(self.tags)
  return self
end

function Entry:has_tag(tag)
  for _, t in ipairs(self.tags) do
    if t == tag then
      return true
    end
  end
  return false
end

-- Case-insensitive substring search over the text fields.
function Entry:matches(term)
  term = term:lower()
  for _, field in ipairs({ self.title, self.url, self.note, self:tag_string(" ") }) do
    if field:lower():find(term, 1, true) then
      return true
    end
  end
  return false
end

function Entry:tag_string(sep)
  return table.concat(self.tags, sep or ",")
end

-- tostring(entry) and print(entry) use this.
function Entry.__tostring(self)
  return ("#%d %s"):format(self.id or 0, self.title)
end

-- `a < b` on entries compares ids, so table.sort(list) needs no comparator.
function Entry.__lt(a, b)
  return a.id < b.id
end
```

Design notes:

- `Entry.new` takes named fields ([Chapter 4](04-functions.md)), so callers can omit any.
- The constructor **copies** the tags. Tables are passed by reference
  ([Chapter 5](05-tables.md)), so keeping the caller's table would let later changes leak in.
- `matches(entry, term)` and `has_tag(entry, tag)` became methods: data and code live together.

Then the store and its sample data:

```lua
---------------------------------------------------------------------------
-- MemoryStore: keeps entries in a table. Every store we write implements
-- the same methods, so the commands do not care where entries live:
--   add(entry) -> entry      get(id) -> entry|nil     remove(id) -> entry|nil
--   list{tag=, limit=} -> array     search(term) -> array     tags() -> array
---------------------------------------------------------------------------

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

-- All entries sorted by id. (pairs() visits keys in no particular order.)
function MemoryStore:sorted()
  local list = {}
  for _, entry in pairs(self.by_id) do
    list[#list + 1] = entry
  end
  table.sort(list)                           -- uses Entry.__lt
  return list
end

function MemoryStore:list(filter)
  local result = {}
  for _, entry in ipairs(self:sorted()) do
    if filter.limit and #result >= filter.limit then
      break
    end
    if filter.tag == nil or entry:has_tag(filter.tag) then
      result[#result + 1] = entry
    end
  end
  return result
end

function MemoryStore:search(term)
  local result = {}
  for _, entry in ipairs(self:sorted()) do
    if entry:matches(term) then
      result[#result + 1] = entry
    end
  end
  return result
end

-- Returns { {tag=, count=}, ... }: most used first, then by name.
function MemoryStore:tags()
  local counts = {}
  for _, entry in pairs(self.by_id) do
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

-- Nothing is saved yet (files arrive in Chapter 12), so every run starts
-- from these sample entries.
local store = MemoryStore.new({
  { url = "https://www.lua.org/", title = "The Programming Language Lua",
    tags = { "lua", "lang" }, note = "official site" },
  { url = "https://luajit.org/", title = "LuaJIT", tags = { "lua", "jit" } },
  { url = "https://sqlite.org/fts5.html", title = "SQLite FTS5 Extension",
    tags = { "db", "search" }, note = "full-text search" },
})
```

- `by_id` is a hash, so its order is undefined. `sorted()` builds an array and sorts it with `<`
  (`Entry.__lt`).
- Ids are never reused: `next_id` only grows. After `rm 2`, the next entry gets 4, not 2.
- `tags()` is the old `tags` command's counting code, moved into the store. The command only
  prints.

### The commands

`fail` and `parse_args` don't change (in `project/ch07/` a few comments are shorter). In the
`Commands` section, `format_row` moves above `commands.add` and uses `tag_string`:

```lua
local commands = {}
local order = { "add", "list", "search", "show", "rm", "tags", "help", "version" }

local function format_row(entry)
  return ("%3d  %-36s  %s"):format(entry.id, truncate(entry.title, 36), entry:tag_string())
end
```

`add` builds an `Entry` and hands it to the store. `Entry.new` now sorts tags and makes the title:

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
    local entry = store:add(Entry.new({ url = url, tags = tags, note = opts.note }))
    print("added " .. tostring(entry))
  end,
}
```

`list` and `search` ask the store. The loops are gone, and so is the old `matches` (now
`Entry:matches`):

```lua
commands.list = {
  usage = "list [-t TAG] [--limit N]",
  help = "list bookmarks",
  options = { ["-t"] = { "tag", "value" }, ["--limit"] = { "limit", "number" } },
  run = function(opts)
    for _, entry in ipairs(store:list({ tag = opts.tag, limit = opts.limit })) do
      print(format_row(entry))
    end
  end,
}

commands.search = {
  usage = "search TERM",
  help = "find bookmarks containing TERM",
  options = {},
  run = function(opts)
    local term = opts[1]
    if term == nil then
      return fail("search: missing TERM")
    end
    local found = store:search(term)
    for _, entry in ipairs(found) do
      print(format_row(entry))
    end
    if #found == 0 then
      fail("nothing matches '%s'", term)
    end
  end,
}
```

`show`, `rm` and `tags` also go through the store:

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
    local entry = store:get(id)
    if entry == nil then
      return fail("no entry with id %d", id)
    end
    print(("%-6s %d"):format("id:", entry.id))
    print(("%-6s %s"):format("title:", entry.title))
    print(("%-6s %s"):format("url:", entry.url))
    print(("%-6s %s"):format("tags:", entry:tag_string(", ")))
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
    local entry = store:remove(id)
    if entry == nil then
      return fail("no entry with id %d", id)
    end
    print("removed " .. tostring(entry))
  end,
}

commands.tags = {
  usage = "tags",
  help = "count bookmarks per tag",
  options = {},
  run = function()
    for _, row in ipairs(store:tags()) do
      print(("%4d  %s"):format(row.count, row.tag))
    end
  end,
}
```

`help`, `version` and `main` stay the same.

### Checkpoint

```console
$ luajit stash.lua list
  1  The Programming Language Lua          lang,lua
  2  LuaJIT                                jit,lua
  3  SQLite FTS5 Extension                 db,search
$ luajit stash.lua list -t lua
  1  The Programming Language Lua          lang,lua
  2  LuaJIT                                jit,lua
$ luajit stash.lua search sqlite
  3  SQLite FTS5 Extension                 db,search
$ luajit stash.lua show 1
id:    1
title: The Programming Language Lua
url:   https://www.lua.org/
tags:  lang, lua
note:  official site
$ luajit stash.lua add https://www.lua.org/pil/ -t book,lua
added #4 www.lua.org/pil
$ luajit stash.lua rm 2
removed #2 LuaJIT
$ luajit stash.lua tags
   2  lua
   1  db
   1  jit
   1  lang
   1  search
```

Same output as Chapter 6: new structure, same behavior. `add` and `rm` messages now come from
`Entry.__tostring`. Changes are still lost on exit.

The complete project at this point is in `project/ch07/`.

## Summary

- A metatable (`setmetatable`) holds metamethods Lua uses when an operation can't proceed alone.
- `__index` (table or function) handles reads of missing keys; `__newindex` assignments to missing
  keys. `rawget`/`rawset`/`rawequal` bypass metamethods.
- Operators: `__add` and friends, `__unm`, `__concat`, `__eq` (both tables, same metamethod),
  `__lt`, `__le` (falls back to `__lt`), `__call`, `__tostring`.
- A class is a method table that is also its objects' metatable (`Class.__index = Class`), with
  constructor `Class.new`; methods use `:` and `self`.
- Inheritance chains `__index`; call base methods as `Base.method(self, ...)`. Mixins copy
  functions. Keep hierarchies flat.
- Proxies make read-only tables (but `#` and `pairs` see them empty). `__metatable` hides and locks
  a metatable.
- A metatable on `_G` gives strict mode.
- `__mode = "k"`/`"v"` makes weak tables for caches and per-object data.
- In Lua 5.1/LuaJIT, `__len`, `__gc` and `__pairs` don't work for tables (`__gc` works for cdata).

## Exercises

1. Write a `Stack` class: `push`, `pop` (error when empty), `size`, and a `__tostring` printing
   `[1, two, 3]`. Why must `size` be a method instead of `#stack`?

<details><summary>Solution</summary>

```lua
local Stack = {}
Stack.__index = Stack

function Stack.new()
  return setmetatable({ items = {}, n = 0 }, Stack)
end

function Stack:push(value)
  self.n = self.n + 1
  self.items[self.n] = value
end

function Stack:pop()
  if self.n == 0 then
    error("pop from an empty stack", 2)
  end
  local value = self.items[self.n]
  self.items[self.n] = nil
  self.n = self.n - 1
  return value
end

function Stack:size()
  return self.n
end

function Stack:__tostring()
  local parts = {}
  for i = 1, self.n do
    parts[i] = tostring(self.items[i])
  end
  return "[" .. table.concat(parts, ", ") .. "]"
end

local s = Stack.new()
s:push(1); s:push("two"); s:push(3)
print(tostring(s), s:size())
print(s:pop(), s:pop(), tostring(s))
print(pcall(function() s:pop(); s:pop() end))
```

Saved as `ex.lua`, it prints:

```console
[1, two, 3]	3
3	two	[1]
false	ex.lua:39: pop from an empty stack
```

`#` ignores `__len` on tables in Lua 5.1, so `#s` counts the object's own array part (empty: the
items are in `s.items`). A count `n` also lets the stack hold `nil`.

</details>

2. Write a `Set` class: `Set.new{"a", "b"}`, `+` union, `*` intersection, `<=` subset, `==` equal
   sets, and a sorted `__tostring` like `{a, b}`.

<details><summary>Solution</summary>

```lua
local Set = {}
Set.__index = Set

function Set.new(items)
  local self = setmetatable({}, Set)
  for _, v in ipairs(items or {}) do
    self[v] = true
  end
  return self
end

function Set.__add(a, b)               -- union
  local r = Set.new()
  for k in pairs(a) do r[k] = true end
  for k in pairs(b) do r[k] = true end
  return r
end

function Set.__mul(a, b)               -- intersection
  local r = Set.new()
  for k in pairs(a) do
    if b[k] then r[k] = true end
  end
  return r
end

function Set.__le(a, b)                -- subset
  for k in pairs(a) do
    if not b[k] then return false end
  end
  return true
end

function Set.__eq(a, b)
  return a <= b and b <= a
end

function Set:__tostring()
  local items = {}
  for k in pairs(self) do items[#items + 1] = tostring(k) end
  table.sort(items)
  return "{" .. table.concat(items, ", ") .. "}"
end

local a, b = Set.new({ "lua", "c", "go" }), Set.new({ "c", "zig" })
print(tostring(a + b), tostring(a * b))
print(Set.new({ "c" }) <= a, b <= a, a + b == b + a)
```

```console
{c, go, lua, zig}	{c}
true	false	true
```

The elements are the object's own keys. The methods live in `Set`, so `pairs(self)` sees only
elements.

</details>

3. `Entry` defines `__lt` but not `__le`. Does `a <= b` work on entries? What does Lua do?

<details><summary>Solution</summary>

It works:

```console
$ luajit -e '
local Entry = {} Entry.__index = Entry
function Entry.__lt(a, b) return a.id < b.id end
local a, b = setmetatable({id=1}, Entry), setmetatable({id=2}, Entry)
print(a <= b, b <= a, a >= b)'
true	false	false
```

Without `__le`, Lua 5.1 evaluates `a <= b` as `not (b < a)` with `__lt`. Right for a total order
like ids; wrong for a partial order (exercise 2's subsets), so define `__le` there.

</details>

4. Write `counted(t)`: return a proxy for `t` and a table `reads`. Each read through the proxy adds
   one to `reads[key]`; writes go to `t`.

<details><summary>Solution</summary>

```lua
local function counted(t)
  local reads = {}
  local proxy = setmetatable({}, {
    __index = function(_, key)
      reads[key] = (reads[key] or 0) + 1
      return t[key]
    end,
    __newindex = t,                    -- a table: new keys are stored in t
  })
  return proxy, reads
end

local config, reads = counted({ width = 80, color = "auto" })
local _ = config.width, config.width, config.color, config.missing
config.depth = 3
print(reads.width, reads.color, reads.missing, config.depth, reads.depth)
```

```console
2	1	1	3	1
```

The proxy stays empty, so every read reaches `__index` and every write reaches `__newindex`.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-7--metatables-and-objects)
