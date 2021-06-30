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

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include "c-dt/dt.h"

#if defined(__cplusplus)
extern "C"
{
#endif /* defined(__cplusplus) */

/**
 * Full datetime structure representing moments
 * since Unix Epoch (1970-01-01).
 * Time is kept normalized to UTC, time-zone offset
 * is informative only.
 */
struct datetime_t {
	int64_t secs;	/**< seconds since epoch */
	int32_t nsec;	/**< nanoseconds if any */
	int32_t offset; /**< offset in minutes from UTC */
};

/**
 * Date/time interval structure
 */
struct datetime_interval_t {
	int64_t secs; /**< relative seconds delta */
	int32_t nsec; /**< nanoseconds delta */
};

int
datetime_compare(const struct datetime_t * lhs,
		 const struct datetime_t * rhs);


struct datetime_t *
datetime_unpack(const char **data, uint32_t len, struct datetime_t *date);

/**
 * Pack datetime_t data to the MessagePack buffer.
 */
char *
datetime_pack(char *data, const struct datetime_t *date);

/**
 * Calculate size of MessagePack buffer for datetime_t data.
 */
uint32_t
mp_sizeof_datetime(const struct datetime_t *date);

/**
 * Decode data from MessagePack buffer to datetime_t structure.
 */
struct datetime_t *
mp_decode_datetime(const char **data, struct datetime_t *date);

/**
 * Encode datetime_t structure to the MessagePack buffer.
 */
char *
mp_encode_datetime(char *data, const struct datetime_t *date);

/**
 * Convert datetime to string using default format
 * @param date source datetime value
 * @param buf output character buffer
 * @param len size ofoutput buffer
 */
int
datetime_to_string(const struct datetime_t * date, char *buf, uint32_t len);

int
mp_snprint_datetime(char *buf, int size, const char **data, uint32_t len);

int
mp_fprint_datetime(FILE *file, const char **data, uint32_t len);

#if defined(__cplusplus)
} /* extern "C" */
#endif /* defined(__cplusplus) */
