#include "diag.h"
#include "execute.h"
#include "lua/utils.h"
#include "sqlInt.h"
#include "../sql/vdbe.h"	// FIXME
#include "../sql/vdbeInt.h"	// FIXME
#include "../execute.h"		// FIXME
#include "../schema.h"		// FIXME
#include "../session.h"		// FIXME
#include "../box.h"		// FIXME
#include <small/ibuf.h>
#include <msgpuck/msgpuck.h>

#include "sqlparser.h"

#include <assert.h>
#include <stdlib.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

static struct Select *
mp_decode_select(const char **data, bool subselect);

static struct SrcList *
mp_decode_select_from(const char **data);

static struct ExprList *
mp_decode_expr_list(const char **data);

void
luaT_push_sql_parsed_ast(struct lua_State *L, struct sql_parsed_ast *ast);

struct span_view {
	const char * ptr;
	uint32_t length;
};

#define ON_(span, expected) \
	if (span.length == (sizeof(expected) - 1) && \
	    strncmp(expected, span.ptr, span.length) == 0)

#define UNLESS_(span, expected) \
	if (span.length != (sizeof(expected) - 1) || \
	    strncmp(expected, span.ptr, span.length) != 0)

#define EXPECT_MAP(data) ({ \
		enum mp_type type = mp_typeof(**data); \
		assert(type == MP_MAP); \
		uint32_t size = mp_decode_map(data); \
		size; })

#define EXPECT_ARRAY(data) ({ \
		enum mp_type type = mp_typeof(**data); \
		assert(type == MP_ARRAY); \
		uint32_t size = mp_decode_array(data); \
		size; })

#define IN_S(data, v) { \
		enum mp_type type = mp_typeof(**data); \
		assert(type == MP_STR || type == MP_NIL); \
		if (type == MP_STR) { \
			(v).length = 0; \
			(v).ptr = mp_decode_str(data, &v.length); \
		} else if (type == MP_NIL) { \
			(v).ptr = NULL; \
			(v).length = 0; \
			mp_decode_nil(data); \
		} \
	}

#define EXPECT_KEY(data, v) \
		IN_S(data, v)

#define IN_V(data, v, f, type) { \
		ON_(key, #f) { \
			/* assert(type == MP_STR); */ \
			(v).f = mp_decode_##type(data); \
			continue; \
		} \
	}

#define IN_VS_(data, string, span) \
		ON_(key, string) { \
			IN_S(data, span); \
			continue; \
		}

