-- The same work as raw.lua, through stash's wrapper (stash.db).
-- Run from the course root: the wrapper lives in project/ch15/src.
package.path = "project/ch15/src/?.lua;" .. package.path

local Db = require("stash.db")

local db = assert(Db.open(":memory:"))
db:exec("CREATE TABLE langs (name TEXT, year INTEGER, note TEXT)")
db:run("INSERT INTO langs VALUES (?, ?, ?)", { "Lua", 1993, "small" })
db:run("INSERT INTO langs (name, year) VALUES (:name, :year)", { name = "C", year = 1972 })
print("last id", db:last_id())

for row in db:rows("SELECT * FROM langs ORDER BY year") do
  print(row.name, row.year, row.note)        -- plain Lua values; NULL is nil
end
print(db:first("SELECT count(*) AS n FROM langs").n)

-- SQLite's error message, raised as a Lua error.
print(pcall(db.first, db, "SELECT nope FROM langs"))
db:close()
