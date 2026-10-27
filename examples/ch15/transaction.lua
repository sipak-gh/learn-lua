-- A transaction is all or nothing. Db:transaction(fn) runs fn inside
-- BEGIN ... COMMIT, and rolls back if fn raises an error.
package.path = "project/ch15/src/?.lua;" .. package.path

local Db = require("stash.db")
local db = assert(Db.open(":memory:"))
db:exec("CREATE TABLE accounts (name TEXT PRIMARY KEY, balance INTEGER)")
db:run("INSERT INTO accounts VALUES ('ann', 100), ('bob', 0)")

local function transfer(from, to, amount)
  db:transaction(function()
    db:run("UPDATE accounts SET balance = balance + ? WHERE name = ?", { amount, to })
    local row = db:first("SELECT balance FROM accounts WHERE name = ?", { from })
    if row.balance < amount then
      error("not enough money", 0)           -- after bob was already paid!
    end
    db:run("UPDATE accounts SET balance = balance - ? WHERE name = ?", { amount, from })
  end)
end

local function show()
  local parts = {}
  for row in db:rows("SELECT * FROM accounts ORDER BY name") do
    parts[#parts + 1] = row.name .. "=" .. row.balance
  end
  print(table.concat(parts, " "))
end

transfer("ann", "bob", 30)
show()
print(pcall(transfer, "ann", "bob", 500))
show()                                       -- bob's +500 was rolled back

-- BEGIN does not nest: a transaction inside a transaction fails.
print(pcall(db.transaction, db, function() db:transaction(function() end) end))
