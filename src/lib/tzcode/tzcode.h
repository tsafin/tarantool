#pragma once
/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright 2021, Tarantool AUTHORS, please see AUTHORS file.
 */

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif /* defined(__cplusplus) */

/**
 * Local version resembling ISO C' tm structure.
 * Includes original epoch value, and nanoseconds.
 */
struct tnt_tm {
	/** Seconds. [0-60] (1 leap second) */
	int tm_sec;
	/** Minutes. [0-59] */
	int tm_min;
	/** Hours. [0-23] */
	int tm_hour;
	/** Day. [1-31] */
	int tm_mday;
	/** Month. [0-11] */
	int tm_mon;
	/** Year - 1900. */
	int tm_year;
	/** Day of week. [0-6] */
	int tm_wday;
	/** Days in year.[0-365] */
	int tm_yday;
	/** DST. [-1/0/1] */
	int tm_isdst;

	/** Seconds east of UTC. */
	long int tm_gmtoff;
	/** Seconds since Epoch */
	int64_t tm_epoch;
	/** nanoseconds */
	int tm_nsec;
	/** Timezone index. */
	int16_t tm_tzindex;
};

/**
 * tnt_strftime is Tarantool version of a POSIX' strftime()
 * which has been extended with %f (fractions of second)
 * flag support. In all other aspect it's behaving exactly
 * like standard strftime.
 * @sa strftime()
 */
size_t
tnt_strftime(char *s, size_t maxsize, const char *format,
	     const struct tnt_tm *tm);

/**
 * tnt_strptime is a Tarantool version of POSIX strptime()
 * which has been extended with %f (fractions of second)
 * flag support.
 * @sa strptime()
 */
char *
tnt_strptime(const char *__restrict buf, const char *__restrict fmt,
	     struct tnt_tm *__restrict tm);

/** FIXME */

#include "tzfile.h"

struct ttinfo { /* time type information */
	int_fast32_t tt_utoff; /* UT offset in seconds */
	bool tt_isdst; /* used to set tm_isdst */
	int tt_desigidx; /* abbreviation list index */
	bool tt_ttisstd; /* transition is std time */
	bool tt_ttisut; /* transition is UT */
};

struct lsinfo { /* leap second information */
	time_t ls_trans; /* transition time */
	int_fast32_t ls_corr; /* correction to apply */
};

#define SMALLEST(a, b) (((a) < (b)) ? (a) : (b))
#define BIGGEST(a, b) (((a) > (b)) ? (a) : (b))

/* This abbreviation means local time is unspecified.  */
static const char gmt[] = "GMT";
static char const UNSPEC[] = "-00";

/* How many extra bytes are needed at the end of struct state's chars array.
   This needs to be at least 1 for null termination in case the input
   data isn't properly terminated, and it also needs to be big enough
   for ttunspecified to work without crashing.  */
enum { CHARS_EXTRA = BIGGEST(sizeof UNSPEC, 2) - 1 };

#ifdef TZNAME_MAX
#define MY_TZNAME_MAX TZNAME_MAX
#endif /* defined TZNAME_MAX */
#ifndef TZNAME_MAX
#define MY_TZNAME_MAX 255
#endif /* !defined TZNAME_MAX */

struct state {
	int leapcnt;
	int timecnt;
	int typecnt;
	int charcnt;
	bool goback;
	bool goahead;
	time_t ats[TZ_MAX_TIMES];
	unsigned char types[TZ_MAX_TIMES];
	struct ttinfo ttis[TZ_MAX_TYPES];
	char chars[BIGGEST(BIGGEST(TZ_MAX_CHARS + CHARS_EXTRA, sizeof gmt),
			   (2 * (MY_TZNAME_MAX + 1)))];
	struct lsinfo lsis[TZ_MAX_LEAPS];

	/* The time type to use for early times or if no transitions.
	   It is always zero for recent tzdb releases.
	   It might be nonzero for data from tzdb 2018e or earlier.  */
	int defaulttype;
};
typedef struct state *timezone_t;

timezone_t tzalloc(const char *);
void tzfree(timezone_t);

#if defined(__cplusplus)
} /* extern "C" */
#endif /* defined(__cplusplus) */
