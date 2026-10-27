# stash

A command-line bookmark manager with full-text search, written in Lua for
LuaJIT. stash saves a URL, downloads the page, and keeps its text
searchable and its HTML compressed in an SQLite database. It is the
project of the course *Learn Lua (LuaJIT) by Building stash*.

```
$ stash add file://$PWD/test/fixtures/lua.html -t lua,lang
added #1 The Programming Language Lua
$ stash search scripting
  1  The Programming Language Lua          lang,lua          2026-01-01
     ...a small, fast [scripting] language built to be...
```

## Requirements

- LuaJIT 2.1 (any build from 2023 or later)
- The shared libraries SQLite 3 (with FTS5), libcurl and zlib. On
  Debian/Ubuntu: `libsqlite3-0 libcurl4 zlib1g`.
- To build the single-file program: a C compiler, LuaJIT's headers and
  static library, and the static SQLite and zlib libraries
  (`libsqlite3-dev zlib1g-dev`).

## Running

From this directory, without building anything:

```
./stash help
```

Or build the single-file program `build/stash`, which needs neither
LuaJIT nor the Lua sources to run (libcurl is still loaded at run time):

```
make
make test        # the tests with luajit, then end-to-end with build/stash
make clean
```

## Commands

```
add URL [-t TAGS] [-n NOTE] [--no-fetch]  save a bookmark
list [-t TAG] [-m PATTERN] [--limit N]    list bookmarks
search WORDS...                           full-text search, best matches first
show ID [--body]                          show one bookmark, or its saved page
rm ID                                     delete a bookmark
tags                                      count bookmarks per tag
export [FILE]                             write all bookmarks as JSON
stats                                     count entries and the space pages take
plugins                                   list the loaded plugins
help                                      show this help
version [-v]                              print the version (-v: and the libraries' versions)
```

Exit codes: 0 success, 1 not found (or no search results), 2 usage error
or failure.

## Files and settings

Data lives in `$STASH_HOME` (default `~/.local/share/stash`):

- `stash.db`: the SQLite database.
- `config.lua`: settings, as Lua assignments:

  ```lua
  list_limit = 10
  aliases = { ls = "list", lua = "list -t lua" }
  color = "auto"                         -- or "always", "never"
  user_agent = "stash"
  timeout = 10                           -- seconds per download
  plugins = { "autotag", "wordcount", "checksum" }
  trusted_plugins = { "checksum" }       -- may use require and the FFI
  ```

- `plugins/NAME.lua`: plugins. `plugins/` here has three examples.

Environment: `STASH_HOME`; `NO_COLOR` turns color off; `COLUMNS` sets the
width when stdout is not a terminal; `STASH_NOW` (seconds since 1970)
fixes the clock, for tests; `STASH_DEBUG` adds tracebacks to internal
errors.

## Plugins

A plugin is a Lua file run in a sandbox that holds a few safe globals and
the `stash` table:

```lua
stash.command("hello", {
  usage = "hello [NAME]",
  help = "say hello",
  run = function(opts) stash.print("hello, " .. (opts[1] or "world")) end,
})
stash.on("add", function(entry) entry.tags[#entry.tags + 1] = "new" end)
```

The rest of the API: `stash.entries()`, `stash.get(id)`, `stash.page(id)`,
`stash.text(html)`, `stash.paint(text, style)`, `stash.fail(fmt, ...)`,
`stash.not_found(fmt, ...)`. The sandbox stops accidents, not attacks:
only install plugins you trust as much as any other program.

## Layout

```
stash                launcher: runs src/ with luajit
src/stash/           the modules; src/stash/ffi/ holds the C bindings
plugins/             example plugins
test/run.lua         test runner: luajit test/run.lua [FILTER]
bench/               benchmarks: luajit bench/run.lua [-p] [FILTER]
host/, Makefile      the single-file build
```
