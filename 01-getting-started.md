# Chapter 1 — Getting Started

You learn what Lua and LuaJIT are and why this course uses LuaJIT. You run code three ways: at the
prompt, from a file, and as an executable script. You also start `stash`, the tool you build
through the course. [Chapter 2](02-values-and-types.md) starts on the language itself.

## What Lua is

Lua is a small scripting language, born in 1993 at PUC-Rio, a university in Rio de Janeiro,
Brazil. "Lua" is Portuguese for "moon". Write it "Lua", not "LUA".

Its design goals explain most of this course:

| Goal | What it means for you |
|------|-----------------------|
| **Small** | The whole language fits in your head. PUC Lua 5.5.1, source and docs, is about 390 KB compressed. |
| **Fast** | One of the fastest scripting languages. LuaJIT is faster still. |
| **Embeddable** | Lua is a C library first. Games, editors and web servers embed it so users can script them. |
| **One data structure** | The *table*. Arrays, dictionaries, objects, modules and namespaces are all tables. |
| **Mechanisms, not policies** | General building blocks (tables, functions, metatables), not fixed features. No `class` keyword, but you can build classes in a few lines ([Chapter 7](07-metatables-and-objects.md)). |

The last point is the heart of Lua: it stays small because each mechanism does many jobs. The
price: Lua sets few rules, so you make your own conventions.

## PUC Lua and LuaJIT

Two main implementations:

- **PUC Lua**: the reference implementation, by the language's authors. Versions 5.1 (2006), 5.2,
  5.3, 5.4 and 5.5 (December 2025). Each changed the language a little.
- **LuaJIT**: an independent implementation by Mike Pall, developed since 2005. It runs **Lua 5.1**
  plus some extensions. Its just-in-time (JIT) compiler turns hot Lua code into machine code.

Why LuaJIT:

1. **Speed.** It is one of the fastest dynamic language implementations. Hot loops over plain
   tables can come close to compiled C ([Chapter 18](18-performance-and-the-jit.md)).
2. **The FFI.** The *foreign function interface* lets Lua call C functions and use C data directly.
   Write a C declaration in a Lua string, then call the function. No glue code to write or compile,
   so a few lines of Lua open up the huge world of C libraries.

The FFI is the course's theme. Part I teaches Lua. Part II drives real C libraries (SQLite,
libcurl, zlib, libc) from Lua. Part III packs everything into one program.

LuaJIT 2.1 is a "rolling release" with no numbered point releases. Each build is named
`2.1.<timestamp>`, from its last commit. You need **LuaJIT 2.1, any build from 2023 or later**:

```console
$ luajit -v
LuaJIT 2.1.1792588164 -- Copyright (C) 2005-2026 Mike Pall. https://luajit.org/
```

Your number will differ. Anything starting with `LuaJIT 2.1.` is fine.

Lua 5.1 is old but no toy: OpenResty (nginx scripting), Neovim's plugin system and many games run on
LuaJIT. Where newer PUC Lua changed a 5.1 rule, the course says so.
[Appendix C](appendix-c-lua-versions.md) lists all the differences.

## The interactive prompt (REPL)

Run `luajit` with no arguments to get a prompt. Type a statement and press Enter.

```console
$ luajit
LuaJIT 2.1.1792588164 -- Copyright (C) 2005-2026 Mike Pall. https://luajit.org/
JIT: ON SSE3 SSE4.1 BMI2 fold cse dce fwd dse narrow loop abc sink fuse
> print("hello")
hello
> = 1 + 2
3
> 1 + 2
stdin:1: unexpected symbol near '1'
> x = 10
> = x * 2, x / 4
20	2.5
> for i = 1, 3 do
>> print(i)
>> end
1
2
3
> os.exit()
```

The `JIT:` line lists your CPU's features, so yours will differ.

- The prompt runs **statements**, not expressions. `1 + 2` alone is an error.
- Start a line with `=` to print values: `= 1 + 2` is short for `return 1 + 2`.
- `>>` means the statement isn't finished; the prompt waits for `end`.
- Leave with `os.exit()` or Ctrl-D (Ctrl-Z then Enter on Windows).

Use the prompt for quick tries, files for everything else.

## Running a script

A Lua program is a text file, usually ending in `.lua`. Code that runs as a unit is a **chunk**: a
file, or a line typed at the prompt.

`examples/ch01/hello.lua`

```lua
#!/usr/bin/env luajit
-- hello.lua: the smallest useful Lua program.
print("Hello, Lua!")
```

```console
$ luajit examples/ch01/hello.lua
Hello, Lua!
```

No `main` function, no compile step. LuaJIT compiles the file to bytecode in memory and runs it top
to bottom.

Other ways to run code:

| Command | What it does |
|---------|--------------|
| `luajit file.lua a b` | Run `file.lua` with arguments `a` and `b`. |
| `luajit -e 'print(1 + 1)'` | Run a chunk given on the command line. |
| `luajit -i file.lua` | Run the file, then open the prompt (its globals are still there). |
| `luajit -` | Read the chunk from standard input. |
| `luajit -v` | Print the version. |

