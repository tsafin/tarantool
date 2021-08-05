/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright 2021, Tarantool AUTHORS, please see AUTHORS file.
 */

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
