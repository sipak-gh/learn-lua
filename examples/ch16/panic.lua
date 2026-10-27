-- A JIT-compiled FFI call must not call back into Lua.
--   luajit examples/ch16/panic.lua       stash.db as it is: works
--   luajit examples/ch16/panic.lua on    with the JIT back on: PANIC
package.path = "project/ch16/src/?.lua;" .. package.path
local Db = require("stash.db")
local db = assert(Db.open(":memory:"))
if arg[1] == "on" then
  jit.on(db:prepare("SELECT 1").step)        -- undo stash.db's jit.off(Stmt.step)
end
db:exec("CREATE TABLE t (s TEXT)")
for i = 1, 1000 do
  db:run("INSERT INTO t VALUES (?)", { "row " .. i })
end
db:create_function("shout", 1, function(s) return s:upper() end)

local function count(sql)
  local n = 0
  for _ in db:rows(sql) do n = n + 1 end
  return n
end
print(count("SELECT s FROM t"))              -- hot loop: step() gets compiled
print(count("SELECT shout(s) FROM t"))       -- same loop, but now step() calls Lua
