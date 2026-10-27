-- Inheritance: a subclass whose metatable points (via __index) to the base.
local Shape = {}
Shape.__index = Shape

function Shape.new(name)
  return setmetatable({ name = name }, Shape)
end

function Shape:area()
  return 0
end

function Shape:describe()
  return ("%s with area %.2f"):format(self.name, self:area())
end

-- Circle "is a" Shape: missing keys in Circle are looked up in Shape.
local Circle = setmetatable({}, { __index = Shape })
Circle.__index = Circle

function Circle.new(r)
  local self = Shape.new("circle")      -- build the base part...
  self.r = r
  return setmetatable(self, Circle)     -- ...then make it a Circle
end

function Circle:area()                  -- override
  return math.pi * self.r ^ 2
end

function Circle:describe()              -- extend: call the base version
  return Shape.describe(self) .. " and radius " .. self.r
end

-- A mixin: copy functions into a class instead of inheriting them.
local Comparable = {
  bigger_than = function(self, other) return self:area() > other:area() end,
}
for name, fn in pairs(Comparable) do
  Shape[name] = fn
end

local s, c = Shape.new("dot"), Circle.new(1)
print(s:describe())
print(c:describe())
print(c:bigger_than(s), s:bigger_than(c))
-- The lookup chain: c -> Circle -> Shape
print(rawget(c, "area"), rawget(Circle, "bigger_than"), Shape.bigger_than ~= nil)
