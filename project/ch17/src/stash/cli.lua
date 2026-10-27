-- Command-line parsing.

local util = require("stash.util")

local M = {}

-- Parses args[first], args[first+1], ... using a spec that maps each flag
-- to { field, kind }. Kinds: "flag" (no value), "value", "number", "list"
-- (may repeat, values may be comma-separated). Returns an options table:
-- named fields for flags, and the remaining (positional) arguments at 1, 2, 3...
-- On a bad argument it returns nil plus a message.
function M.parse(args, first, spec)
  local opts = {}
  local i = first
  while i <= #args do
    local a = args[i]
    local option = spec[a]
    if option == nil then
      if a:sub(1, 1) == "-" and a ~= "-" then
        return nil, "unknown option " .. a
      end
      opts[#opts + 1] = a
    else
      local field, kind = option[1], option[2]
      if kind == "flag" then
        opts[field] = true
      else
        i = i + 1
        local value = args[i]
        if value == nil then
          return nil, a .. " needs a value"
        end
        if kind == "number" then
          value = tonumber(value)
          if value == nil then
            return nil, a .. " needs a number"
          end
        end
        if kind == "list" then
          opts[field] = opts[field] or {}
          for _, item in ipairs(util.split(value, ",")) do
            table.insert(opts[field], item)
          end
        else
          opts[field] = value
        end
      end
    end
    i = i + 1
  end
  return opts
end

return M
