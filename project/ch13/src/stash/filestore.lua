-- FileStore: a MemoryStore that saves itself to a Lua data file after
-- every change. It inherits everything else from MemoryStore.
--
-- The file looks like:   return { next_id = 3, entries = { {...}, {...} } }

local Entry = require("stash.entry")
local MemoryStore = require("stash.memstore")
local errors = require("stash.errors")
local fs = require("stash.fs")
local serialize = require("stash.serialize")

-- Methods not found in FileStore are looked up in MemoryStore.
local FileStore = setmetatable({}, { __index = MemoryStore })
FileStore.__index = FileStore

-- Opens the store in `path`; a missing file means an empty store.
-- Returns the store, or nil and an error message.
function FileStore.open(path)
  local self = setmetatable(MemoryStore.new(), FileStore)
  self.path = path
  if not fs.exists(path) then
    return self
  end
  local data, err = serialize.load(path)
  if data == nil then
    return nil, err
  end
  for _, fields in ipairs(data.entries) do
    local entry = Entry.new(fields)
    self.by_id[entry.id] = entry             -- keep the saved ids
  end
  self.next_id = data.next_id
  return self
end

function FileStore:save()
  local records = {}
  for entry in self:entries() do
    records[#records + 1] = entry:record()
  end
  local text = "return " .. serialize.serialize({ next_id = self.next_id, entries = records }) .. "\n"
  local ok, err = fs.mkdir_p(fs.dirname(self.path))
  if ok then
    ok, err = fs.write_atomic(self.path, text)
  end
  if not ok then
    errors.fail("cannot save %s: %s", self.path, err)
  end
end

-- Overrides: do what MemoryStore does, then save.
function FileStore:add(entry)
  MemoryStore.add(self, entry)
  self:save()
  return entry
end

function FileStore:remove(id)
  local entry = MemoryStore.remove(self, id)
  if entry then
    self:save()
  end
  return entry
end

return FileStore
