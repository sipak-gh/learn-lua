# Learn Lua (LuaJIT) by Building `stash`

This course teaches Lua from first principles, using LuaJIT. Then it shows Lua's superpower: a small
scripting language, built around one flexible data structure (the table), with direct access to the
huge world of C libraries through LuaJIT's FFI.

You build **`stash`**, a command-line bookmark manager. Its core is pure Lua; it reaches into C for
everything heavy:

- **SQLite** for storage and full-text search
- **libcurl** for fetching pages
- **zlib** for compression
- **libc** for terminal tricks

Users extend it with Lua plugins. At the end you package it as a single binary, using a tiny C host
program that embeds LuaJIT. The finished program, run from `project/ch21/`:

```console
$ ./stash add file://$PWD/test/fixtures/lua.html -t lua,lang
added #1 The Programming Language Lua
$ ./stash add file://$PWD/test/fixtures/luajit.html -t lua,jit
added #2 LuaJIT: a Just-In-Time Compiler & FFI
$ ./stash search fast
  1  The Programming Language Lua          lang,lua          2026-01-01
     ...is a small, [fast] scripting language built to...
  2  LuaJIT: a Just-In-Time Compiler &...  jit,lua           2026-01-01
     ...Lua code very [fast] with a tracing JIT...
```

## Requirements

| Tool | Version |
|------|---------|
| LuaJIT | 2.1, any build from 2023 or later (`luajit -v` prints `LuaJIT 2.1.<timestamp>`) |
| C compiler | gcc or clang (Chapters 13+ need headers; Chapter 20 compiles C) |
| LuaJIT headers and static library | from the same build (Chapter 20) |
| SQLite 3 | 3.35 or newer, with FTS5 (dev package with headers and static library) |
| zlib, libcurl | any recent version (dev packages with headers; zlib's static library) |
| pkg-config | any |

Installation is not covered. LuaJIT runs Lua 5.1 code, plus its own extensions.
[Appendix C](appendix-c-lua-versions.md) covers what changes in PUC Lua 5.4 and 5.5.

You should already know one programming language.

## How to use this course

- **Read in order.** Each chapter uses only what earlier chapters taught.
- **Type the code.** Commands start with `$` and are followed by their output.
- **Examples:** run one with `luajit examples/chNN/<name>.lua`.
- **Project snapshots:** `project/chNN/` holds the full project as it stands at the end of
  chapter NN. If you get stuck, compare your code with it.
- **Exercises** end each chapter. Their solutions are hidden in collapsible blocks.

## Table of contents

**Part I: The Lua Language**

| # | Chapter | `stash` milestone |
|---|---------|-------------------|
| 1 | [Getting Started](01-getting-started.md) | A script that prints usage |
| 2 | [Values and Types](02-values-and-types.md) | A version and the first argument |
| 3 | [Control Flow](03-control-flow.md) | Flags anywhere in the arguments |
| 4 | [Functions](04-functions.md) | Command handlers |
| 5 | [Tables](05-tables.md) | Dispatch table, options, an in-memory store |
| 6 | [Strings and Patterns](06-strings.md) | Tags, titles, search and columns |
| 7 | [Metatables and Objects](07-metatables-and-objects.md) | `Entry` and `MemoryStore` classes |
| 8 | [Modules](08-modules.md) | Modules and a config file |
| 9 | [Errors](09-errors.md) | Error handling and exit codes |
| 10 | [Testing](10-testing.md) | A test runner written in Lua |
| 11 | [Coroutines](11-coroutines.md) | Streaming iterators |
| 12 | [I/O and the OS](12-io-and-os.md) | Saving to a file, reading pages, JSON export |

**Part II: The C World through the FFI**

| # | Chapter | `stash` milestone |
|---|---------|-------------------|
| 13 | [FFI Basics](13-ffi-basics.md) | `mkdir` and colors via libc |
| 14 | [C Data](14-c-data.md) | Terminal width and a C byte buffer |
| 15 | [Wrapping SQLite](15-wrapping-sqlite.md) | SQLite storage and full-text search |
| 16 | [Callbacks and libcurl](16-callbacks-and-curl.md) | Downloads with libcurl; a Lua `REGEXP` in SQL |
| 17 | [Binary Data and zlib](17-binary-data-and-zlib.md) | Compressed page bodies |
| 18 | [Performance and the JIT](18-performance-and-the-jit.md) | Benchmarks, profiling and fixes |
| 19 | [Plugins and Scripting](19-plugins-and-scripting.md) | A plugin system |

**Part III: Shipping**

| # | Chapter | `stash` milestone |
|---|---------|-------------------|
| 20 | [Embedding LuaJIT](20-embedding-luajit.md) | A single binary |
| 21 | [Design and Next Steps](21-design-and-next-steps.md) | Version 1.0.0 and a README |

**Appendices:** [A: Cheat Sheet](appendix-a-cheatsheet.md) ·
[B: FFI Reference](appendix-b-ffi-reference.md) · [C: Lua Versions](appendix-c-lua-versions.md)

References: [REFERENCES.md](REFERENCES.md) lists the sources behind each chapter, with archived
(Wayback Machine) copies of every link.
