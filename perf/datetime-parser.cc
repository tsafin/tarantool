#include "dt.h"
#include <string.h>
#include <assert.h>

#include "datetime-common.h"

/* p5-time-moment/src/moment_parse.c: parse_string_lenient() */
int
parse_datetime(const char *str, size_t len, int64_t *sp, int32_t *np,
	       int32_t *op)
{
	size_t n;
	dt_t dt;
	char c;
	int sod = 0, nanosecond = 0, offset = 0;

	n = dt_parse_iso_date(str, len, &dt);
	if (!n)
		return 1;
	if (n == len)
		goto exit;

	c = str[n++];
	if (!(c == 'T' || c == 't' || c == ' '))
		return 1;

	str += n;
	len -= n;

	n = dt_parse_iso_time(str, len, &sod, &nanosecond);
	if (!n)
		return 1;
	if (n == len)
		goto exit;

	if (str[n] == ' ')
	n++;

	str += n;
	len -= n;

	n = dt_parse_iso_zone_lenient(str, len, &offset);
	if (!n || n != len)
		return 1;

exit:
	*sp = ((int64_t)dt_rdn(dt) - 719163) * 86400 + sod - offset * 60;
	*np = nanosecond;
	*op = offset;

	return 0;
}

/// Parse 70 datetime literals of various lengths
static void
ParseTimeStamps()
{
	size_t index;
	int64_t secs_expected;
	int nanosecs;
	int ofs;
	parse_datetime(sample, sizeof(sample) - 1, &secs_expected,
		       &nanosecs, &ofs);

	for (index = 0; index < DIM(tests); index++)
	{
		int64_t secs;
		int rc = parse_datetime(tests[index].sz, tests[index].len,
					&secs, &nanosecs, &ofs);
		assert(rc == 0);
		assert(secs == secs_expected);
	}
}

static void
CDT_Parse70(benchmark::State &state)
{
	for (auto _ : state)
		ParseTimeStamps();
}
BENCHMARK(CDT_Parse70);

/// Parse single datetime literal of longest length
static void
Parse1()
{
	const char civil_string[] = "2015-02-18T10:50:31.521345123+10:00";
	int64_t secs;
	int nanosecs;
	int ofs;
	int rc = parse_datetime(civil_string, sizeof(civil_string) - 1,
				&secs, &nanosecs, &ofs);
	assert(rc == 0);
	assert(nanosecs == 521345123);
}

static void
CDT_Parse1(benchmark::State &state)
{
	for (auto _ : state)
		Parse1();
}
BENCHMARK(CDT_Parse1);

BENCHMARK_MAIN();
