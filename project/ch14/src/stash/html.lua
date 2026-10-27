-- Just enough HTML handling for stash: Lua patterns, not a real parser.

local M = {}

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }

-- Replaces &amp; &lt; ... and numeric &#65; / &#x41; references (ASCII only).
function M.decode_entities(s)
  return (s:gsub("&(#?)([xX]?)(%w+);", function(hash, x, name)
    if hash == "" then
      return ENTITIES[name]                  -- nil keeps the original text
    end
    local code = tonumber(name, x == "" and 10 or 16)
    if code and code < 128 then
      return string.char(code)
    end
  end))
end

-- Collapses runs of whitespace into one space and trims the ends.
function M.squeeze(s)
  return (s:gsub("%s+", " "):match("^ ?(.-) ?$"))
end

-- Lua patterns have no "ignore case" flag; [tT][iI]... does the job.
local function nocase(word)
  return (word:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end))
end

local TITLE = "<" .. nocase("title") .. "[^>]*>(.-)</" .. nocase("title") .. "%s*>"

-- The text of the <title> element, or nil.
function M.title(html)
  local title = html:match(TITLE)
  if title == nil then
    return nil
  end
  title = M.squeeze(M.decode_entities(title))
  if title == "" then
    return nil
  end
  return title
end

return M
