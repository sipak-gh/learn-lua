-- string.format: printf-style formatting.
local fmt = string.format

print(fmt("%d apples, %5d|, %-5d|, %05d", 3, 42, 42, 42))
print(fmt("%.2f  %8.3f|  %e  %g  %g", math.pi, math.pi, 12345.678, 0.1, 1e20))
print(fmt("%x %X %o %c", 255, 255, 8, 65))
print(fmt("[%s] [%10s] [%-10s] [%.3s]", "lua", "lua", "lua", "luajit"))
print(fmt("%q", 'say "hi"\n'))    -- quoted so Lua can read it back
print(fmt("%s %s %s", nil, true, 12)) -- %s calls tostring
print(fmt("100%% done"))
print(fmt("%d", 3.99))                -- %d cuts the fraction
