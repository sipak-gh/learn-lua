/* Lua calling C: plain C functions, and a userdata type with methods
   and a __gc finalizer. */
#include <stdio.h>
#include <stdlib.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/* divmod(a, b) -> quotient, remainder.  Errors when b is 0. */
static int l_divmod(lua_State *L)
{
  lua_Integer a = luaL_checkinteger(L, 1);  /* raises a Lua error if not */
  lua_Integer b = luaL_checkinteger(L, 2);
  if (b == 0)
    return luaL_error(L, "division by zero");
  lua_pushinteger(L, a / b);
  lua_pushinteger(L, a % b);
  return 2;                                 /* number of results */
}

/* A counter object, allocated by Lua as a userdata block. */
typedef struct { int count; } Counter;

static int counter_new(lua_State *L)
{
  Counter *c = (Counter *)lua_newuserdata(L, sizeof(Counter));
  c->count = (int)luaL_optinteger(L, 1, 0);
  luaL_getmetatable(L, "demo.Counter");
  lua_setmetatable(L, -2);                  /* give it the methods */
  return 1;
}

static int counter_bump(lua_State *L)
{
  Counter *c = (Counter *)luaL_checkudata(L, 1, "demo.Counter");
  c->count++;
  lua_pushinteger(L, c->count);
  return 1;
}

static int counter_gc(lua_State *L)
{
  Counter *c = (Counter *)luaL_checkudata(L, 1, "demo.Counter");
  printf("__gc: counter at %d\n", c->count);
  return 0;
}

static const luaL_Reg counter_methods[] = {
  { "bump", counter_bump },
  { "__gc", counter_gc },
  { NULL, NULL }
};

static const luaL_Reg demo_functions[] = {
  { "divmod", l_divmod },
  { "counter", counter_new },
  { NULL, NULL }
};

static const char *script =
  "print(demo.divmod(17, 5))\n"
  "print(pcall(demo.divmod, 1, 0))\n"
  "print(pcall(demo.divmod, 'x', 1))\n"
  "local c = demo.counter(10)\n"
  "print(type(c), c:bump(), c:bump())\n"
  "print(pcall(c.bump, {}))\n";

int main(void)
{
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);

  luaL_newmetatable(L, "demo.Counter");     /* registry["demo.Counter"] */
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");           /* mt.__index = mt */
  luaL_register(L, NULL, counter_methods);  /* put methods into mt */
  lua_pop(L, 1);

  luaL_register(L, "demo", demo_functions); /* global table `demo` */
  lua_pop(L, 1);

  if (luaL_dostring(L, script) != 0)
    printf("error: %s\n", lua_tostring(L, -1));
  printf("closing\n");
  lua_close(L);                             /* the counter is collected */
  return 0;
}
