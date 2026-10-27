-- Most io and os functions report failure as: nil, message, errno.

local f, err, code = io.open("missing.txt")
print(f, err, code)

-- Pattern 1: check and handle.
if not f then
  print("could not open: " .. err)
end

-- Pattern 2: assert turns the failure into an error with that message.
print(pcall(function() return assert(io.open("missing.txt")) end))

-- io.type tells files apart from other values.
local h = assert(io.open(arg[0]))           -- arg[0] is this script
print(io.type(h), io.type(io.stdout), io.type("a string"))
h:close()
print(io.type(h))

-- Using a closed file is a real error, not a nil return.
print(pcall(h.read, h, "*l"))

-- os.remove and os.rename follow the same nil, message, errno convention.
print(os.remove("missing.txt"))
print(os.rename("missing.txt", "other.txt"))
