/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright 2021, Tarantool AUTHORS, please see AUTHORS file.
 */

#include <assert.h>
#include <limits.h>
#include <string.h>
#include <time.h>

#include "trivia/util.h"
#include "datetime.h"

static int
local_dt(int64_t secs)
{
	return dt_from_rdn((int)(secs / SECS_PER_DAY) + DT_EPOCH_1970_OFFSET);
}

static struct tm *
datetime_to_tm(const struct datetime *date)
{
	static struct tm tm;

	memset(&tm, 0, sizeof(tm));
	int64_t secs = date->secs;
	dt_to_struct_tm(local_dt(secs), &tm);

	int seconds_of_day = (int64_t)date->secs % SECS_PER_DAY;
	tm.tm_hour = (seconds_of_day / 3600) % 24;
	tm.tm_min = (seconds_of_day / 60) % 60;
	tm.tm_sec = seconds_of_day % 60;

	return &tm;
}

void
datetime_now(struct datetime *now)
{
	struct timeval tv;
	gettimeofday(&tv, NULL);
	now->secs = tv.tv_sec;
	now->nsec = tv.tv_usec * 1000;

	time_t now_seconds;
	time(&now_seconds);
	struct tm tm;
	localtime_r(&now_seconds, &tm);
	now->offset = tm.tm_gmtoff / 60;
}

char *
datetime_asctime(const struct datetime *date, char *buf)
{
	struct tm *p_tm = datetime_to_tm(date);
	return asctime_r(p_tm, buf);
}

char *
datetime_ctime(const struct datetime *date, char *buf)
{
	time_t time = date->secs;
	return ctime_r(&time, buf);
}

size_t
datetime_strftime(const struct datetime *date, const char *fmt, char *buf,
		  uint32_t len)
{
	struct tm *p_tm = datetime_to_tm(date);
	return strftime(buf, len, fmt, p_tm);
}

#define SECS_EPOCH_1970_OFFSET ((int64_t)DT_EPOCH_1970_OFFSET * SECS_PER_DAY)

/* NB! buf may be NULL, and we should handle it gracefully, returning
 * calculated length of output string
 */
int
datetime_to_string(const struct datetime *date, char *buf, int len)
{
	int offset = date->offset;
	/* for negative offsets around Epoch date we could get
	 * negative secs value, which should be attributed to
	 * 1969-12-31, not 1970-01-01, thus we first shift
	 * epoch to Rata Die then divide by seconds per day,
	 * not in reverse
	 */
	int64_t secs = (int64_t)date->secs + offset * 60 + SECS_EPOCH_1970_OFFSET;
	assert((secs / SECS_PER_DAY) <= INT_MAX);
	dt_t dt = dt_from_rdn(secs / SECS_PER_DAY);

	int year, month, day, sec, ns, sign;
	dt_to_ymd(dt, &year, &month, &day);

	int hour = (secs / 3600) % 24,
	    minute = (secs / 60) % 60;
	sec = secs % 60;
	ns = date->nsec;

	int sz = 0;
	SNPRINT(sz, snprintf, buf, len, "%04d-%02d-%02dT%02d:%02d",
		year, month, day, hour, minute);
	if (sec || ns) {
		SNPRINT(sz, snprintf, buf, len, ":%02d", sec);
		if (ns) {
			if ((ns % 1000000) == 0)
				SNPRINT(sz, snprintf, buf, len, ".%03d",
					ns / 1000000);
			else if ((ns % 1000) == 0)
				SNPRINT(sz, snprintf, buf, len, ".%06d",
					ns / 1000);
			else
				SNPRINT(sz, snprintf, buf, len, ".%09d", ns);
		}
	}
	if (offset == 0) {
		SNPRINT(sz, snprintf, buf, len, "Z");
	}
	else {
		if (offset < 0)
			sign = '-', offset = -offset;
		else
			sign = '+';

		SNPRINT(sz, snprintf, buf, len, "%c%02d:%02d", sign,
			offset / 60, offset % 60);
	}
	return sz;
}