```console
$ luajit -e 'print(1 + 1)'
2
$ echo 'print("from stdin")' | luajit -
from stdin
```

## Executable scripts: the `#!` line

The first line of `hello.lua` is a **shebang**. On Linux and macOS it tells the system which
program runs the file. Lua skips a first line that starts with `#`, so `luajit hello.lua` still
works.

Make the file executable once, then run it directly:

```console
$ chmod +x examples/ch01/hello.lua
$ ./examples/ch01/hello.lua
Hello, Lua!
```

`/usr/bin/env luajit` looks for `luajit` on your `PATH`. If it isn't there:

```console
$ ./examples/ch01/hello.lua
/usr/bin/env: ‘luajit’: No such file or directory
```

## `print`

`print` turns each argument into text, puts a tab between them, and ends with a newline.

`examples/ch01/print.lua`

```lua
-- print takes any number of values. It separates them with a tab
-- and ends the line with a newline.
print("one", 2, 3.5, true, nil)
print()                       -- an empty line
print("no parentheses needed for a single string:")
print "like this"
```

```console
$ luajit examples/ch01/print.lua
one	2	3.5	true	nil

no parentheses needed for a single string:
like this
```

You may drop the parentheses when the only argument is a literal string or a table constructor
([Chapter 4](04-functions.md)). Most code keeps them; DSL-style code uses the short form.

`print` is for quick output. For exact control (no tabs, no newline) use `io.write`
([Chapter 12](12-io-and-os.md)) and `string.format` ([Chapter 6](06-strings.md)).

## Comments

`examples/ch01/comments.lua`

```lua
-- A line comment starts with two dashes.

--[[ A block comment starts with two dashes and two
     opening brackets. Two closing brackets end it. ]]

--[==[ Put equals signs between the brackets when the
     text contains two closing brackets, like a[b[1]].
     The comment ends at closing brackets with the same
     number of equals signs. ]==]

---[[ Delete the first dash of this line to comment out the block.
print("this line runs")
--]]

print("done")
```

```console
$ luajit examples/ch01/comments.lua
this line runs
done
```

The last block is a common trick. `---[[` and `--]]` are both line comments, so the `print` runs.
Delete one dash: `--[[` now opens a block comment that ends at `--]]`, and the `print` is gone.

Gotcha: the first `]]` (or `]==]` for that level) ends a block comment, even mid-sentence. If your
text contains `]]`, add equals signs.

## Command-line arguments: `arg`

`luajit` puts the script's arguments in a global table named `arg`. Tables come in
[Chapter 5](05-tables.md); for now, `arg[1]` is the first argument, `arg[2]` the second, and so on.

`examples/ch01/args.lua`

```lua
-- The command-line arguments live in the global table `arg`.
print("interpreter:", arg[-1])
print("script:     ", arg[0])
print("first:      ", arg[1])
print("second:     ", arg[2])
print("count:      ", #arg)   -- # is the length operator (Chapter 2)
```

```console
$ luajit examples/ch01/args.lua apple "banana split"
interpreter:	luajit
script:     	examples/ch01/args.lua
first:      	apple
second:     	banana split
count:      	2
$ luajit examples/ch01/args.lua
interpreter:	luajit
script:     	examples/ch01/args.lua
first:      	nil
second:     	nil
count:      	0
```

- `arg[0]` is the script name. Negative indexes hold the interpreter and its options.
- A missing argument is `nil`, Lua's "no value". Reading it is not an error.
- The shell, not Lua, splits the command line. Quotes keep `"banana split"` as one argument.

## Errors

When something goes wrong, LuaJIT prints the file, line and message, then stops.

`examples/ch01/oops.lua`

```lua
print("this line is fine")
pritn("this one has a typo")
```

```console
$ luajit examples/ch01/oops.lua
this line is fine
luajit: examples/ch01/oops.lua:2: attempt to call global 'pritn' (a nil value)
stack traceback:
	examples/ch01/oops.lua:2: in main chunk
	[C]: at 0x584a193183a0
```

(The address on the last line changes from run to run.)

Line 2 tried to call `pritn`. Nothing has that name, so its value is `nil`, and you can't call
`nil`. Line 1 ran first: Lua finds this kind of mistake only when the line runs.

A *syntax* error is found while reading the file, so nothing runs. Here `bad.lua` is the one line
`print("hi"`, missing its `)`:

```console
$ luajit bad.lua
luajit: bad.lua:2: ')' expected (to close '(' at line 1) near '<eof>'
```

## Syntax at a glance

- Statements need no separator; a newline is just whitespace. `;` is allowed but rare.
- Names are case-sensitive (`print` ≠ `Print`): letters, digits and `_`, not starting with a digit.
- Blocks end with `end`. No braces; indentation doesn't matter.
- Reserved words:

```text
and       break     do        else      elseif    end
false     for       function  if        in        local
nil       not       or        repeat    return    then
true      until     while
```

