-- wordcount: counts the words of saved pages.
--
--   stash words          words per bookmark
--   stash words ID       the most common words of one page

local function count_words(text)
  local counts, total = {}, 0
  for word in text:lower():gmatch("%a+") do
    counts[word] = (counts[word] or 0) + 1
    total = total + 1
  end
  return counts, total
end

-- The `top` most frequent words of at least 3 letters, ties in a-z order.
local function most_common(counts, top)
  local words = {}
  for word in pairs(counts) do
    if #word >= 3 then
      words[#words + 1] = word
    end
  end
  table.sort(words, function(a, b)
    if counts[a] ~= counts[b] then
      return counts[a] > counts[b]
    end
    return a < b
  end)
  local result = {}
  for i = 1, math.min(top, #words) do
    result[i] = words[i]
  end
  return result
end

stash.command("words", {
  usage = "words [ID] [--top N]",
  help = "count the words of saved pages",
  options = { ["--top"] = { "top", "number" } },
  run = function(opts)
    if opts[1] == nil then
      for entry in stash.entries() do
        local page = stash.page(entry.id)
        local _, total = count_words(page and stash.text(page) or "")
        stash.print(("%3d  %5d  %s"):format(entry.id, total, entry.title))
      end
      return
    end
    local id = tonumber(opts[1])
    local entry = id and stash.get(id) or stash.not_found("no entry with id %s", opts[1])
    local page = stash.page(id) or stash.not_found("no saved page for #%d", id)
    local counts, total = count_words(stash.text(page))
    stash.print(("%d words in #%d %s"):format(total, id, entry.title))
    for _, word in ipairs(most_common(counts, opts.top or 5)) do
      stash.print(("%5d  %s"):format(counts[word], stash.paint(word, "tag")))
    end
  end,
})
