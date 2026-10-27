local config = require("stash.config")

test("a missing file gives the defaults", function()
  local settings = config.load("test/fixtures/no-such-file.lua")
  eq(settings.list_limit, 20)
  same(settings.aliases, {})
end)

test("settings come from the file", function()
  local settings = config.load("test/fixtures/config_ok.lua")
  eq(settings.list_limit, 5)
  eq(settings.aliases.ls, "list")
end)

test("unknown settings and wrong types are reported", function()
  local settings, err = config.load("test/fixtures/config_typo.lua")
  eq(settings, nil)
  eq(err, "test/fixtures/config_typo.lua: unknown setting 'list_limt'")
  eq(select(2, config.load("test/fixtures/config_type.lua")),
     "test/fixtures/config_type.lua: 'list_limit' must be a number")
end)

test("some settings only accept a few values", function()
  eq(select(2, config.load("test/fixtures/config_choice.lua")),
     "test/fixtures/config_choice.lua: 'color' must be one of auto, always, never")
end)
