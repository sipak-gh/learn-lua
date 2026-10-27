-- io.popen runs a shell command and connects a pipe to it.

-- Mode "r": read what the command prints.
local p = assert(io.popen("echo one; echo two", "r"))
for line in p:lines() do
  print("got: " .. line)
end
print("close:", p:close())   -- LuaJIT returns just true here, not the exit code

-- Mode "w": write to the command's stdin.
p = assert(io.popen("tr a-z A-Z", "w"))
p:write("shouted through a pipe\n")
p:close()

-- To get the exit status, have the shell print it.
p = assert(io.popen("ls missing-dir 2>/dev/null; echo \"[exit $?]\""))
print(p:read("*a"))
p:close()
