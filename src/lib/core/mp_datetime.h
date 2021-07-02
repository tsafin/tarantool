#pragma once
/*
 * Copyright 2021, Tarantool AUTHORS, please see AUTHORS file.
 *
 * Redistribution and use in source and binary forms, with or
 * without modification, are permitted provided that the following
 * conditions are met:
 *
 * 1. Redistributions of source code must retain the above
 *    copyright notice, this list of conditions and the
 *    following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above
 *    copyright notice, this list of conditions and the following
 *    disclaimer in the documentation and/or other materials
 *    provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY <COPYRIGHT HOLDER> ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 * <COPYRIGHT HOLDER> OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 * THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <stdio.h>
#include "datetime.h"

#if defined(__cplusplus)
extern "C"
{
#endif /* defined(__cplusplus) */

/**
 * Unpack datetime data from MessagePack buffer.
 * @sa datetime_pack
 */
struct datetime *
datetime_unpack(const char **data, uint32_t len, struct datetime *date);

/**
 * Pack datetime data to MessagePack buffer.
 * @sa datetime_unpack
 */
char *
datetime_pack(char *data, const struct datetime *date);

/**
 * Calculate size of MessagePack buffer for datetime data.
 */
uint32_t
mp_sizeof_datetime(const struct datetime *date);

/**
 * Decode data from MessagePack buffer to datetime structure.
 */
struct datetime *
mp_decode_datetime(const char **data, struct datetime *date);

/**
 * Encode datetime structure to the MessagePack buffer.
 */
char *
mp_encode_datetime(char *data, const struct datetime *date);

/**
 * Print datetime's string representation into a given buffer.
 * @sa mp_snprint_decimal
 */
int
mp_snprint_datetime(char *buf, int size, const char **data, uint32_t len);

/**
 * Print datetime's string representation into a stream.
 * @sa mp_fprint_decimal
 */
int
mp_fprint_datetime(FILE *file, const char **data, uint32_t len);

#if defined(__cplusplus)
} /* extern "C" */
#endif /* defined(__cplusplus) */
