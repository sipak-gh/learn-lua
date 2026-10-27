local Entry = require("stash.entry")
local Store = require("stash.store")

local function sample_store()
  local store = assert(Store.open(":memory:"))
  store:add(Entry.new({ url = "https://a.org/", title = "Alpha", tags = { "x", "y" } }),
            "the first page talks about tables")
  store:add(Entry.new({ url = "https://b.org/", title = "Beta", tags = { "y" }, note = "second" }),
            "the second page talks about tables and closures")
  store:add(Entry.new({ url = "https://c.org/", title = "Gamma" }))
  return store
end

test("add assigns ids; get and remove", function()
  local store = sample_store()
  eq(store:get(2).title, "Beta")
  same(store:get(1).tags, { "x", "y" })
  same(store:get(3).tags, {})
  eq(store:remove(2).title, "Beta")
  eq(store:get(2), nil)
  eq(store:remove(2), nil)
end)

test("ids are not reused after remove", function()
  local store = sample_store()
  store:remove(3)
  eq(store:add(Entry.new({ url = "https://d.org/" })).id, 4)
end)

test("list filters by tag and limits", function()
  local store = sample_store()
  local function ids(list)
    local out = {}
    for i, e in ipairs(list) do
      out[i] = e.id
    end
    return out
  end
  same(ids(store:list({})), { 1, 2, 3 })
  same(ids(store:list({ tag = "y" })), { 1, 2 })
  same(ids(store:list({ limit = 1 })), { 1 })
  same(ids(store:list({ tag = "none" })), {})
end)

test("tags counts and sorts", function()
  same(sample_store():tags(), { { tag = "y", count = 2 }, { tag = "x", count = 1 } })
end)

test("entries iterates over everything", function()
  local titles = {}
  for e in sample_store():entries() do
    titles[#titles + 1] = e.title
  end
  same(titles, { "Alpha", "Beta", "Gamma" })
end)

test("search ranks matches and needs every word", function()
  local store = sample_store()
  local found = store:search("tables")
  eq(#found, 2)
  local beta = store:search("tables closures")[1]
  eq(beta.title, "Beta")
  eq(beta.id, 2)
  same(beta.tags, { "y" })                                     -- whole entries come back
  eq(#store:search("tables gamma"), 0)
  eq(store:search("clos*")[1].snippet, "the second page talks about tables and [closures]")
  eq(store:search("second")[1].snippet, "[second]")             -- the note matches too
end)

test("removed entries leave the search index", function()
  local store = sample_store()
  store:remove(2)
  eq(#store:search("closures"), 0)
end)

test("user input is quoted for FTS5", function()
  eq(Store.fts_query('c++ "x" lua*'), '"c++" """x""" "lua"*')
  eq(Store.fts_query("  "), "")
end)

test("list -m matches a Lua pattern against title and URL", function()
  local store = sample_store()
  eq(#store:list({ match = "^alpha" }), 1)              -- case-insensitive
  eq(#store:list({ match = "^ALPHA" }), 1)              -- in the pattern too
  eq(#store:list({ match = "^%A" }), 0)                 -- but %A keeps its meaning
  eq(#store:list({ match = "[bc]%.org" }), 2)
  raises(function() store:list({ match = "[" }) end, "malformed pattern")
end)

test("pages are stored compressed and come back whole", function()
  local store = assert(Store.open(":memory:"))
  local page = ("<p>hello</p>\n"):rep(50)
  store:add(Entry.new({ url = "https://a.org/" }), "hello", page)
  store:add(Entry.new({ url = "https://b.org/" }))
  eq(store:page(1), page)
  eq(store:page(2), nil)
  local size, stored = store:page_size(1)
  eq(size, #page)
  ok(stored < size / 10, stored)
  same(store:stats(), { entries = 2, tags = 0, pages = 1, size = #page, stored = stored })
  store:remove(1)
  eq(store:stats().pages, 0)                 -- ON DELETE CASCADE
end)

test("the schema is at the latest version", function()
  eq(assert(Store.open(":memory:")).db:first("PRAGMA user_version").user_version, 2)
end)
