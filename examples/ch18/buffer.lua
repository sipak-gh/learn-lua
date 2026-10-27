-- LuaJIT's string buffers: a growable, reusable string builder.
local buffer = require("string.buffer")

local buf = buffer.new()
buf:put("stash", " ", 18):put("\n")          -- put returns buf: calls chain
buf:putf("%-6s|%5.1f|\n", "pi", math.pi)     -- like string.format
print(#buf)
io.write(buf:tostring())                     -- a copy; buf is unchanged

-- A buffer is also a queue: get() takes bytes off the front.
print(buf:get(5), #buf)
buf:reset()                                  -- empty, but keeps its memory
print(#buf)

-- Serialization: any Lua value without functions, to bytes and back.
local bytes = buffer.encode({ id = 7, tags = { "lua", "jit" } })
local copy = buffer.decode(bytes)
print(#bytes, copy.id, copy.tags[2])
