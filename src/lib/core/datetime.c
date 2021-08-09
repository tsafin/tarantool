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

#include <assert.h>
#include <limits.h>
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

	int seconds_of_day = date->secs % SECS_PER_DAY;
	tm.tm_hour = (seconds_of_day / 3600) % 24;
	tm.tm_min = (seconds_of_day / 60) % 60;
	tm.tm_sec = seconds_of_day % 60;

	return &tm;
}

void
datetime_now(struct datetime * now)
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
datetime_asctime(const struct datetime *date)
{
	struct tm *p_tm = datetime_to_tm(date);
	return asctime(p_tm);
}

char *
datetime_ctime(const struct datetime *date)
{
	time_t time = date->secs;
	return ctime(&time);
}

size_t
datetime_strftime(const struct datetime *date, const char *fmt, char *buf,
		  uint32_t len)
{
	struct tm *p_tm = datetime_to_tm(date);
	return strftime(buf, len, fmt, p_tm);
}

#define SECS_EPOCH_1970_OFFSET ((int64_t)DT_EPOCH_1970_OFFSET * SECS_PER_DAY)

int
datetime_to_string(const struct datetime *date, char *buf, uint32_t len)
{
	char * src = buf;
	int offset = date->offset;
	/* for negative offsets around Epoch date we could get
	 * negative secs value, which should be attributed to
	 * 1969-12-31, not 1970-01-01, thus we first shift
	 * epoch to Rata Die then divide by seconds per day,
	 * not in reverse
	 */
	int64_t secs = date->secs + offset * 60 + SECS_EPOCH_1970_OFFSET;
	assert((secs / SECS_PER_DAY) <= INT_MAX);
	dt_t dt = dt_from_rdn(secs / SECS_PER_DAY);

	int year, month, day, sec, ns, sign;
	dt_to_ymd(dt, &year, &month, &day);

	int hour = (secs / 3600) % 24,
	    minute = (secs / 60) % 60;
	sec = secs % 60;
	ns = date->nsec;

	uint32_t sz = snprintf(buf, len, "%04d-%02d-%02dT%02d:%02d",
			       year, month, day, hour, minute);
	buf += sz; len -= sz;
	if (sec || ns) {
		sz = snprintf(buf, len, ":%02d", sec);
		buf += sz; len -= sz;
		if (ns) {
			if ((ns % 1000000) == 0)
				sz = snprintf(buf, len, ".%03d", ns / 1000000);
			else if ((ns % 1000) == 0)
				sz = snprintf(buf, len, ".%06d", ns / 1000);
			else
				sz = snprintf(buf, len, ".%09d", ns);
			buf += sz; len -= sz;
		}
	}
	if (offset == 0) {
		strncpy(buf, "Z", len);
		buf++;
		len--;
	}
	else {
		if (offset < 0)
			sign = '-', offset = -offset;
		else
			sign = '+';

		sz = snprintf(buf, len, "%c%02d:%02d", sign, offset / 60, offset % 60);
		buf += sz; len -= sz;
	}
	return (buf - src);
}

int
datetime_compare(const struct datetime *lhs, const struct datetime *rhs)
{
	int result = COMPARE_RESULT(lhs->secs, rhs->secs);
	if (result != 0)
		return result;

	return COMPARE_RESULT(lhs->nsec, rhs->nsec);
}

