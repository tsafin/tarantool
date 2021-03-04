#include "diag.h"
#include "execute.h"
#include "lua/utils.h"
#include "sqlInt.h"
#include "sqlparser.h"
#include "box/box.h"
#include <small/ibuf.h>

#include <stdlib.h>
#include <strings.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

uint32_t CTID_STRUCT_SQL_PARSED_AST = 0;
static uint32_t CTID_STRUCT_SQL_STMT = 0;


struct sql_parsed_ast*
sql_ast_alloc(void)
{
	struct sql_parsed_ast *p = calloc(1, sizeof(*p));
	if (p == NULL) {
		diag_set(OutOfMemory, sizeof(*p), "malloc",
			 "struct sql_parsed_ast");
		return NULL;
	}
	return p;
}

void
sql_ast_free(struct sql_parsed_ast *p)
{
	if (p == NULL)
		return;
	free(p);
}

inline struct sql_parsed_ast *
luaT_check_sql_parsed_ast(struct lua_State *L, int idx)
{
	if (lua_type(L, idx) != LUA_TCDATA)
		return NULL;

	uint32_t cdata_type;
	struct sql_parsed_ast **sql_parsed_ast_ptr = luaL_checkcdata(L, idx, &cdata_type);
	if (sql_parsed_ast_ptr == NULL || cdata_type != CTID_STRUCT_SQL_PARSED_AST)
		return NULL;
	return *sql_parsed_ast_ptr;
}


static int
lbox_sql_parsed_ast_gc(struct lua_State *L)
{
	struct sql_parsed_ast *ast = luaT_check_sql_parsed_ast(L, 1);
	struct sql *db = sql_get();
	sql_parsed_ast_destroy(db, ast);

	return 0;
}

void
luaT_push_sql_parsed_ast(struct lua_State *L, struct sql_parsed_ast *ast)
{
	*(struct sql_parsed_ast **)
		luaL_pushcdata(L, CTID_STRUCT_SQL_PARSED_AST) = ast;
	lua_pushcfunction(L, lbox_sql_parsed_ast_gc);
	luaL_setcdatagc(L, -2);
}

struct sql_stmt *
luaT_check_sql_stmt(struct lua_State *L, int idx)
{
	if (lua_type(L, idx) != LUA_TCDATA)
		return NULL;

	uint32_t cdata_type;
	struct sql_stmt **sql_stmt_ptr = luaL_checkcdata(L, idx, &cdata_type);
	if (sql_stmt_ptr == NULL || cdata_type != CTID_STRUCT_SQL_STMT)
		return NULL;
	return *sql_stmt_ptr;
}


static int
lbox_sql_stmt_gc(struct lua_State *L)
{
	(void)L;
	return 0;
}

void
luaT_push_sql_stmt(struct lua_State *L, struct sql_stmt *stmt)
{
	*(struct sql_stmt **)
		luaL_pushcdata(L, CTID_STRUCT_SQL_STMT) = stmt;
	lua_pushcfunction(L, lbox_sql_stmt_gc);
	luaL_setcdatagc(L, -2);
}
/**
 * Parse SQL to AST, return it as cdata
 */
static int
lbox_sqlparser_parse(struct lua_State *L)
{
	if (!box_is_configured())
		luaL_error(L, "Please call box.cfg{} first");
	size_t length;
	int top = lua_gettop(L);

	if (top != 1 || !lua_isstring(L, 1))
		return luaL_error(L, "Usage: sqlparser.parse(sqlstring)");

	const char *sql = lua_tolstring(L, 1, &length);

	struct sql_parsed_ast *ast = sql_ast_alloc();
	struct sql_stmt *stmt = NULL;

	if (sql_stmt_parse(sql, &stmt, ast) != 0)
		goto return_error;

	if (AST_VALID(ast))
		luaT_push_sql_parsed_ast(L, ast);
	else
		luaT_push_sql_stmt(L, stmt);

	return 1;

return_error:
	return luaT_push_nil_and_error(L);
}

static int
lbox_sqlparser_execute(struct lua_State *L)
{
	struct sql_parsed_ast *ast = luaT_check_sql_parsed_ast(L, 1);
	struct sql_stmt *stmt = NULL;
	if (ast == NULL)
		stmt = luaT_check_sql_stmt(L, 1);

	if (sql_parser_ast_execute(L, ast, stmt) == 0)
		return luaT_push_nil_and_error(L);
	else
		return 1;
}

int
lbox_sqlparser_serialize(struct lua_State *L)
{
	struct sql_parsed_ast *ast = luaT_check_sql_parsed_ast(L, 1);

	if (AST_VALID(ast)) {
		assert(ast->ast_type == AST_TYPE_SELECT);

		struct ibuf ibuf;
		ibuf_create(&ibuf, &cord()->slabc, 1024);
		ibuf_reset(&ibuf);

		struct Parse parser;
		struct sql *db = sql_get();
		sql_parser_create(&parser, db, default_flags);
		sqlparser_generate_msgpack_walker(&parser, &ibuf, ast->select);

		lua_pushlstring(L, ibuf.buf, ibuf_used(&ibuf));
		ibuf_reinit(&ibuf);
	} else {
		lua_pushnil(L);
	}
	return 1;
}

int
lbox_sqlparser_deserialize(struct lua_State *L)
{
	int index = lua_gettop(L);
	int type = index >= 1 ? lua_type(L, 1) : LUA_TNONE;
	switch (type) {
	case LUA_TSTRING:
		return sqlparser_msgpack_decode_string(L, true);
	default:
		return luaL_error(L, "sqldeserialize: "
				  "a Lua string or 'char *' expected");
	}
	return 1;
}

extern char sql_ast_cdef[];

void
box_lua_sqlparser_init(struct lua_State *L)
{
	int rc = luaL_cdef(L, sql_ast_cdef);
	if (rc != LUA_OK) {
		const char * error = lua_tostring(L, -1);
		panic("ffi cdef error: %s", error);
	}
	CTID_STRUCT_SQL_PARSED_AST = luaL_ctypeid(L, "struct sql_parsed_ast&");
	assert(CTID_STRUCT_SQL_PARSED_AST != 0);
	luaL_cdef(L, "struct sql_stmt;");
	CTID_STRUCT_SQL_STMT = luaL_ctypeid(L, "struct sql_stmt&");
	assert(CTID_STRUCT_SQL_STMT != 0);

	static const struct luaL_Reg meta[] = {
		{ "parse", lbox_sqlparser_parse },
		{ "serialize", lbox_sqlparser_serialize },
		{ "deserialize", lbox_sqlparser_deserialize },
		{ "execute", lbox_sqlparser_execute },
		{ NULL, NULL },
	};
	luaL_register_module(L, "sqlparser", meta);
	lua_pop(L, 1);

	return;
}
