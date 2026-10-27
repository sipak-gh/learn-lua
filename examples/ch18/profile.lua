-- Where does the time go? Run: luajit -jp=F profile.lua

local WORDS = { "lua", "jit", "trace", "table", "string", "buffer", "ffi" }

local function make_text(n)                  -- n words, as one string
  local words = {}
  for i = 1, n do
    words[i] = WORDS[i % #WORDS + 1] .. (i % 50)
  end
  return table.concat(words, " ")
end

local function count_words(text)
  local counts = {}
  for word in text:gmatch("%a+") do          -- letters only: "lua17" -> "lua"
    counts[word] = (counts[word] or 0) + 1
  end
  return counts
end

local function top(counts)
  local list = {}
  for word, n in pairs(counts) do
    list[#list + 1] = { word = word, n = n }
  end
  table.sort(list, function(a, b) return a.n > b.n or (a.n == b.n and a.word < b.word) end)
  return list[1].word, list[1].n
end

local text = make_text(2e6)
local counts
for _ = 1, 5 do
  counts = count_words(text)
end
print(top(counts))
