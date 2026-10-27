-- Ask the terminal for its size with ioctl(TIOCGWINSZ).

local ffi = require("ffi")
ffi.cdef [[
struct winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
int ioctl(int fd, unsigned long request, ...);
char *strerror(int errnum);
]]
local TIOCGWINSZ = ffi.os == "OSX" and 0x40087468 or 0x5413

local ws = ffi.new("struct winsize")      -- C fills this in (an out parameter)
if ffi.C.ioctl(1, TIOCGWINSZ, ws) == 0 then
  print(("terminal: %d columns x %d rows"):format(ws.ws_col, ws.ws_row))
else
  local e = ffi.errno()
  print("not a terminal: " .. ffi.string(ffi.C.strerror(e)) .. " (errno " .. e .. ")")
end
