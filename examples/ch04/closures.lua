-- A closure is a function plus the local variables it uses from outside.
local function make_counter()
  local n = 0                  -- an upvalue of the function below
  return function()
    n = n + 1
    return n
  end
end

local c1 = make_counter()
local c2 = make_counter()      -- a separate n
print(c1(), c1(), c1(), c2())

-- Two closures created together share the same upvalue.
local function make_account(balance)
  local function deposit(x) balance = balance + x end
  local function get() return balance end
  return deposit, get
end
local deposit, get = make_account(100)
deposit(50)
print(get())

-- Each loop pass has a fresh loop variable, so each closure keeps its own i.
local fns = {}
for i = 1, 3 do
  fns[i] = function() return i end
end
print(fns[1](), fns[2](), fns[3]())
