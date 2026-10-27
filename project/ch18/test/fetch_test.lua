local fetch = require("stash.fetch")

local PAGES = "file://" .. os.getenv("PWD") .. "/test/fixtures"

test("file:// URLs are read by curl", function()
  local body, info = fetch.get(PAGES .. "/luajit.html")
  ok(body:find("<title>LuaJIT", 1, true))
  eq(info.status, 0)
  eq(info.content_type, nil)
end)

test("errors come back as messages", function()
  local body, err = fetch.get("file:///no/such/page.html")
  eq(body, nil)
  eq(err, "Couldn't open file /no/such/page.html")
  eq(select(2, fetch.get("ftp://example.com/")),
     'Protocol "ftp" not supported or disabled in libcurl')
end)

test("pages over the size limit are refused", function()
  local saved = fetch.MAX_SIZE
  fetch.MAX_SIZE = 100
  local body, err = fetch.get(PAGES .. "/luajit.html")
  fetch.MAX_SIZE = saved
  eq(body, nil)
  eq(err, "page is larger than 100 bytes")
  ok(fetch.get(PAGES .. "/luajit.html"))     -- and the next download works
end)
