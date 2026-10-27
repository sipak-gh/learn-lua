-- A local lives from its declaration to the end of its block.
local count = 0
count = count + 1

-- A typo silently creates a new GLOBAL variable. No error.
cuont = count + 1
print(count, cuont)

-- Reading a name that was never assigned gives nil. No error either.
print(undefined_name)

-- Globals are fields of the table _G.
print(_G.cuont, _G.count)     -- count is local, so it isn't in _G

-- A local declared without a value starts as nil.
local x
print(x)

-- `local x = x` makes a local copy of a global (a common speed idiom).
local print = print
print("still works")
