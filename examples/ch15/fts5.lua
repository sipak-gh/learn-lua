-- Full-text search with SQLite's FTS5 extension.
package.path = "project/ch15/src/?.lua;" .. package.path

local Db = require("stash.db")
local db = assert(Db.open(":memory:"))

-- A virtual table: SQLite keeps an inverted index of every word.
db:exec("CREATE VIRTUAL TABLE docs USING fts5(title, body)")
local docs = {
  { "Lua", "Lua is a small scripting language. Tables are its only data structure." },
  { "LuaJIT", "LuaJIT is a tracing JIT compiler for Lua, with an FFI for C." },
  { "SQLite", "SQLite is a C library. FTS5 adds full-text search to SQLite tables." },
}
for _, d in ipairs(docs) do
  db:run("INSERT INTO docs (title, body) VALUES (?, ?)", d)
end

local function search(query)
  print("-- " .. query)
  local ok, err = pcall(function()
    for row in db:rows([[
        SELECT title, snippet(docs, 1, '[', ']', '...', 6) AS snip
        FROM docs WHERE docs MATCH ? ORDER BY rank]], { query }) do
      print(row.title, row.snip)
    end
  end)
  if not ok then print(err) end
end

search("tables")                 -- words, case-insensitive; rank = best first
search("lua c")                  -- every word must appear
search("compil*")                -- prefix query
search("title:sqlite")           -- a column filter
search("c++")                    -- user input is FTS5 syntax...
search('"c++"')                  -- ...unless you quote it
