-- error() raises an error; pcall catches it and returns false plus the message.
local function check_age(age)
  if type(age) ~= "number" then
    error("age must be a number")         -- level 1 (default): blames this line
  end
  if age < 0 then
    error("age must not be negative", 2)  -- level 2: blames the caller
  end
  return age
end

print(pcall(check_age, 30))
print(pcall(check_age, "old"))
print(pcall(function()
  local age = check_age(-1)               -- line 15: level 2 points here
  return age
end))
print(pcall(error, "no position", 0))     -- level 0: the message as is
