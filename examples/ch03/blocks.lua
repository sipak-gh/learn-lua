-- do ... end makes a block: locals declared inside end with it.
local x = "outer"
do
  local x = "inner"            -- shadows the outer x inside the block
  local temp = 42
  print(x, temp)
end
print(x, temp)                 -- temp is gone: this reads the global, nil
