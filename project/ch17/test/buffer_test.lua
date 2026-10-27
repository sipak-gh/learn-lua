local ffi = require("ffi")
local Buffer = require("stash.buffer")

test("an empty buffer", function()
  local buf = Buffer.new()
  eq(#buf, 0)
  eq(tostring(buf), "")
end)

test("appending strings and C bytes", function()
  local buf = Buffer.new()
  buf:append("hello, ")
  local bytes = ffi.new("uint8_t[5]", { 119, 111, 114, 108, 100 })    -- "world"
  buf:append(bytes, 5)
  eq(#buf, 12)
  eq(buf:tostring(), "hello, world")
  eq(buf:byte(0), 104)                                                 -- "h"
  raises(function() buf:byte(12) end, "index out of range")
end)

test("the buffer grows past its first allocation", function()
  local buf = Buffer.new()
  for i = 1, 1000 do
    buf:append(("%04d"):format(i))
  end
  eq(#buf, 4000)
  ok(buf.cap >= 4000)
  eq(buf:tostring():sub(-8), "09991000")
  buf:reset()
  eq(#buf, 0)
end)
