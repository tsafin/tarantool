#pragma once
/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright 2022, Tarantool AUTHORS, please see AUTHORS file.
 */

#ifdef __cplusplus
extern "C" {
#endif

struct lua_State;

void
tarantool_lua_debug_init(struct lua_State *L);

#ifdef __cplusplus
}
#endif
