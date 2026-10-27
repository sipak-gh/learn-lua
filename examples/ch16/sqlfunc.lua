-- A Lua function called from SQL, through stash.db's create_function.
package.path = "project/ch16/src/?.lua;" .. package.path
local Db = require("stash.db")

local db = assert(Db.open(":memory:"))
db:exec([[
  CREATE TABLE words (w TEXT);
  INSERT INTO words VALUES ('lua'), ('LuaJIT'), ('sqlite'), (NULL);
]])

db:create_function("vowels", 1, function(s)
  return s and select(2, s:gsub("[aeiouAEIOU]", ""))
end)

for row in db:rows("SELECT w, vowels(w) AS n FROM words ORDER BY n DESC, w") do
  print(row.w, row.n)
end

db:create_function("fails", 0, function() error("no luck", 0) end)
print(pcall(db.first, db, "SELECT fails()"))
