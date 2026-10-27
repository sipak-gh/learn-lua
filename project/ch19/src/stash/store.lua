-- Store: bookmarks in an SQLite database, with full-text search (FTS5).
-- It has the same methods the commands used before, plus the page text:
--   add(entry, text, page) -> entry   get(id) -> entry|nil   remove(id) -> entry|nil
--   list{tag=, limit=} -> array   search(query) -> array   tags() -> array
--   entries() -> iterator over all entries in id order
--   page(id) -> html|nil   page_size(id) -> size, stored | nil   stats() -> table

local Db = require("stash.db")
local compress = require("stash.compress")
local errors = require("stash.errors")
local Entry = require("stash.entry")
local util = require("stash.util")

-- The schema grows by appending to this list; never edit a migration
-- that has shipped. The database remembers how many it has applied in
-- PRAGMA user_version.
local MIGRATIONS = {
  [[
  CREATE TABLE entries (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,   -- AUTOINCREMENT: ids are never reused
    url     TEXT NOT NULL,
    title   TEXT NOT NULL,
    note    TEXT NOT NULL DEFAULT '',
    created INTEGER NOT NULL
  );
  CREATE TABLE tags (
    entry_id INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    tag      TEXT NOT NULL,
    PRIMARY KEY (entry_id, tag)
  );
  CREATE INDEX tags_by_tag ON tags(tag);

  -- The search index: one row per entry, rowid = entries.id.
  CREATE VIRTUAL TABLE search USING fts5(title, url, note, tags, body);
  CREATE TRIGGER entries_deleted AFTER DELETE ON entries BEGIN
    DELETE FROM search WHERE rowid = old.id;
  END;
  ]],
  -- 2: the downloaded pages, compressed (see stash.compress).
  [[
  CREATE TABLE pages (
    entry_id INTEGER PRIMARY KEY REFERENCES entries(id) ON DELETE CASCADE,
    size     INTEGER NOT NULL,                   -- before compression
    data     BLOB NOT NULL
  );
  ]],
}

local Store = {}
Store.__index = Store

-- Brings the schema up to date, one migration per transaction.
local function migrate(db)
  local version = db:first("PRAGMA user_version").user_version
  for i = version + 1, #MIGRATIONS do
    db:transaction(function()
      db:exec(MIGRATIONS[i])
      db:exec("PRAGMA user_version = " .. i)
    end)
  end
end

