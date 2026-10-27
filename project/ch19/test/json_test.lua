local json = require("stash.json")
local iter = require("stash.iter")

test("scalars", function()
  eq(json.encode(42), "42")
  eq(json.encode(-0.5), "-0.5")
  eq(json.encode(true), "true")
  eq(json.encode(nil), "null")
end)

test("strings are escaped", function()
  eq(json.encode('say "hi"\n'), [["say \"hi\"\n"]])
  eq(json.encode("tab\tbell\7"), [["tab\tbell\u0007"]])
  eq(json.encode("back\\slash"), [["back\\slash"]])
end)

test("arrays and objects", function()
  eq(json.encode({ 1, 2, 3 }), "[1,2,3]")
  eq(json.encode({}), "[]")
  eq(json.encode({ b = 1, a = { "x" } }), [[{"a":["x"],"b":1}]])
end)

test("tables with holes are not arrays", function()
  raises(function() json.encode({ [1] = "a", [3] = "c" }) end, "keys must be strings")
end)

test("values JSON cannot hold are errors", function()
  raises(function() json.encode(math.huge) end, "cannot represent inf")
  raises(function() json.encode(print) end, "cannot represent a function")
end)

test("write_array streams one element per line", function()
  local lines = {}
  local n = json.write_array(iter.values({ 1, { a = 2 } }), function(l) lines[#lines + 1] = l end)
  eq(n, 2)
  same(lines, { "[", "  1,", [[  {"a":2}]], "]" })
  lines = {}
  json.write_array(iter.values({}), function(l) lines[#lines + 1] = l end)
  same(lines, { "[", "]" })
end)
