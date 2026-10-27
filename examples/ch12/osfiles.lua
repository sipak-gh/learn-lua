-- os.getenv, os.rename, os.remove, os.execute, os.exit

print("HOME set?", os.getenv("HOME") ~= nil)
print("NOPE:", os.getenv("STASH_DOES_NOT_EXIST"))   -- nil when unset

-- Write to a temporary name, then rename over the real file.
-- On POSIX, rename within one filesystem replaces the target in one step.
local f = assert(io.open("data.txt.tmp", "w"))
f:write("new contents\n")
f:close()
print("rename:", os.rename("data.txt.tmp", "data.txt"))
print("remove:", os.remove("data.txt"))
print("again: ", os.remove("data.txt"))

-- os.execute runs a shell command. LuaJIT returns the raw wait status:
-- 0 for success, exit code * 256 otherwise.
print("true  ->", os.execute("true"))
print("exit 3->", os.execute("exit 3"))
print("shell? ->", os.execute())    -- no argument: nonzero if a shell exists

-- os.exit(code) ends the program right away. true = 0, false = 1.
os.exit(4)
print("never printed")
