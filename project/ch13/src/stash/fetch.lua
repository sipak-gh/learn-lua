-- Fetching pages. For now only file:// URLs, read with the io library.

local fs = require("stash.fs")

local M = {}

-- "file:///tmp/my%20page.html" -> "/tmp/my page.html"
local function file_path(url)
  local path = url:match("^file://(/.*)$")
  if path == nil then
    return nil
  end
  return (path:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

function M.can_fetch(url)
  return file_path(url) ~= nil
end

-- Returns the body of the page, or nil and an error message.
function M.get(url)
  local path = file_path(url)
  if path == nil then
    return nil, "cannot fetch " .. url
  end
  return fs.read_file(path)
end

return M
