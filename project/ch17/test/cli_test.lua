local cli = require("stash.cli")

local spec = {
  ["-t"] = { "tags", "list" },
  ["-n"] = { "note", "value" },
  ["--limit"] = { "limit", "number" },
  ["--body"] = { "body", "flag" },
}

test("positional arguments keep their order", function()
  same(cli.parse({ "add", "a", "b" }, 2, spec), { "a", "b" })
end)

test("options of every kind", function()
  local opts = cli.parse({ "x", "-n", "hi", "--limit", "5", "--body", "url" }, 1, spec)
  same(opts, { "x", "url", note = "hi", limit = 5, body = true })
end)

test("list options repeat and split on commas", function()
  local opts = cli.parse({ "-t", "a,b", "-t", "c" }, 1, spec)
  same(opts.tags, { "a", "b", "c" })
end)

test("errors come back as nil plus a message", function()
  local opts, err = cli.parse({ "--limit" }, 1, spec)
  eq(opts, nil)
  eq(err, "--limit needs a value")
  eq(select(2, cli.parse({ "--limit", "many" }, 1, spec)), "--limit needs a number")
  eq(select(2, cli.parse({ "--verbose" }, 1, spec)), "unknown option --verbose")
end)

test("a lone dash is positional", function()
  same(cli.parse({ "-" }, 1, spec), { "-" })
end)
