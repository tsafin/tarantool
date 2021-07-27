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

#include <string.h>

#include "trivia/util.h"
#include "datetime.h"

int
datetime_to_string(const struct datetime_t * date, char *buf, uint32_t len)
{
	char * src = buf;
	int offset = date->offset;
	int64_t secs = date->secs + offset * 60;
	dt_t dt = dt_from_rdn((secs / SECS_PER_DAY) + 719163);

	int year, month, day, sec, ns, sign;
	dt_to_ymd(dt, &year, &month, &day);

	int hour = (secs / 3600) % 24,
	    minute = (secs / 60) % 60;
	;
	sec = secs % 60;
	ns = date->nsec;
	uint32_t sz;
	sz = snprintf(buf, len, "%04d-%02d-%02dT%02d:%02d",
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
