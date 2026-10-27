local Entry = require("stash.entry")
local FileStore = require("stash.filestore")
local serialize = require("stash.serialize")

test("serialize output loads back as the same data", function()
  local data = { 1, "two", { three = 3 }, flag = true, ["odd key"] = "x\n\"y\"" }
  local text = serialize.serialize(data)
  local loaded = loadstring("return " .. text)()
  same(loaded, data)
end)

test("serialize refuses functions", function()
  raises(function() serialize.serialize({ f = print }) end, "cannot serialize a function")
end)

test("a missing file is an empty store", function()
  local store = assert(FileStore.open(tmpdir("fs-empty") .. "/entries.lua"))
  eq(#store:list({}), 0)
end)

test("entries survive a reopen, ids included", function()
  local path = tmpdir("fs-reopen") .. "/sub/dir/entries.lua"
  local store = assert(FileStore.open(path))
  store:add(Entry.new({ url = "https://a.org/", tags = { "x" }, created = 5 }))
  store:add(Entry.new({ url = "https://b.org/", created = 6 }))
  store:remove(1)

  local again = assert(FileStore.open(path))
  eq(again:get(1), nil)
  eq(again:get(2).url, "https://b.org/")
  eq(again:get(2).created, 6)
  eq(again:add(Entry.new({ url = "https://c.org/" })).id, 3)
end)

test("a broken file is reported", function()
  local path = tmpdir("fs-broken") .. "/entries.lua"
  local file = assert(io.open(path, "w"))
  file:write("return {")
  file:close()
  local store, err = FileStore.open(path)
  eq(store, nil)
  ok(err:find("entries.lua:1:", 1, true), err)
end)
