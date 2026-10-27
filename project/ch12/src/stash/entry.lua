-- Entry: one bookmark.

local util = require("stash.util")

local Entry = {}
Entry.__index = Entry

function Entry.new(fields)
  local self = setmetatable({}, Entry)
  self.id = fields.id                        -- nil until a store assigns one
  self.url = fields.url
  self.title = fields.title or util.title_from_url(fields.url)
  self.note = fields.note or ""
  self.created = fields.created or util.now()  -- seconds since 1970
  self.tags = {}
  for i, tag in ipairs(fields.tags or {}) do
    self.tags[i] = tag
  end
  table.sort(self.tags)
  return self
end

function Entry:has_tag(tag)
  for _, t in ipairs(self.tags) do
    if t == tag then
      return true
    end
  end
  return false
end

-- Case-insensitive substring search over the text fields.
function Entry:matches(term)
  term = term:lower()
  for _, field in ipairs({ self.title, self.url, self.note, self:tag_string(" ") }) do
    if field:lower():find(term, 1, true) then
      return true
    end
  end
  return false
end

function Entry:tag_string(sep)
  return table.concat(self.tags, sep or ",")
end

-- A plain table with the same fields and no metatable: what we save to
-- disk or export as JSON.
function Entry:record()
  local tags = {}
  for i, tag in ipairs(self.tags) do
    tags[i] = tag
  end
  return { id = self.id, url = self.url, title = self.title, note = self.note,
           tags = tags, created = self.created }
end

function Entry.__tostring(self)
  return ("#%d %s"):format(self.id or 0, self.title)
end

function Entry.__lt(a, b)
  return a.id < b.id
end

return Entry
