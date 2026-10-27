-- Sample bookmarks. A module can be plain data: this file just returns a
-- table. (Nothing is saved yet; files arrive in Chapter 12.)

return {
  { url = "https://www.lua.org/", title = "The Programming Language Lua",
    tags = { "lua", "lang" }, note = "official site" },
  { url = "https://luajit.org/", title = "LuaJIT", tags = { "lua", "jit" } },
  { url = "https://sqlite.org/fts5.html", title = "SQLite FTS5 Extension",
    tags = { "db", "search" }, note = "full-text search" },
}
