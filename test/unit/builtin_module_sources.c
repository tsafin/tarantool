#include <stdarg.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "trivia/util.h"
#include "lua/tarantool_debug.h"
#include "lua/utils.h"
#include "lua/error.h"

#define UNIT_TAP_COMPATIBLE 1
#include "unit.h"

/* contents of src/lua/ files */
extern char strict_lua[],
	fun_lua[],
	debug_lua[],
	buffer_lua[],
	errno_lua[],
	fiber_lua[],
	env_lua[],
	datetime_lua[];

static const char * const lua_modules[] = {
	"strict", strict_lua,
	"fun", fun_lua,
	"debug", debug_lua,
	"errno", errno_lua,
	"fiber", fiber_lua,
	"env", env_lua,
	"datetime", datetime_lua,
};

static void
builtin_sources_test(void)
{
	plan(70);
	header();

	struct lua_State *L = luaL_newstate();
	luaL_openlibs(L);
	tarantool_L = L;
	tarantool_lua_debug_init(L);
	tarantool_lua_error_init(L);
	static const char * const fmts[] = {
		"return require 'tarantool'.debug.getsources('%s')",
		"return require 'tarantool'.debug.getsources('@builtin/%s.lua')",
	};

	for (size_t i = 0; i < lengthof(lua_modules); i += 2) {
		char buf[128];
		const char *modname = lua_modules[i];
		for (size_t j = 0; j < lengthof(fmts); j++) {
			const char *fmt = fmts[j];
			snprintf(buf, sizeof(buf), fmt, modname);
			luaL_loadstring(L, buf);
			int rc = lua_pcall(L, 0, 1, 0);
			is(rc, 0, "lua_pcall is ok");
			int top = lua_gettop(L);
			is(top, 2, "top == 2");
			size_t len = 0;
			const char *code = luaL_checklstring(L, -1, &len);
			isnt(code, NULL, "code != NULL");
			isnt(len, 0, "len != 0");
			const char *expected_code = lua_modules[i + 1];
			is(0, strcmp(code, expected_code),
			   "code == expected_code");
			lua_pop(L, 1);
		}
	}

	footer();
	check_plan();
}

int
main(void)
{
	plan(1);
	builtin_sources_test();
	return check_plan();
}
