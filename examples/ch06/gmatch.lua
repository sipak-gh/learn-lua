-- gmatch returns an iterator over all matches.
for word in ("the quick brown fox"):gmatch("%a+") do
  io.write("[", word, "] ")
end
print()

-- With captures, each step returns the captures.
local settings = {}
for key, value in ("width=80, height=24, title=stash"):gmatch("(%w+)=(%w+)") do
  settings[key] = value
end
print(settings.width, settings.height, settings.title)

-- Splitting lines: match "everything that is not a newline".
local text = "first\nsecond\n\nfourth"
for line in text:gmatch("[^\n]+") do
  print("line:", line)          -- note: the empty line is skipped
end
