-- Switching the JIT off and on, for everything or for one function.
print(jit.version, jit.arch)
print(jit.status())                          -- on?, then the CPU features and options

local function sum(n)
  local s = 0
  for i = 1, n do
    local p = { x = i, y = 0.5 }             -- a new table every time?
    s = s + p.x * p.y
  end
  return s
end

local function time(name)
  local start = os.clock()
  sum(1e7)
  print(("%-22s %6.1f ms"):format(name, (os.clock() - start) * 1000))
end

time("compiled")
jit.off(sum)                                 -- this function: interpreter only
time("jit.off(sum)")
jit.on(sum)
time("jit.on(sum)")

jit.off()                                    -- the whole VM, like luajit -joff
print(jit.status())
