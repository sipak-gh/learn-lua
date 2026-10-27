-- os.time, os.date, os.difftime, os.clock

-- os.time() with no argument: seconds since 1970-01-01 00:00 UTC (the "epoch").
local now = os.time()
print("now is a number:", type(now))

-- A fixed timestamp keeps this output the same on every run.
local t = 1767225600

-- os.date(format, time). A leading "!" means UTC; without it you get local time.
print(os.date("!%Y-%m-%d %H:%M:%S", t))
print(os.date("!%A, %d %B %Y", t))

-- "*t" (or "!*t") returns a table of fields instead of a string.
local d = os.date("!*t", t)
print(d.year, d.month, d.day, d.hour, d.min, d.sec, d.wday, d.yday)

-- os.time(table) goes the other way, but reads the table as LOCAL time.
-- Run with TZ=UTC so local time and UTC agree.
print(os.time({ year = 2026, month = 1, day = 1, hour = 0 }))

-- Fields may overflow; os.time normalizes them.
print(os.date("!%Y-%m-%d", os.time({ year = 2026, month = 1, day = 32, hour = 0 })))

-- os.difftime(t2, t1) = t2 - t1 in seconds (as a float).
print(os.difftime(t + 90, t))

-- os.clock(): CPU time used by this program, in seconds. Good for timing code.
local start = os.clock()
local x = 0
for i = 1, 1e7 do x = x + i end
print(("loop took %.3f s of CPU"):format(os.clock() - start))
