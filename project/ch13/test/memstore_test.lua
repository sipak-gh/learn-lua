local Entry = require("stash.entry")
local MemoryStore = require("stash.memstore")

local function sample_store()
  return MemoryStore.new({
    { url = "https://a.org/", title = "Alpha", tags = { "x", "y" } },
    { url = "https://b.org/", title = "Beta", tags = { "y" }, note = "second" },
    { url = "https://c.org/", title = "Gamma" },
  })
end

test("add assigns increasing ids", function()
  local store = MemoryStore.new()
  eq(store:add(Entry.new({ url = "https://a.org/" })).id, 1)
  eq(store:add(Entry.new({ url = "https://b.org/" })).id, 2)
end)

test("get and remove", function()
  local store = sample_store()
  eq(store:get(2).title, "Beta")
  eq(store:remove(2).title, "Beta")
  eq(store:get(2), nil)
  eq(store:remove(2), nil)
end)

test("ids are not reused after remove", function()
  local store = sample_store()
  store:remove(3)
  eq(store:add(Entry.new({ url = "https://d.org/" })).id, 4)
end)

test("list filters by tag and stops at the limit", function()
  local store = sample_store()
  local function titles(list)
    local result = {}
    for i, e in ipairs(list) do result[i] = e.title end
    return result
  end
  same(titles(store:list({})), { "Alpha", "Beta", "Gamma" })
  same(titles(store:list({ tag = "y" })), { "Alpha", "Beta" })
  same(titles(store:list({ limit = 1 })), { "Alpha" })
end)

test("search looks at the note too", function()
  local found = sample_store():search("SECOND")
  eq(#found, 1)
  eq(found[1].title, "Beta")
end)

test("tags are counted, most used first", function()
  same(sample_store():tags(), { { tag = "y", count = 2 }, { tag = "x", count = 1 } })
end)

test("entries skips removed ids", function()
  local store = sample_store()
  store:remove(2)
  local ids = {}
  for entry in store:entries() do
    ids[#ids + 1] = entry.id
  end
  same(ids, { 1, 3 })
end)
