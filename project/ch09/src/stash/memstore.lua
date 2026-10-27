-- MemoryStore: keeps entries in a table. Every store implements the same
-- methods, so the commands do not care where entries live:
--   add(entry) -> entry      get(id) -> entry|nil     remove(id) -> entry|nil
--   list{tag=, limit=} -> array     search(term) -> array     tags() -> array

local Entry = require("stash.entry")

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

return MemoryStore
