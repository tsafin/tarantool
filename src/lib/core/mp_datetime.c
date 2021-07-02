/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright 2021, Tarantool AUTHORS, please see AUTHORS file.
 */

#include <limits.h>

#include "msgpuck.h"
#include "mp_datetime.h"
#include "mp_extension_types.h"
#include "mp_utils.h"

/*
  Datetime MessagePack serialization schema is MP_EXT (0xC7 for 1 byte length)
  extension, which creates container of 1 to 3 integers.

  +----+-----------+---+====~~~~~~~====+-----~~~~~~~~-------+....~~~~~~~....+
  |0xC7|len (uint8)| 4 | seconds (int) | nanoseconds (uint) | offset (int)  |
  +----+-----------+---+====~~~~~~~====+-----~~~~~~~~-------+....~~~~~~~....+

  MessagePack extension MP_EXT (0xC7), after 1-byte length, contains:

  - signed integer seconds part (required). Depending on the value of
    seconds it may be from 1 to 8 bytes positive or negative integer number;

  - [optional] fraction time in nanoseconds as unsigned integer.
    If this value is 0 then it's not saved (unless there is offset field,
    as below);

  - [optional] timezone offset in minutes as signed integer.
    If this field is 0 then it's not saved.
 */


#define check_secs(secs)                                \
	assert((int64_t)(secs) <= MAX_EPOCH_SECS_VALUE);\
	assert((int64_t)(secs) >= MIN_EPOCH_SECS_VALUE);

#define check_nanosecs(nsec)      assert((nsec) < 1000000000);

#define check_tz_offset(offset)       \
	assert((offset) <= (12 * 60));\
	assert((offset) >= (-12 * 60));

static inline uint32_t
mp_sizeof_datetime_raw(const struct datetime *date)
{
	check_secs(date->secs);
	uint32_t sz = mp_sizeof_xint(date->secs);

	/*
	 * even if nanosecs == 0 we need to output something
	 * if we have a non-null tz offset
	 */
	if (date->nsec != 0 || date->offset != 0) {
		check_nanosecs(date->nsec);
		sz += mp_sizeof_xint(date->nsec);
	}
	if (date->offset != 0) {
		check_tz_offset(date->offset);
		sz += mp_sizeof_xint(date->offset);
	}
	return sz;
}

uint32_t
mp_sizeof_datetime(const struct datetime *date)
{
	return mp_sizeof_ext(mp_sizeof_datetime_raw(date));
}

struct datetime *
datetime_unpack(const char **data, uint32_t len, struct datetime *date)
{
	const char *svp = *data;

	memset(date, 0, sizeof(*date));

	int64_t seconds = mp_decode_xint(data);
	check_secs(seconds);
	date->secs = seconds;

	len -= *data - svp;
	if (len <= 0)
		return date;

	svp = *data;
	uint64_t nanoseconds = mp_decode_uint(data);
	check_nanosecs(nanoseconds);
	date->nsec = nanoseconds;
	len -= *data - svp;

	if (len <= 0)
		return date;

	int64_t offset = mp_decode_xint(data);
	check_tz_offset(offset);
	date->offset = offset;

	return date;
}

struct datetime *
mp_decode_datetime(const char **data, struct datetime *date)
{
	if (mp_typeof(**data) != MP_EXT)
		return NULL;

	const char *svp = *data;
	int8_t type;
	uint32_t len = mp_decode_extl(data, &type);

	if (type != MP_DATETIME || len == 0) {
		*data = svp;
		return NULL;
	}
	return datetime_unpack(data, len, date);
}

char *
datetime_pack(char *data, const struct datetime *date)
{
	data = mp_encode_xint(data, date->secs);
	if (date->nsec != 0 || date->offset != 0)
		data = mp_encode_uint(data, date->nsec);
	if (date->offset)
		data = mp_encode_xint(data, date->offset);

	return data;
}

char *
mp_encode_datetime(char *data, const struct datetime *date)
{
	uint32_t len = mp_sizeof_datetime_raw(date);

	data = mp_encode_extl(data, MP_DATETIME, len);

	return datetime_pack(data, date);
}

int
mp_snprint_datetime(char *buf, int size, const char **data, uint32_t len)
{
	struct datetime date = {
		.secs = 0, .nsec = 0, .offset = 0
	};

	if (datetime_unpack(data, len, &date) == NULL)
		return -1;

	return datetime_to_string(&date, buf, size);
}

int
mp_fprint_datetime(FILE *file, const char **data, uint32_t len)
{
	struct datetime date = {
		.secs = 0, .nsec = 0, .offset = 0
	};

	if (datetime_unpack(data, len, &date) == NULL)
		return -1;

	char buf[DT_TO_STRING_BUFSIZE];
	datetime_to_string(&date, buf, sizeof(buf));

	return fprintf(file, "%s", buf);
}

