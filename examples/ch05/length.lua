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
