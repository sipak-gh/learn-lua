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