#define IN_VS(data, span) \
		IN_VS_(data, #span, span)

#define IN_VA(data, v, f) \
		ON_(key, #f) { \
			struct span_view ps; \
			IN_S(data, ps); \
			if (ps.ptr != NULL) { \
				strncpy((v).f, ps.ptr, ps.length); \
			} \
			(v).f[ps.length] = '\0'; \
			continue; \
		}

static int64_t
mp_decode_Xint(const char **data)
{
	switch (mp_typeof(**data)) {
	case MP_UINT:
		return mp_decode_uint(data);
	case MP_INT:
		return mp_decode_int(data);
	default:
		assert(0);
	}
	return 0;
}

static struct Expr*
mp_expr_new(int op, const struct span_view *token)
{
	int extra_sz = 0;
	if (token && token->ptr)
		extra_sz = token->length + 1;
	struct Expr *e = sqlDbMallocRawNN(sql_get(), sizeof(*e) + extra_sz);
	if (e == NULL) {
		diag_set(OutOfMemory, sizeof(*e), "mp_expr_new", "e");
		return NULL;
	}
	memset(e, 0, sizeof(*e));
	e->op = (u8)op;
	e->iAgg = -1;
#if SQL_MAX_EXPR_DEPTH > 0
	e->nHeight = 1;
#endif
	if (extra_sz) {
		char * p = (char*)e + sizeof(*e);
		e->u.zToken = p;
		assert(token->ptr != NULL);
		memcpy(p, token->ptr, token->length);
		p[token->length] = 0;
	} 
	return e;
}

static struct Expr*
mp_decode_expr(const char **data)
{
	struct Expr tmp = {0}, *expr = NULL;
	struct span_view zToken = {0};

	int items = EXPECT_MAP(data);
	for (int j = 0; j < items; j++) {
		struct span_view key;
		EXPECT_KEY(data, key);

		IN_V(data, tmp, op, uint);
		IN_V(data, tmp, type, uint);
		IN_V(data, tmp, flags, uint);
		// if (tmp.flags & EP_IntValue) {
			IN_V(data, tmp, u.iValue, Xint);
		// } else {
			IN_VS_(data, "u.zToken", zToken);
		//}
#if SQL_MAX_EXPR_DEPTH > 0
		IN_V(data, tmp, nHeight, Xint);
#endif
		IN_V(data, tmp, iTable, Xint);
		IN_V(data, tmp, iColumn, Xint);

		IN_V(data, tmp, iAgg, Xint);
		IN_V(data, tmp, iRightJoinTable, Xint);
		IN_V(data, tmp, op2, uint);
		ON_(key, "left") {
			tmp.pLeft = mp_decode_expr(data);
		}
		else ON_(key, "right") {
			tmp.pRight = mp_decode_expr(data);
		}
		else ON_(key, "subselect") {
			tmp.x.pSelect = mp_decode_select(data, true);
		}
		else ON_(key, "inexpr") {
			tmp.x.pList = mp_decode_expr_list(data);
		}


	}
	// FIXME - macroize
	expr = mp_expr_new(tmp.op, &zToken);
	expr-> type = tmp.type;
	expr->flags = tmp.flags;
	if (tmp.flags & EP_IntValue)
		expr->u.iValue = tmp.u.iValue;
#if SQL_MAX_EXPR_DEPTH > 0
	expr->nHeight = tmp.nHeight;
#endif
	expr->iTable = tmp.iTable;
	expr->iColumn = tmp.iColumn;
	expr->iAgg = tmp.iAgg;
	expr->iRightJoinTable = tmp.iRightJoinTable;
	expr->op2 = tmp.op2;

	expr->pLeft = tmp.pLeft;
	expr->pRight = tmp.pRight;
	expr->x = tmp.x;

	return expr;

}

static struct ExprList *
mp_decode_expr_list(const char **data)
{
	struct ExprList * p = NULL;
	int n_elems = EXPECT_ARRAY(data);
	for (int i = 0; i < n_elems; i++) {
		struct Expr * expr = mp_decode_expr(data);
		p = sql_expr_list_append(sql_get(), p, expr);
	}
	return p;
}

static void
mp_decode_select_expr(const char **data, struct Select *p, struct span_view key)
{
	ON_(key, "results") {
		p->pEList = mp_decode_expr_list(data);
	}
	else ON_(key, "where") {
		p->pWhere = mp_decode_expr(data);
	}
	else ON_(key, "groupby") {
		p->pGroupBy = mp_decode_expr_list(data);
	}
	else ON_(key, "having") {
		p->pHaving = mp_decode_expr(data);
	}
	else ON_(key, "orderby") {
		p->pOrderBy = mp_decode_expr_list(data);
	}
	else ON_(key, "limit") {
		p->pLimit = mp_decode_expr(data);
	}
	else ON_(key, "offset") {
		p->pOffset = mp_decode_expr(data);
	}
	else ON_(key, "from") {
		if (p->pSrc != NULL)
			sqlSrcListDelete(sql_get(), p->pSrc);
		p->pSrc = mp_decode_select_from(data);
	}

}

static inline char *
sql_name_from_span(struct sql *db, const struct span_view *token)
{
	assert(token != NULL && token->ptr != NULL);

	return sql_normalized_name_db_new(db, token->ptr, token->length);
}

static struct IdList *
mp_decode_idlist(const char **data)
{
	struct IdList * p = NULL;
	int n_elems = EXPECT_ARRAY(data);
	for (int i = 0; i < n_elems; i++) {
		int items = EXPECT_MAP(data);
		struct span_view zName;
		struct IdList_item item = {0};
		for (int j = 0; j < items; j++) {
			struct span_view key;
			EXPECT_KEY(data, key);

			IN_VS(data, zName);
			IN_V(data, item, idx, Xint);
		}
		struct Token token = {
			.z = zName.ptr,
			.n = zName.length
		};
		assert(item.idx == 0);
		p = sql_id_list_append(sql_get(), p, &token);
	}
	return p;
}

static struct SrcList *
mp_decode_select_from(const char **data)
{
	struct sql *db = sql_get();
	struct SrcList *pSrcList = sql_src_list_new(db);

	int n_elems = EXPECT_ARRAY(data);
	// FIXME - introduce simpler way to allocate more than 1 SrcList
	if (n_elems > 1)
		pSrcList = sql_src_list_enlarge(db, pSrcList, 1, pSrcList->nSrc);
	
	for (int i = 0; i < n_elems; i++) {
		struct SrcList_item *p = &pSrcList->a[i];
		struct span_view zName = {0}, zAlias = {0}, zIndexedBy = {0};

		int items = EXPECT_MAP(data);
		
		for (int j = 0; j < items; j++) {
			struct span_view key;
			EXPECT_KEY(data, key);
			IN_VS(data, zName);
			IN_VS(data, zAlias);
			IN_V(data, *p, fgBits, uint);
			IN_VS_(data, "u1.zIndexedBy", zIndexedBy);
			ON_(key, "select") {
				p->pSelect = mp_decode_select(data, true);
			}
			else ON_(key, "list") {
				p->u1.pFuncArg = mp_decode_expr_list(data);
			}
			// FIXME - serializer
			else ON_(key, "on") {
				p->pOn = mp_decode_expr(data);
			}
			else ON_(key, "using") {
				p->pUsing = mp_decode_idlist(data);
			}
		}
		if (zName.length > 0)
			p->zName = sql_name_from_span(db, &zName);
		if (zAlias.length > 0)
			p->zAlias = sql_name_from_span(db, &zAlias);
		if (zIndexedBy.length > 0)
			p->u1.zIndexedBy = sql_name_from_span(db, &zIndexedBy);
	}
	return pSrcList;
}

static struct Select *
mp_decode_select(const char **data, bool subselect)
{
	// top-most select is wrapped as map
	// {"select": ... }
	if (!subselect) {
		uint32_t size = EXPECT_MAP(data);
		assert(size == 1);

		struct span_view key;
		IN_S(data, key);

		UNLESS_(key, "select") {
			assert(0);
			return NULL;
		}
	}

	Parse sParse;
	sql_parser_create(&sParse, sql_get(), current_session()->sql_flags);

	struct Select *pSelect = NULL;
	struct Select *p = NULL, *pPrior = NULL;
	int n_selects = EXPECT_ARRAY(data);
	for (int j = 0; j < n_selects; j++) {
		p = sqlSelectNew(
			&sParse, NULL, NULL, NULL, NULL, NULL, NULL,
			0, NULL, NULL
		);
		if (pSelect == NULL)
			pSelect = p;

		int n = EXPECT_MAP(data);
		for (int k = 0; k < n; k++) {
			struct span_view key;
			EXPECT_KEY(data, key);

			IN_V(data, *p, op, uint);
			IN_V(data, *p, nSelectRow, Xint);
			IN_V(data, *p, selFlags, uint);
			IN_V(data, *p, iLimit, Xint);
			IN_V(data, *p, iOffset, Xint);
			IN_VA(data, *p, zSelName);
			IN_V(data, *p, addrOpenEphm[0], Xint);
			IN_V(data, *p, addrOpenEphm[1], Xint);
			// ON_(key, "expr", len) {
			mp_decode_select_expr(data, p, key);
			// }
		}
		if (pPrior != NULL)
			pPrior->pPrior = p;
		pPrior = p;
	}
	return pSelect;
}

static int
sqlparser_msgpack_decode_string(struct lua_State *L, bool check)
{
	size_t data_len;
	const char *data = lua_tolstring(L, 1, &data_len);
	const char *p = data;
	if (check) {
		if (mp_check(&p, data + data_len) != 0)
			return luaL_error(L, "sqldeserialize: invalid MsgPack");
	}
	p = data;
	struct Select * select = mp_decode_select(&p, false);
	assert(select != NULL);

	struct sql_parsed_ast *ast = sql_ast_alloc();
	ast->ast_type = AST_TYPE_SELECT;
	ast->keep_ast = true;
	ast->select = select;

	if (AST_VALID(ast)) {
		luaT_push_sql_parsed_ast(L, ast);
		return 1;
	} else  {
		return luaT_push_nil_and_error(L);
	}
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
