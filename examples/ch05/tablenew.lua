-- LuaJIT extensions: pre-sized tables and clearing in place.
-- require loads a library (Chapter 8); these two add table.new/table.clear.
require("table.new")
require("table.clear")

-- table.new(narray, nhash) reserves room, so the table never has to grow.
local squares = table.new(1000, 0)
for i = 1, 1000 do squares[i] = i * i end
print(#squares, squares[1000])

-- table.clear removes every key but keeps the allocated room for reuse.
table.clear(squares)
print(#squares, next(squares))
