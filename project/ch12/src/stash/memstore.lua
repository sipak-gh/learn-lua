-- MemoryStore: keeps entries in a table. Every store implements the same
-- methods, so the commands do not care where entries live:
--   add(entry) -> entry      get(id) -> entry|nil     remove(id) -> entry|nil
--   list{tag=, limit=} -> array     search(term) -> array     tags() -> array
--   entries() -> iterator over all entries in id order

local Entry = require("stash.entry")
local iter = require("stash.iter")

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

-- Iterates over the entries in id order:  for entry in store:entries() do
-- The generator walks the ids in order, so no sorting is needed; ids of
-- removed entries are simply missing from the table.
function MemoryStore:entries()
  return coroutine.wrap(function()
    for id = 1, self.next_id - 1 do
      local entry = self.by_id[id]
      if entry then
        coroutine.yield(entry)
      end
    end
  end)
end

-- list and search are pipelines: entries -> filter -> take -> collect.
function MemoryStore:list(filter)
  local it = self:entries()
  if filter.tag then
    it = iter.filter(function(e) return e:has_tag(filter.tag) end, it)
  end
  if filter.limit then
    it = iter.take(filter.limit, it)
  end
  return iter.collect(it)
end

function MemoryStore:search(term)
  return iter.collect(iter.filter(function(e) return e:matches(term) end, self:entries()))
end

-- Returns { {tag=, count=}, ... }: most used first, then by name.
function MemoryStore:tags()
  local counts = {}
  for entry in self:entries() do
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

return MemoryStore
