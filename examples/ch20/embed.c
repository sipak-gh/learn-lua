/* The smallest useful host: create a Lua state, open the standard
   libraries, run some Lua code, report errors. */
#include <stdio.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/* Compiles and runs `code`; returns 0 on success. */
static int run(lua_State *L, const char *name, const char *code)
{
  int status = luaL_loadbuffer(L, code, strlen(code), name);  /* chunk */
  if (status == 0)
    status = lua_pcall(L, 0, 0, 0);       /* call it: 0 args, 0 results */
  if (status != 0) {
    fflush(stdout);                       /* keep print() output in order */
    fprintf(stderr, "error: %s\n", lua_tostring(L, -1));  /* the message */
    lua_pop(L, 1);
  }
  return status;
}

int main(void)
{
  lua_State *L = luaL_newstate();         /* a new, empty Lua world */
  if (L == NULL)
    return 1;
  luaL_openlibs(L);                       /* string, table, io, ffi, jit, ... */

  run(L, "=hello", "print('hello from ' .. jit.version)");
  run(L, "=math", "x = 6 * 7  print('x =', x)");
  run(L, "=again", "print('x is still', x)");   /* same state, same globals */
  run(L, "=syntax", "print('oops'");
  run(L, "=runtime", "local t = nil; print(t.field)");

  lua_close(L);                           /* frees everything, runs __gc */
  return 0;
}
