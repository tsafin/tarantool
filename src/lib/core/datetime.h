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

#ifndef SECS_PER_DAY
#define SECS_PER_DAY          86400
#define DT_EPOCH_1970_OFFSET  719163
#endif

/**
 * Full datetime structure representing moments
 * since Unix Epoch (1970-01-01).
 * Time is kept normalized to UTC, time-zone offset
 * is informative only.
 */
struct datetime {
	/** seconds since epoch */
	int64_t secs;
	/** nanoseconds if any */
	int32_t nsec;
	/** offset in minutes from UTC */
	int32_t offset;
};

/**
 * Date/time interval structure
 */
struct datetime_interval {
	/** relative seconds delta */
	int64_t secs;
	/** nanoseconds delta */
	int32_t nsec;
};

/**
 * Compare arguments of a datetime type
 * @param lhs left datetime argument
 * @param rhs right datetime argument
 * @retval < 0 if lhs less than rhs
 * @retval = 0 if lhs and rhs equal
 * @retval > 0 if lhs greater than rhs
 */
int
datetime_compare(const struct datetime *lhs, const struct datetime *rhs);

/**
 * Convert datetime to string using default format
 * @param date source datetime value
 * @param buf output character buffer
 * @param len size ofoutput buffer
 */
int
datetime_to_string(const struct datetime *date, char *buf, uint32_t len);

/**
 * Convert datetime to string using default asctime format
 * "Sun Sep 16 01:03:52 1973\n\0"
 * Wrapper around reenterable asctime_r() version of POSIX function
 * @param date source datetime value
 * @sa datetime_ctime
 */
char *
datetime_asctime(const struct datetime *date, char *buf);

char *
datetime_ctime(const struct datetime *date, char *buf);

size_t
datetime_strftime(const struct datetime *date, const char *fmt, char *buf,
		  uint32_t len);

void
datetime_now(struct datetime * now);

#if defined(__cplusplus)
} /* extern "C" */
#endif /* defined(__cplusplus) */
