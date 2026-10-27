# Builds stash as a single program: build/stash.
#
#   make          build it
#   make test     run the tests with luajit, then the end-to-end tests
#                 against build/stash
#   make clean    remove build/
#
# LuaJIT is linked in statically, and so are SQLite and zlib; libcurl is
# loaded at run time with ffi.load, like before.

LUAJIT ?= luajit
# The LuaJIT installation that `luajit` on the PATH comes from.
LUAJIT_PREFIX ?= $(abspath $(dir $(shell command -v $(LUAJIT)))..)

CC ?= cc
CFLAGS ?= -O2 -Wall
CPPFLAGS += -I$(LUAJIT_PREFIX)/include/luajit-2.1 -Ibuild -Ibuild/bc
# -E (--export-dynamic): put the program's own functions in its dynamic
# symbol table, so dlsym -- and so ffi.C -- can find them.
# --whole-archive: link all of libsqlite3.a and libz.a, not just the parts
# main.c calls (none!): the Lua code calls them through the FFI.
LDFLAGS += -Wl,-E
LDLIBS += $(LUAJIT_PREFIX)/lib/libluajit-5.1.a \
          -Wl,--whole-archive -l:libsqlite3.a -l:libz.a -Wl,--no-whole-archive \
          -lm -ldl -lpthread

# src/stash/ffi/sqlite.lua -> stash/ffi/sqlite
MODULES := $(patsubst src/%.lua,%,$(sort $(shell find src -name '*.lua')))
HEADERS := $(MODULES:%=build/bc/%.h)

build/stash: host/main.c build/modules.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ host/main.c $(LDLIBS)

# Each module as bytecode in a C header; -g keeps the line numbers for
# error messages, -n sets the module name.
build/bc/%.h: src/%.lua
	@mkdir -p $(dir $@)
	$(LUAJIT) -b -g -t h -n $(subst /,.,$*) $< $@

build/modules.h: $(HEADERS) host/modules.lua
	$(LUAJIT) host/modules.lua $(MODULES) > $@

test: build/stash
	$(LUAJIT) test/run.lua
	STASH_BIN=build/stash $(LUAJIT) test/run.lua e2e

clean:
	rm -rf build

.PHONY: test clean
