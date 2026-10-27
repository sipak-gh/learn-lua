local util = require("stash.util")

test("split trims pieces and drops empty ones", function()
  same(util.split(" a, b,,c ", ","), { "a", "b", "c" })
  same(util.split("", ","), {})
end)

test("truncate keeps short strings and marks cuts", function()
  eq(util.truncate("short", 10), "short")
  eq(util.truncate("exactly10!", 10), "exactly10!")
  eq(util.truncate("a bit too long", 10), "a bit t...")
end)

test("title_from_url drops scheme, query and trailing slashes", function()
  eq(util.title_from_url("https://www.lua.org/"), "www.lua.org")
  eq(util.title_from_url("https://www.lua.org/pil/?x=1#top"), "www.lua.org/pil")
  eq(util.title_from_url("not a url"), "not a url")
end)
