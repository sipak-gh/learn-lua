-- Where require looks: ? is replaced by the module name.
package.path = "examples/ch08/?.lua;examples/ch08/?/init.lua"

local greet = require("greet")       -- runs greet.lua once...
print(greet.hello("Ada"))

local again = require("greet")       -- ...and returns the cached table after that
print(again == greet, again.count())
print(package.loaded.greet == greet)

print(count)                         -- nil: greet's local `count` is private
