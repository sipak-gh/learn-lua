package.path = "examples/ch08/?.lua;examples/ch08/?/init.lua"
package.cpath = "examples/ch08/?.so"

local ok, err = pcall(require, "nosuch")
print(ok)
print(err)
