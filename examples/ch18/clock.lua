-- Two clocks: CPU time (os.clock) and real time (clock_gettime).
local ffi = require("ffi")

ffi.cdef [[
struct timespec { long tv_sec; long tv_nsec; };
int clock_gettime(int clock, struct timespec *tp);
int poll(void *fds, unsigned long nfds, int timeout);
]]
local CLOCK_MONOTONIC = ffi.os == "OSX" and 6 or 1

local ts = ffi.new("struct timespec")
local function now()
  ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
  return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

local function time(name, fn)
  local cpu, real = os.clock(), now()
  fn()
  print(("%-6s cpu %.2f s   real %.2f s"):format(name, os.clock() - cpu, now() - real))
end

time("work", function()                      -- busy: both clocks advance
  local x = 0
  for i = 1, 1e8 do x = x + i % 7 end
end)
time("sleep", function()                     -- waiting: only real time passes
  ffi.C.poll(nil, 0, 300)                    -- sleep 300 ms
end)
