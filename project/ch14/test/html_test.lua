local html = require("stash.html")

test("title is found in any case and squeezed", function()
  eq(html.title("<html><TITLE>\n  Hello\n  World </Title>"), "Hello World")
  eq(html.title('<title lang="en">Hi</title>'), "Hi")
end)

test("missing or empty titles give nil", function()
  eq(html.title("<p>no title</p>"), nil)
  eq(html.title("<title>  </title>"), nil)
end)

test("entities are decoded", function()
  eq(html.decode_entities("a &amp; b &lt;c&gt; &#65;&#x42;"), "a & b <c> AB")
  eq(html.decode_entities("&bogus; &#233;"), "&bogus; &#233;")
end)

test("fixture pages", function()
  local fs = require("stash.fs")
  eq(html.title(assert(fs.read_file("test/fixtures/lua.html"))), "The Programming Language Lua")
  eq(html.title(assert(fs.read_file("test/fixtures/luajit.html"))),
     "LuaJIT: a Just-In-Time Compiler & FFI")
end)
