-- A class: a table of methods that is also the metatable of its objects.
local Account = {}
Account.__index = Account          -- objects look up missing keys here

-- The constructor. By convention it is called new.
function Account.new(owner, balance)
  local self = setmetatable({}, Account)
  self.owner = owner
  self.balance = balance or 0
  return self
end

function Account:deposit(amount)   -- same as Account.deposit(self, amount)
  self.balance = self.balance + amount
end

function Account:withdraw(amount)
  if amount > self.balance then
    error("insufficient funds")
  end
  self.balance = self.balance - amount
end

function Account:__tostring()
  return ("%s: %d"):format(self.owner, self.balance)
end

local a = Account.new("Ada", 100)
local b = Account.new("Bob")
a:deposit(50)                      -- a.deposit(a, 50)
b:deposit(10)
print(tostring(a), tostring(b))
print(a.deposit == b.deposit)      -- one function, shared through __index
print(pcall(b.withdraw, b, 99))
print(getmetatable(a) == Account, rawget(a, "deposit"))
