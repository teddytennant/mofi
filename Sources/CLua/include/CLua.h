// Umbrella header for the vendored Lua 5.4 plus inline shims for the
// function-like macros Swift can't import.
#ifndef CLUA_H
#define CLUA_H

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

static inline void mofi_pop(lua_State *L, int n) { lua_pop(L, n); }
static inline void mofi_newtable(lua_State *L) { lua_newtable(L); }
static inline void mofi_pushcfunction(lua_State *L, lua_CFunction f) { lua_pushcfunction(L, f); }
static inline const char *mofi_tostring(lua_State *L, int i) { return lua_tostring(L, i); }
static inline lua_Integer mofi_tointeger(lua_State *L, int i) { return lua_tointeger(L, i); }
static inline lua_Number mofi_tonumber(lua_State *L, int i) { return lua_tonumber(L, i); }
static inline int mofi_pcall(lua_State *L, int nargs, int nres, int msgh) { return lua_pcall(L, nargs, nres, msgh); }
static inline void mofi_insert(lua_State *L, int i) { lua_insert(L, i); }
static inline void mofi_remove(lua_State *L, int i) { lua_remove(L, i); }

#endif
