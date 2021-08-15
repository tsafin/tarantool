#include "dt.h"
#include <string.h>
#include <assert.h>
#include <limits.h>

#include "datetime-common.h"

template <typename T>
struct datetime_bench
{
	T secs;
	uint32_t nsec;
	uint32_t offset;

static struct datetime_bench date_array[];
};
template<typename T>
struct datetime_bench<T> datetime_bench<T>::date_array[DIM(tests)];

/// Parse 70 datetime literals of various lengths
template <typename T>
static void
Assign70()
{
	size_t index;
	int64_t secs_expected;
	int nanosecs;
	int ofs;
	using dt_bench = datetime_bench<T>;

	for (index = 0; index < DIM(tests); index++) {
		int64_t secs;
		int rc = parse_datetime(tests[index].sz, tests[index].len,
					&secs, &nanosecs, &ofs);
		assert(rc == 0);
		dt_bench::date_array[index].secs = (T)secs;
		dt_bench::date_array[index].nsec = nanosecs;
		dt_bench::date_array[index].offset = ofs;
	}
}

template <typename T>
static void
DateTime_Assign70(benchmark::State &state)
{
	for (auto _ : state)
		Assign70<T>();
}
BENCHMARK_TEMPLATE1(DateTime_Assign70, uint64_t);
BENCHMARK_TEMPLATE1(DateTime_Assign70, double);

#define COMPARE_RESULT_BENCH(a, b) (a < b ? -1 : a > b)

template <typename T>
int datetime_compare(const struct datetime_bench<T> *lhs,
		     const struct datetime_bench<T> *rhs)
{
	int result = COMPARE_RESULT_BENCH(lhs->secs, rhs->secs);
	if (result != 0)
		return result;

	return COMPARE_RESULT_BENCH(lhs->nsec, rhs->nsec);
}

template <typename T>
static void
AssignCompare70()
{
	size_t index;
	int nanosecs;
	int ofs;
	using dt_bench = datetime_bench<T>;

	size_t arrays_sz = DIM(tests);
	for (index = 0; index < arrays_sz; index++) {
		int64_t secs;
		int rc = parse_datetime(tests[index].sz, tests[index].len,
					&secs, &nanosecs, &ofs);
		assert(rc == 0);
		dt_bench::date_array[index].secs = (T)secs;
		dt_bench::date_array[index].nsec = nanosecs;
		dt_bench::date_array[index].offset = ofs;
	}

	for (index = 0; index < (arrays_sz - 1); index++) {
		volatile int rc = datetime_compare<T>(&dt_bench::date_array[index],
					     &dt_bench::date_array[index + 1]);
		assert(rc == 0 || rc == -1 || rc == 1);
	}
}

template <typename T>
static void
DateTime_AssignCompare70(benchmark::State &state)
{
	for (auto _ : state)
		AssignCompare70<T>();
}
BENCHMARK_TEMPLATE1(DateTime_AssignCompare70, uint64_t);
BENCHMARK_TEMPLATE1(DateTime_AssignCompare70, double);

template <typename T>
static void
Compare20()
{
	size_t index;
	int nanosecs;
	int ofs;
	using dt_bench = datetime_bench<T>;

	for (size_t i = 0; i < 10; i++) {
		volatile int rc = datetime_compare<T>(&dt_bench::date_array[i],
					     &dt_bench::date_array[32 + i]);
		assert(rc == 0 || rc == -1 || rc == 1);
	}
}

template <typename T>
static void
DateTime_Compare20(benchmark::State &state)
{
	for (auto _ : state)
		Compare20<T>();
}
BENCHMARK_TEMPLATE1(DateTime_Compare20, uint64_t);
BENCHMARK_TEMPLATE1(DateTime_Compare20, double);


#define SECS_EPOCH_1970_OFFSET ((int64_t)DT_EPOCH_1970_OFFSET * SECS_PER_DAY)

template<typename T>
int
datetime_to_string(const struct datetime_bench<T> *date, char *buf, uint32_t len)
{
#define ADVANCE(sz)		\
	if (buf != NULL) { 	\
		buf += sz; 	\
		len -= sz; 	\
	}			\
	ret += sz;

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

	int ret = 0;
	uint32_t sz = snprintf(buf, len, "%04d-%02d-%02dT%02d:%02d",
			       year, month, day, hour, minute);
	ADVANCE(sz);
	if (sec || ns) {
		sz = snprintf(buf, len, ":%02d", sec);
		ADVANCE(sz);
		if (ns) {
			if ((ns % 1000000) == 0)
				sz = snprintf(buf, len, ".%03d", ns / 1000000);
			else if ((ns % 1000) == 0)
				sz = snprintf(buf, len, ".%06d", ns / 1000);
			else
				sz = snprintf(buf, len, ".%09d", ns);
			ADVANCE(sz);
		}
	}
	if (offset == 0) {
		sz = snprintf(buf, len, "Z");
		ADVANCE(sz);
	}
	else {
		if (offset < 0)
			sign = '-', offset = -offset;
		else
			sign = '+';

		sz = snprintf(buf, len, "%c%02d:%02d", sign, offset / 60, offset % 60);
		ADVANCE(sz);
	}
	return ret;
}
#undef ADVANCE

template <typename T>
static void
ToString1()
{
	char buf[48];
	struct datetime_bench<T> dateval = datetime_bench<T>::date_array[13];

	volatile auto len = datetime_to_string<T>(&dateval, buf, sizeof buf);
}

template <typename T>
static void
DateTime_ToString1(benchmark::State &state)
{
	for (auto _ : state)
		ToString1<T>();
}
BENCHMARK_TEMPLATE1(DateTime_ToString1, uint64_t);
BENCHMARK_TEMPLATE1(DateTime_ToString1, double);
