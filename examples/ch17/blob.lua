-- Text or BLOB? The same Lua string, stored two ways in SQLite.
package.path = "project/ch17/src/?.lua;" .. package.path
local Db = require("stash.db")

local db = assert(Db.open(":memory:"))
db:exec("CREATE TABLE t (how TEXT, data)")
local bytes = "ab\0cd"                        -- 5 bytes, one of them zero
db:run("INSERT INTO t VALUES ('text', ?)", { bytes })
db:run("INSERT INTO t VALUES ('blob', ?)", { Db.blob(bytes) })

for row in db:rows("SELECT how, typeof(data) AS type, length(data) AS len, hex(data) AS hex FROM t") do
  print(row.how, row.type, row.len, row.hex)
end
for row in db:rows("SELECT data FROM t") do
  print(#row.data, row.data == bytes)
end
