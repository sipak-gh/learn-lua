-- obj:name(args) is short for obj.name(obj, args).
local account = { balance = 100 }

function account.deposit(self, amount)
  self.balance = self.balance + amount
end

function account:withdraw(amount) -- same as account.withdraw(self, amount)
  self.balance = self.balance - amount
end

account.deposit(account, 50)
account:deposit(50)              -- the same call, shorter
account:withdraw(30)
print(account.balance)

-- Strings have methods too (Chapter 6).
local s = "lua"
print(s:upper(), s:rep(3, "-"), ("x"):rep(4))
