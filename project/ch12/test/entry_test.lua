local Entry = require("stash.entry")

test("new copies and sorts the tags", function()
  local tags = { "b", "a" }
  local e = Entry.new({ url = "https://x.org/", tags = tags })
  same(e.tags, { "a", "b" })
  same(tags, { "b", "a" })                   -- the caller's table is untouched
end)

test("title defaults to one made from the URL", function()
  eq(Entry.new({ url = "https://x.org/a/" }).title, "x.org/a")
  eq(Entry.new({ url = "https://x.org/", title = "X" }).title, "X")
end)

test("has_tag and tag_string", function()
  local e = Entry.new({ url = "https://x.org/", tags = { "lua", "db" } })
  ok(e:has_tag("lua"))
  ok(not e:has_tag("go"))
  eq(e:tag_string(), "db,lua")
  eq(e:tag_string(", "), "db, lua")
end)

test("matches ignores case and treats the term literally", function()
  local e = Entry.new({ url = "https://x.org/", title = "C++ Notes (50%)" })
  ok(e:matches("c++"))
  ok(e:matches("50%"))
  ok(not e:matches("python"))
end)

test("tostring and < use the id", function()
  local a = Entry.new({ id = 1, url = "https://a.org/", title = "A" })
  local b = Entry.new({ id = 2, url = "https://b.org/", title = "B" })
  eq(tostring(a), "#1 A")
  ok(a < b)
  local list = { b, a }
  table.sort(list)
  eq(list[1], a)
end)
