-- A clock for measuring: seconds since some fixed moment, with
-- nanosecond resolution. os.clock() counts CPU time of this process
-- only; a monotonic clock counts real time and never jumps backwards.

local ffi = require("ffi")
local libc = require("stash.ffi.libc")

local M = {}

local ts = ffi.new("struct timespec")       -- made once, reused by every call

function M.now()
  ffi.C.clock_gettime(libc.CLOCK_MONOTONIC, ts)
  return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

return M
