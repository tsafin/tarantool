#pragma once
/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright 2021, Tarantool AUTHORS, please see AUTHORS file.
 */

#include <limits.h>
#include <assert.h>

#include "msgpuck.h"

/**
 * Convenient wrapper for determining size of integer value
 * in MessagePack, regardless of it's sign.
 *
 * @param n signed 64-bit value
 * @sa mp_sizeof_int
 * @sa mp_sizeof_uint
 */
static inline uint32_t
mp_sizeof_xint(int64_t n)
{
	return n < 0 ? mp_sizeof_int(n) : mp_sizeof_uint(n);
}

/**
 * Convenient wrapper for encoding integer value
 * to messagepack, regardless of it's sign.
 *
 * @param data output MessagePack buffer
 * @param v 64-bit value to be encoded.
 * @sa mp_encode_int
 * @sa mp_encode_uint
 */
static inline char *
mp_encode_xint(char *data, int64_t v)
{
	assert(v < 0 || (uint64_t)v <= LONG_MAX);
	return v < 0 ? mp_encode_int(data, v) : mp_encode_uint(data, v);
}

/**
 * Convenient wrapper for decoding to integer value
 * from MessagePack, regardless of it's sign.
 *
 * @param data messagepack buffer
 * @retval return signed, 64-bit value.
 * @sa mp_decode_int
 * @sa mp_decode_uint
 */
static inline int64_t
mp_decode_xint(const char **data)
{
	switch (mp_typeof(**data)) {
	case MP_UINT:
		return (int64_t)mp_decode_uint(data);
	case MP_INT:
		return mp_decode_int(data);
	default:
		mp_unreachable();
	}
	return 0;
}
