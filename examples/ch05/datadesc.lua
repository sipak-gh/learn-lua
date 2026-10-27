-- Tables plus the f{...} call syntax make a data description language.
-- This file could be written by a user, as a config or data file.
local books = {}

local function Book(fields)
  assert(fields.title, "a book needs a title")  -- assert: Chapter 9
  fields.tags = fields.tags or {}
  books[#books + 1] = fields
end

Book{ title = "Programming in Lua", year = 2016, tags = { "lua" } }
Book{ title = "The C Programming Language", year = 1988, tags = { "c", "classic" } }
Book{ title = "SICP", year = 1985 }

for _, b in ipairs(books) do
  print(b.year, b.title, "[" .. table.concat(b.tags, ",") .. "]")
end

-- A plain table works as a record of settings, with defaults.
local defaults = { width = 80, color = "auto", limit = 20 }
local user = { color = "never" }
local settings = {}
for k, v in pairs(defaults) do settings[k] = v end
for k, v in pairs(user) do settings[k] = v end
print(settings.width, settings.color, settings.limit)
