-- ffi.metatype: give a C type methods and operators.

local ffi = require("ffi")
ffi.cdef [[ typedef struct vec2 { double x, y; } vec2; ]]

local new                 -- the constructor, assigned below

local Vec2 = {}
Vec2.__index = Vec2       -- methods are looked up here, like a class

function Vec2.length(v) return math.sqrt(v.x * v.x + v.y * v.y) end
function Vec2.scale(v, k) return new(v.x * k, v.y * k) end

Vec2.__add = function(a, b) return new(a.x + b.x, a.y + b.y) end
Vec2.__eq = function(a, b) return a.x == b.x and a.y == b.y end
Vec2.__tostring = function(v) return ("(%g, %g)"):format(v.x, v.y) end

-- ffi.metatype returns a constructor: calling it is like ffi.new("vec2", ...).
-- From now on the metatable belongs to the type: don't change Vec2 anymore.
new = ffi.metatype("vec2", Vec2)

local a = new(3, 4)
local b = new(1, 1)
print(a:length(), tostring(a + b), tostring(b:scale(2)))
print(a == new(3, 4), a == b)

-- Every vec2 gets the methods, however it was made.
local arr = ffi.new("vec2[2]", { { 6, 8 } })
print(arr[0]:length())

-- Fields come first; __index is only asked about names that are not fields.
print(a.x, a.length ~= nil)

-- A second metatype call for the same type is an error.
print(pcall(ffi.metatype, "vec2", {}))
