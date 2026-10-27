-- The three standard streams: io.stdin, io.stdout, io.stderr.

-- print adds tabs and a newline and calls tostring on everything.
print("print:", 1, nil, true)

-- io.write writes exactly what you give it (strings and numbers only).
io.write("io.write: ", 1, " ", 2.5, "\n")

-- io.write is short for io.output():write. io.stdout:write is the same here.
io.stdout:write("stdout:write\n")

-- Errors and diagnostics go to stderr, so they don't mix with real output.
io.stderr:write("stderr: something went wrong\n")

-- io.read reads from stdin. Here we read every line that was piped in.
local count = 0
for line in io.lines() do          -- io.lines() with no file = stdin
  count = count + 1
  io.write(("stdin %d: %s\n"):format(count, line))
end
print("lines on stdin:", count)
