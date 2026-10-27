-- Small string helpers shared by several modules.

local M = {}

-- Splits "a, b,,c" into { "a", "b", "c" }: pieces are trimmed, empty ones dropped.
function M.split(s, sep)
  local parts = {}
  for piece in s:gmatch("[^" .. sep .. "]+") do
    piece = piece:match("^%s*(.-)%s*$")
    if piece ~= "" then
      parts[#parts + 1] = piece
    end
  end
  return parts
end

-- Shortens s to at most `width` characters, marking the cut with "...".
function M.truncate(s, width)
  if #s <= width then
    return s
  end
  return s:sub(1, width - 3) .. "..."
end

-- "https://www.lua.org/pil/?x=1" -> "www.lua.org/pil"
function M.title_from_url(url)
  local rest = url:match("^%a[%w+.-]*://([^?#]*)") or url
  return (rest:gsub("/+$", ""))
end

-- The current time in seconds since 1970. STASH_NOW overrides it, so
-- tests and examples get the same dates on every run.
function M.now()
  return tonumber(os.getenv("STASH_NOW")) or os.time()
end

-- Dates are shown in UTC ("!" in the format), again so that output does
-- not depend on the machine's time zone.
function M.date(t)
  return os.date("!%Y-%m-%d", t)
end

function M.datetime(t)
  return os.date("!%Y-%m-%d %H:%M UTC", t)
end

return M
