#pragma once
/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright 2021, Tarantool AUTHORS, please see AUTHORS file.
 */

#include <limits.h>
#include <stdint.h>
#include <stdbool.h>
#include "c-dt/dt.h"

#if defined(__cplusplus)
extern "C"
{
#endif /* defined(__cplusplus) */

/**
 * We count dates since so called "Rata Die" date
 * January 1, 0001, Monday (as Day 1).
 * But datetime structure keeps seconds since
 * Unix "Epoch" date:
 * Unix, January 1, 1970, Thursday
 *
 * The difference between Epoch (1970-01-01)
 * and Rata Die (0001-01-01) is 719163 days.
 */

#ifndef SECS_PER_DAY
#define SECS_PER_DAY          86400
#define DT_EPOCH_1970_OFFSET  719163
#endif

/**
 * c-dt library uses int as type for dt value, which
 * represents the number of days since Rata Die date.
 * This implies limits to the number of seconds we
 * could safely store in our structures and then safely
 * pass to c-dt functions.
 *
 * So supported ranges will be
 * - for seconds [-185604722870400 .. 185480451417600]
 * - for dates   [-5879610-06-22T00:00Z .. 5879611-07-11T00:00Z]
 */
#define MAX_DT_DAY_VALUE (int64_t)INT_MAX
#define MIN_DT_DAY_VALUE (int64_t)INT_MIN
#define SECS_EPOCH_1970_OFFSET 	\
	((int64_t)DT_EPOCH_1970_OFFSET * SECS_PER_DAY)
#define MAX_EPOCH_SECS_VALUE    \
	(MAX_DT_DAY_VALUE * SECS_PER_DAY - SECS_EPOCH_1970_OFFSET)
#define MIN_EPOCH_SECS_VALUE    \
	(MIN_DT_DAY_VALUE * SECS_PER_DAY - SECS_EPOCH_1970_OFFSET)

/**
 * datetime structure keeps number of seconds since
 * Unix Epoch.
 * Time is normalized by UTC, so time-zone offset
 * is informative only.
 */
struct datetime {
	/** Seconds since Epoch. */
	double secs;
	/** Nanoseconds, if any. */
	uint32_t nsec;
	/** Offset in minutes from UTC. */
	int32_t offset;
};

/**
 * Date/time interval structure
 */
struct datetime_interval {
	/** Relative seconds delta. */
	double secs;
	/** Nanoseconds delta, if any. */
	uint32_t nsec;
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
datetime_to_string(const struct datetime *date, char *buf, int len);

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
