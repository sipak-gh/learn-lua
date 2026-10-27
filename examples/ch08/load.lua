-- loadstring compiles a string into a function. Nothing runs yet.
local f = assert(loadstring("return 6 * 7"))
print(type(f), f())

-- A syntax error is not thrown: you get nil plus a message.
print(loadstring("return 6 *"))
print(loadstring("return 6 *", "=calc"))     -- the second argument names the chunk

-- A chunk is a function, so it takes arguments as `...`.
local add = loadstring("local a, b = ... return a + b")
print(add(2, 3))

-- loadfile does the same for a file. dofile loads AND runs it (and throws on errors).
print(loadfile("examples/ch08/nosuch.lua"))
print(dofile("examples/ch08/shapes/circle.lua").area(1))
