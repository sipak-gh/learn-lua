-- Operators on tables: arithmetic, comparison, tostring, concat, call.
local Vec = {}
Vec.__index = Vec

local function vec(x, y)
  return setmetatable({ x = x, y = y }, Vec)
end

Vec.__add = function(a, b) return vec(a.x + b.x, a.y + b.y) end
Vec.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y) end
Vec.__mul = function(a, b)                 -- number * vec or vec * number
  if type(a) == "number" then return vec(a * b.x, a * b.y) end
  return vec(a.x * b, a.y * b)
end
Vec.__unm = function(a) return vec(-a.x, -a.y) end
Vec.__eq = function(a, b) return a.x == b.x and a.y == b.y end
Vec.__lt = function(a, b) return a:length() < b:length() end
Vec.__le = function(a, b) return a:length() <= b:length() end
Vec.__tostring = function(a) return ("(%g, %g)"):format(a.x, a.y) end
Vec.__concat = function(a, b) return tostring(a) .. tostring(b) end
Vec.__call = function(a, f) return vec(f(a.x), f(a.y)) end

function Vec:length()
  return math.sqrt(self.x ^ 2 + self.y ^ 2)
end

local a, b = vec(1, 2), vec(3, 4)
print(tostring(a + b), tostring(a - b), tostring(2 * a), tostring(-a))
print(a == vec(1, 2), a ~= b, rawequal(a, vec(1, 2)))
print(a < b, a <= b, a > b)               -- a > b is b < a
print("a is " .. a, a .. b)
print(tostring(b(math.sqrt)))             -- __call: the table is callable
print(b:length())
