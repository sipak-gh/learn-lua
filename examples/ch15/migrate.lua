-- Schema migrations: a Lua array of SQL strings. The database records
-- how many it has run in PRAGMA user_version (an integer SQLite keeps
-- in the file header for applications to use).
package.path = "project/ch15/src/?.lua;" .. package.path

local Db = require("stash.db")

local MIGRATIONS = {
  "CREATE TABLE notes (id INTEGER PRIMARY KEY, text TEXT NOT NULL)",
}

local function migrate(db)
  local version = db:first("PRAGMA user_version").user_version
  for i = version + 1, #MIGRATIONS do
    db:transaction(function()
      db:exec(MIGRATIONS[i])
      db:exec("PRAGMA user_version = " .. i)
    end)
    print("ran migration " .. i)
  end
end

local db = assert(Db.open(":memory:"))
migrate(db)                                  -- runs 1
migrate(db)                                  -- nothing to do

-- A later release appends a migration; old databases catch up.
MIGRATIONS[2] = "ALTER TABLE notes ADD COLUMN created INTEGER NOT NULL DEFAULT 0"
migrate(db)                                  -- runs 2 only
print(db:first("PRAGMA user_version").user_version)
for row in db:rows("PRAGMA table_info(notes)") do
  print(row.cid, row.name, row.type)
end
