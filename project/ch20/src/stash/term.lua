-- Terminal output: color, but only when a person is watching.

local ffi = require("ffi")
local libc = require("stash.ffi.libc")

local M = {}

-- ANSI escape codes ("Select Graphic Rendition") for each kind of text.
local STYLES = {
  id = "33",                                 -- yellow
  tag = "36",                                -- cyan
  dim = "2",
}

-- True when file descriptor fd (1 = stdout) is a terminal, not a pipe
-- or a file. isatty returns a C int, which arrives as a Lua number.
function M.is_tty(fd)
  return ffi.C.isatty(fd) == 1
end

-- The width of the terminal in columns. ioctl fills in a struct we
-- allocate; when stdout is not a terminal there is no width to ask for,
-- so we fall back to $COLUMNS, then to 80.
function M.width()
  if M.is_tty(1) then
    local size = ffi.new("struct winsize")   -- zero-filled
    if ffi.C.ioctl(1, libc.TIOCGWINSZ, size) == 0 and size.ws_col > 0 then
      return size.ws_col
    end
  end
  return tonumber(os.getenv("COLUMNS")) or 80
end

-- Decides whether to use color, from the `color` setting:
-- "always", "never", or "auto" (a terminal, and NO_COLOR is not set).
function M.use_color(setting)
  if setting == "auto" then
    return M.is_tty(1) and os.getenv("NO_COLOR") == nil and os.getenv("TERM") ~= "dumb"
  end
  return setting == "always"
end

-- Returns a function paint(text, style). With color off it returns the
-- text unchanged, so callers never need to check.
function M.painter(enabled)
  if not enabled then
    return function(text)
      return text
    end
  end
  return function(text, style)
    return "\27[" .. STYLES[style] .. "m" .. text .. "\27[0m"
  end
end

return M
