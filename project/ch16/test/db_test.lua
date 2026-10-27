local Db = require("stash.db")

local function memory_db()
  local db = assert(Db.open(":memory:"))
  db:exec("CREATE TABLE t (n INTEGER, x REAL, s TEXT)")
  return db
end

test("values go in and come back as Lua values", function()
  local db = memory_db()
  eq(db:run("INSERT INTO t VALUES (?, ?, ?)", { 42, 0.5, "it's" }), 1)
  eq(db:last_id(), 1)
  same(db:first("SELECT n, x, s FROM t"), { n = 42, x = 0.5, s = "it's" })
end)

test("named parameters, and NULL for the ones not given", function()
  local db = memory_db()
  db:run("INSERT INTO t VALUES (:n, :x, :s)", { n = 7, s = "seven" })
  same(db:first("SELECT * FROM t"), { n = 7, s = "seven" })
  raises(function() db:run("INSERT INTO t VALUES (:n, 0, '')", { m = 1 }) end, "no parameter :m")
end)

test("rows iterates in order", function()
  local db = memory_db()
  for i = 1, 3 do
    db:run("INSERT INTO t (n) VALUES (?)", { i * 10 })
  end
  local seen = {}
  for row in db:rows("SELECT n FROM t WHERE n > ? ORDER BY n", { 10 }) do
    seen[#seen + 1] = row.n
  end
  same(seen, { 20, 30 })
end)

test("SQL errors carry SQLite's message", function()
  local db = memory_db()
  raises(function() db:prepare("SELEKT 1") end, 'database: near "SELEKT": syntax error')
  raises(function() db:exec("INSERT INTO nope VALUES (1)") end, "database: no such table: nope")
end)

test("errors while stepping are reported too", function()
  local db = assert(Db.open(":memory:"))
  db:exec("CREATE TABLE u (name TEXT NOT NULL)")
  raises(function() db:run("INSERT INTO u VALUES (NULL)") end,
         "database: NOT NULL constraint failed: u.name")
end)

test("a failed transaction leaves no trace", function()
  local db = memory_db()
  raises(function()
    db:transaction(function()
      db:run("INSERT INTO t (n) VALUES (1)")
      error("boom")
    end)
  end, "boom")
  eq(db:first("SELECT count(*) AS n FROM t").n, 0)
end)

test("opening a bad path fails cleanly", function()
  local db, err = Db.open("no/such/dir/x.db")
  eq(db, nil)
  eq(err, "cannot open no/such/dir/x.db: unable to open database file")
end)

test("Lua functions can be called from SQL", function()
  local db = memory_db()
  db:create_function("twice", 1, function(s) return s and s .. s end)
  db:create_function("fails", 0, function() error("nope", 0) end)
  eq(db:first("SELECT twice('ab') AS r").r, "abab")
  eq(db:first("SELECT twice(NULL) IS NULL AS r").r, 1)
  raises(function() db:first("SELECT fails()") end, "database: nope")
end)
