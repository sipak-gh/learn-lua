package.path = "examples/ch08/?.lua;examples/ch08/?/init.lua"

local shapes = require("shapes")          -- found as examples/ch08/shapes/init.lua
print(("%.2f"):format(shapes.circle.area(2)))
print(shapes.circle == require("shapes.circle"))

print(package.searchpath("shapes.circle", package.path))
print(package.searchpath("nosuch", package.path))