LuaJIT also has `goto`, borrowed from Lua 5.2 ([Chapter 3](03-control-flow.md)). To keep old 5.1
code working, a standard LuaJIT build still accepts `goto` as a variable name. Don't use it as one:
Lua 5.2 and later reserve it.

## Which Lua am I running?

`examples/ch01/version.lua`

```lua
-- Which Lua am I running?
print(_VERSION)               -- the language level: always "Lua 5.1" in LuaJIT
print(jit.version)            -- the LuaJIT build
print(jit.os, jit.arch)       -- the platform
```

```console
$ luajit examples/ch01/version.lua
Lua 5.1
LuaJIT 2.1.1792588164
Linux	x64
```

The last two lines depend on your build and machine. `jit` is a LuaJIT-only library.

## Building stash: a script that prints usage

`stash` is a command-line bookmark keeper. By the end of the course it will:

- fetch a web page with libcurl and pull out its title,
- store it, compressed with zlib, in an SQLite database with full-text search,
- print colored, width-aware tables,
- load Lua plugins that add commands,
- ship as one binary.

Each chapter adds a step. Step one prints how to use it.

Make a new directory for the project and create `stash.lua` in it:

`stash.lua`

```lua
#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 1: the program only prints how to use it.
-- Run it with:  luajit stash.lua   (or ./stash.lua after chmod +x)

print("stash - a scriptable bookmark keeper")
print()
print("usage: stash <command> [arguments]")
print()
print("commands:")
print("  add URL       save a bookmark")
print("  list          list bookmarks")
print("  search TERM   search bookmarks")
print("  show ID       show one bookmark")
print("  rm ID         delete a bookmark")
print("  help          show this help")
```

Only `print` calls for now. The usage text is the plan; later chapters make each command real.

### Checkpoint

Run these in the project directory:

```console
$ luajit stash.lua
stash - a scriptable bookmark keeper

usage: stash <command> [arguments]

commands:
  add URL       save a bookmark
  list          list bookmarks
  search TERM   search bookmarks
  show ID       show one bookmark
  rm ID         delete a bookmark
  help          show this help
$ chmod +x stash.lua
$ ./stash.lua | head -3
stash - a scriptable bookmark keeper

usage: stash <command> [arguments]
```

The complete project at this point is in `project/ch01/`.

## Summary

- Lua is small, fast and embeddable. Its design is "mechanisms, not policies"; the table is its only
  data structure.
- LuaJIT runs Lua 5.1 plus extensions, a JIT compiler, and the FFI, which calls C directly.
- `luajit` alone opens a prompt; `= expr` prints a value there.
- `luajit file.lua args...` runs a script top to bottom. No `main`, no compile step.
- A `#!/usr/bin/env luajit` first line plus `chmod +x` makes a script executable.
- `print(a, b, ...)` writes values separated by tabs.
- `--` starts a line comment, `--[[ ... ]]` a block comment; add `=` signs if the text holds `]]`.
- `arg[1]`, `arg[2]`, ... are the command-line arguments. `arg[0]` is the script.
- Runtime errors show `file:line: message` and a traceback. Lua finds most mistakes only when the
  line runs.

## Exercises

1. Write `greet.lua` that prints `Hello` and the first argument, separated by a tab. What does it
   print with no argument?

<details><summary>Solution</summary>

```lua
print("Hello", arg[1])
```

```console
$ luajit greet.lua Ada
Hello	Ada
$ luajit greet.lua
Hello	nil
```

A missing argument is `nil`, and `print` shows it as `nil`.

</details>

2. At the prompt, compute 2 to the power of 10 (`2 ^ 10`) and 7 divided by 2. Why do you need the
   `=`?

<details><summary>Solution</summary>

```console
> = 2 ^ 10, 7 / 2
1024	3.5
```

The prompt runs statements, and an expression alone isn't one. `=` turns the line into
`return 2 ^ 10, 7 / 2`, and the prompt prints the returned values. Note that `/` always gives a
fractional result.

</details>

3. Add a line `  tags          count bookmarks per tag` to the commands in `stash.lua`, after `rm`.
   Then use the `---[[` trick to switch the whole commands list off and back on.

<details><summary>Solution</summary>

```lua
print("commands:")
---[[
print("  add URL       save a bookmark")
print("  list          list bookmarks")
print("  search TERM   search bookmarks")
print("  show ID       show one bookmark")
print("  rm ID         delete a bookmark")
print("  tags          count bookmarks per tag")
print("  help          show this help")
--]]
```

Change `---[[` to `--[[` and the seven lines vanish from the output; change it back to restore
them. (Keep the project file as the checkpoint shows; `tags` arrives for real in Chapter 5.)

</details>

4. Run `luajit -e 'print(arg[0])' x y`. What does it print, and why? (Hint: which script runs?)

<details><summary>Solution</summary>

```console
$ luajit -e 'print(arg[0])' x y
x
luajit: cannot open x: No such file or directory
```

`luajit` treats `x` as the script and `y` as its argument. It runs the `-e` chunk first, so
`arg[0]` is `x`, then tries to run the missing file `x`. Options go before the script name;
everything after it belongs to the script.

</details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-1--getting-started)