-- Opens the database in `path` (":memory:" for a throwaway one).
-- Returns the store, or nil and an error message.
function Store.open(path)
  local db, err = Db.open(path)
  if db == nil then
    return nil, err
  end
  db:exec("PRAGMA foreign_keys = ON")         -- SQLite leaves them off by default
  -- `x REGEXP p` calls regexp(p, x). SQLite has no built-in one; ours
  -- uses Lua patterns, case-insensitively: text and pattern are both
  -- lowercased, except %-escapes like %A, whose case is their meaning.
  db:create_function("regexp", 2, function(pattern, text)
    pattern = pattern:gsub("%%?.", function(s) return #s == 1 and s:lower() or s end)
    return text ~= nil and text:lower():find(pattern) ~= nil
  end)
  migrate(db)
  return setmetatable({ db = db }, Store)
end

function Store:close()
  self.db:close()
end

-- Every query that returns entries selects these columns. The tags come
-- along as one comma-separated string.
local COLUMNS = [[
  e.id, e.url, e.title, e.note, e.created,
  (SELECT group_concat(tag) FROM tags WHERE entry_id = e.id) AS tags
]]
local SELECT = "SELECT " .. COLUMNS .. " FROM entries e "

local function to_entry(row)
  row.tags = util.split(row.tags or "", ",")
  return Entry.new(row)
end

-- text is the page as plain text, for the search index; page is the
-- page itself, kept compressed. Both are optional.
function Store:add(entry, text, page)
  local db = self.db
  db:transaction(function()
    db:run("INSERT INTO entries (url, title, note, created) VALUES (:url, :title, :note, :created)",
           { url = entry.url, title = entry.title, note = entry.note, created = entry.created })
    entry.id = db:last_id()
    for _, tag in ipairs(entry.tags) do
      db:run("INSERT INTO tags (entry_id, tag) VALUES (?, ?)", { entry.id, tag })
    end
    db:run("INSERT INTO search (rowid, title, url, note, tags, body) VALUES (?, ?, ?, ?, ?, ?)",
           { entry.id, entry.title, entry.url, entry.note, entry:tag_string(" "), text or "" })
    if page then
      db:run("INSERT INTO pages (entry_id, size, data) VALUES (?, ?, ?)",
             { entry.id, #page, Db.blob(compress.pack(page)) })
    end
  end)
  return entry
end

function Store:get(id)
  local row = self.db:first(SELECT .. "WHERE e.id = ?", { id })
  return row and to_entry(row)
end

function Store:remove(id)
  local entry = self:get(id)
  if entry then
    self.db:run("DELETE FROM entries WHERE id = ?", { id })   -- tags and search rows follow
  end
  return entry
end

-- Iterates over all entries in id order.
function Store:entries()
  local rows = self.db:rows(SELECT .. "ORDER BY e.id")
  return function()
    local row = rows()
    return row and to_entry(row)
  end
end

-- filter.tag, filter.match (a Lua pattern for the title or URL) and
-- filter.limit are optional; a missing parameter is NULL, and LIMIT -1
-- means no limit.
function Store:list(filter)
  local found = {}
  for row in self.db:rows(SELECT .. [[
      WHERE (:tag IS NULL OR e.id IN (SELECT entry_id FROM tags WHERE tag = :tag))
        AND (:match IS NULL OR e.title REGEXP :match OR e.url REGEXP :match)
      ORDER BY e.id LIMIT :limit]],
      { tag = filter.tag, match = filter.match, limit = filter.limit or -1 }) do
    found[#found + 1] = to_entry(row)
  end
  return found
end

-- Turns what the user typed into an FTS5 query: every word must appear.
-- Each word is quoted, so characters like - or : are not FTS5 syntax;
-- a trailing * still means "any word starting with this".
function Store.fts_query(text)
  local words = {}
  for word in text:gmatch("%S+") do
    local star = word:match("%*$") and "*" or ""
    word = word:gsub("%*$", ""):gsub('"', '""')
    if word ~= "" then
      words[#words + 1] = '"' .. word .. '"' .. star
    end
  end
  return table.concat(words, " ")
end

-- Full-text search, best matches first. Each entry gets a `snippet`
-- field: a few words of context with the matches in [brackets].
function Store:search(text)
  local query = Store.fts_query(text)
  local found = {}
  if query == "" then
    return found
  end
  -- One query does it all; fetching each entry with get() would cost a
  -- query per match (see Chapter 18).
  for row in self.db:rows("SELECT " .. COLUMNS .. [[,
        snippet(search, -1, '[', ']', '...', 8) AS snippet
      FROM search JOIN entries e ON e.id = search.rowid
      WHERE search MATCH ? ORDER BY rank]], { query }) do
    local entry = to_entry(row)
    entry.snippet = row.snippet
    found[#found + 1] = entry
  end
  return found
end

-- The saved page of an entry, uncompressed, or nil if there is none.
function Store:page(id)
  local row = self.db:first("SELECT data FROM pages WHERE entry_id = ?", { id })
  if row == nil then
    return nil
  end
  local page, err = compress.unpack(row.data)
  if page == nil then
    errors.fail("the saved page of #%d is damaged: %s", id, err)
  end
  return page
end

-- The size of the saved page and the bytes it takes in the database.
function Store:page_size(id)
  local row = self.db:first("SELECT size, length(data) AS stored FROM pages WHERE entry_id = ?",
                            { id })
  if row then
    return row.size, row.stored
  end
end

function Store:stats()
  return self.db:first([[
    SELECT (SELECT count(*) FROM entries) AS entries,
           (SELECT count(DISTINCT tag) FROM tags) AS tags,
           (SELECT count(*) FROM pages) AS pages,
           (SELECT coalesce(sum(size), 0) FROM pages) AS size,
           (SELECT coalesce(sum(length(data)), 0) FROM pages) AS stored]])
end

-- Returns { {tag=, count=}, ... }: most used first, then by name.
function Store:tags()
  local rows = {}
  for row in self.db:rows("SELECT tag, count(*) AS count FROM tags GROUP BY tag "
                          .. "ORDER BY count DESC, tag") do
    rows[#rows + 1] = row
  end
  return rows
end

return Store
