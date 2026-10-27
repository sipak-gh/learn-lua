-- Which Lua am I running?
print(_VERSION)               -- the language level: always "Lua 5.1" in LuaJIT
print(jit.version)            -- the LuaJIT build
print(jit.os, jit.arch)       -- the platform
