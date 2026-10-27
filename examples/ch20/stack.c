/* C and Lua talk through a stack of values. This program pushes values,
   reads them back, calls a Lua function and reads fields of a table. */
#include <stdio.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

static void dump(lua_State *L, const char *when)
{
  int i, top = lua_gettop(L);             /* number of values on the stack */
  printf("%-14s", when);
  for (i = 1; i <= top; i++)
    printf(" [%d]=%s", i, luaL_typename(L, i));
  printf("\n");
}

int main(void)
{
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  dump(L, "empty:");

  lua_pushinteger(L, 42);                 /* [1] */
  lua_pushstring(L, "stash");             /* [2] */
  lua_pushboolean(L, 1);                  /* [3] */
  lua_pushnil(L);                         /* [4] */
  dump(L, "after pushes:");
  printf("[1] as number: %g, [-3] as string: %s\n",
         lua_tonumber(L, 1), lua_tostring(L, -3));
  lua_settop(L, 0);                       /* drop everything */

  /* Define a Lua function, then call it from C. */
  if (luaL_dostring(L, "function greet(name, n) "
                       "  return ('hi ' .. name):rep(n, ', '), n * 2 end"))
    return 1;
  lua_getglobal(L, "greet");              /* push the function */
  lua_pushstring(L, "lua");               /* first argument */
  lua_pushinteger(L, 2);                  /* second argument */
  dump(L, "before call:");
  if (lua_pcall(L, 2, 2, 0) != 0) {       /* 2 arguments, 2 results */
    printf("error: %s\n", lua_tostring(L, -1));
    return 1;
  }
  dump(L, "after call:");
  printf("results: %s | %d\n", lua_tostring(L, -2), (int)lua_tointeger(L, -1));
  lua_pop(L, 2);

  /* Read fields of a table returned by Lua code. */
  if (luaL_dostring(L, "return { title = 'LuaJIT', tags = { 'jit', 'ffi' } }"))
    return 1;
  lua_getfield(L, -1, "title");           /* push t.title */
  printf("title: %s\n", lua_tostring(L, -1));
  lua_pop(L, 1);
  lua_getfield(L, -1, "tags");            /* push t.tags */
  printf("#tags: %d, ", (int)lua_objlen(L, -1));
  lua_rawgeti(L, -1, 2);                  /* push t.tags[2] */
  printf("tags[2]: %s\n", lua_tostring(L, -1));
  lua_pop(L, 3);                          /* tags[2], tags, t */
  dump(L, "at the end:");

  lua_close(L);
  return 0;
}
