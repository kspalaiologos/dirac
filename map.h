
/* Slightly modified Mashpoe's hashmap implementation. */
/* Original: https://github.com/Mashpoe/c-hashmap */

/* List of my changes (@Palaiologos):
 * - C89 compliance
 * - Remove the tombstone mechanic
 * - More hash functions
 * 
 * Note: hashing is unnecessary here since the keys are pointers that uniquely
 * correspond to variable names. TODO: simplify and remove hashing?
 */

#ifndef _MAP_H_
#define _MAP_H_

#define hashmap_str_lit(str) (str), sizeof(str) - 1
#define hashmap_static_arr(arr) (arr), sizeof(arr)

#include <stdlib.h>
#include <string.h>
#include <stddef.h>

#define HASHMAP_HASH_INIT 2166136261u

#ifdef DIRAC_64
static uint32_t hash_data(const unsigned char* data, size_t size)
{
	size_t nblocks = size / 8;
	uint64_t hash = HASHMAP_HASH_INIT, last;
	size_t i;
	for (i = 0; i < nblocks; ++i)
	{
		hash ^= (uint64_t)data[0] << 0 | (uint64_t)data[1] << 8 |
			 (uint64_t)data[2] << 16 | (uint64_t)data[3] << 24 |
			 (uint64_t)data[4] << 32 | (uint64_t)data[5] << 40 |
			 (uint64_t)data[6] << 48 | (uint64_t)data[7] << 56;
		hash *= 0xbf58476d1ce4e5b9;
		data += 8;
	}

	last = size & 0xff;
	switch (size % 8)
	{
	case 7:
		last |= (uint64_t)data[6] << 56; /* fallthrough */
	case 6:
		last |= (uint64_t)data[5] << 48; /* fallthrough */
	case 5:
		last |= (uint64_t)data[4] << 40; /* fallthrough */
	case 4:
		last |= (uint64_t)data[3] << 32; /* fallthrough */
	case 3:
		last |= (uint64_t)data[2] << 24; /* fallthrough */
	case 2:
		last |= (uint64_t)data[1] << 16; /* fallthrough */
	case 1:
		last |= (uint64_t)data[0] << 8;
		hash ^= last;
		hash *= 0xd6e8feb86659fd93;
	}

	/* compress to a 32-bit result. also serves as a finalizer. */
	return hash ^ hash >> 32;
}
#else
#ifdef DIRAC_32
static uint32_t hash_data(const unsigned char* data, size_t size) {
	int i, j;
	unsigned int byte, crc, mask;

	i = 0;
	crc = 0xFFFFFFFF;
	while (i < size) {
		byte = data[i];
		crc = crc ^ byte;
		for (j = 7; j >= 0; j--) {
			mask = -(crc & 1);
			crc = (crc >> 1) ^ (0xEDB88320 & mask);
		}
		i = i + 1;
	}
	return ~crc;
}
#else
static uint16_t hash_data(const unsigned char* data, size_t size) {
    unsigned char x;
    unsigned short crc = 0xFFFF;

    while (size--){
        x = crc >> 8 ^ *data++;
        x ^= x>>4;
        crc = (crc << 8) ^ ((unsigned short)(x << 12)) ^ ((unsigned short)(x <<5)) ^ ((unsigned short)x);
    }
    return crc;
}
#endif
#endif

/* hashmaps can associate keys with pointer values or integral types. */
typedef struct hashmap hashmap;

/* a callback type used for iterating over a map/freeing entries:
 * `void <function name>(void* key, size_t size, uintptr_t value, void* usr)`
 * `usr` is a user pointer which can be passed through `hashmap_iterate`.
 */
typedef void (*hashmap_callback)(void *key, size_t ksize, uintptr_t value, void *usr);

static hashmap* hashmap_create(void);

/* only frees the hashmap object and buckets.
 * does not call free on each element's `key` or `value`.
 * to free data associated with an element, call `hashmap_iterate`.
 */
static void hashmap_free(hashmap* map);

/* does not make a copy of `key`.
 * you must copy it yourself if you want to guarantee its lifetime,
 * or if you intend to call `hashmap_key_free`.
 */
static void hashmap_set(hashmap* map, void* key, size_t ksize, uintptr_t value);

/* adds an entry if it doesn't exist, using the value of `*out_in`.
 * if it does exist, it sets value in `*out_in`, meaning the value
 * of the entry will be in `*out_in` regardless of whether or not
 * it existed in the first place.
 * returns true if the entry already existed, returns false otherwise.
 */
static int hashmap_get_set(hashmap* map, void* key, size_t ksize, uintptr_t* out_in);

/* similar to `hashmap_set()`, but when overwriting an entry,
 * you'll be able properly free the old entry's data via a callback.
 * unlike `hashmap_set()`, this function will overwrite the original key pointer,
 * which means you can free the old key in the callback if applicable.
 */
static void hashmap_set_free(hashmap* map, void* key, size_t ksize, uintptr_t value, hashmap_callback c, void* usr);

static int hashmap_get(hashmap* map, void* key, size_t ksize, uintptr_t* out_val);

static int hashmap_size(hashmap* map);

/* iterate over the map, calling `c` on every element.
 * goes through elements in the order they were added.
 * the element's key, key size, value, and `usr` will be passed to `c`.
 */
static void hashmap_iterate(hashmap* map, hashmap_callback c, void* usr);

#define HASHMAP_DEFAULT_CAPACITY 5
#define HASHMAP_MAX_LOAD 0.75f
#define HASHMAP_RESIZE_FACTOR 2

struct bucket
{
	/* `next` must be the first struct element.
	 * changing the order will break multiple functions */
	struct bucket* next;

	/* key, key size, key hash, and associated value */
	void* key;
	size_t ksize;
	uint32_t hash;
	uintptr_t value;
};

struct hashmap
{
	struct bucket* buckets;
	int capacity;
	int count;

	/* a linked list of all valid entries, in order */
	struct bucket* first;
	/* lets us know where to add the next element */
	struct bucket* last;
};

static hashmap* hashmap_create(void)
{
	hashmap* m = malloc(sizeof(hashmap));
	m->capacity = HASHMAP_DEFAULT_CAPACITY;
	m->count = 0;
	
	m->buckets = calloc(HASHMAP_DEFAULT_CAPACITY, sizeof(struct bucket));
	m->first = NULL;

	/* this prevents branching in hashmap_set.
	 * m->first will be treated as the "next" pointer in an imaginary bucket.
	 * when the first item is added, m->first will be set to the correct address.
	 */
	m->last = (struct bucket*)&m->first;
	return m;
}

static void hashmap_free(hashmap* m)
{
	free(m->buckets);
	free(m);
}

/* puts an old bucket into a resized hashmap */
static struct bucket* resize_entry(hashmap* m, struct bucket* old_entry)
{
	uint32_t index = old_entry->hash % m->capacity;
	for (;;)
	{
		struct bucket* entry = &m->buckets[index];

		if (entry->key == NULL)
		{
			*entry = *old_entry;
			return entry;
		}

		index = (index + 1) % m->capacity;
	}
}

static void hashmap_resize(hashmap* m)
{
	struct bucket* old_buckets = m->buckets;

	m->capacity *= HASHMAP_RESIZE_FACTOR;
	m->buckets = calloc(m->capacity, sizeof(struct bucket));
	m->last = (struct bucket*)&m->first;

	do
	{
		m->last->next = resize_entry(m, m->last->next);
		m->last = m->last->next;
	} while (m->last->next != NULL);

	free(old_buckets);
}

static struct bucket* find_entry(hashmap* m, void* key, size_t ksize, uint32_t hash)
{
	uint32_t index = hash % m->capacity;

	for (;;)
	{
		struct bucket* entry = &m->buckets[index];

		/* kind of a thicc condition; */
		/* I didn't want this to span multiple if statements or functions. */
		if (entry->key == NULL ||
			/* compare sizes, then hashes, then key data as a last resort. */
			(entry->ksize == ksize &&
			 entry->hash == hash &&
			 memcmp(entry->key, key, ksize) == 0))
		{
			/* return the entry if a match or an empty bucket is found */
			return entry;
		}

		index = (index + 1) % m->capacity;
	}
}

static void hashmap_set(hashmap* m, void* key, size_t ksize, uintptr_t val)
{
	uint32_t hash;
	struct bucket * entry;

	if (m->count + 1 > HASHMAP_MAX_LOAD * m->capacity)
		hashmap_resize(m);

	hash = hash_data(key, ksize);
	entry = find_entry(m, key, ksize, hash);
	if (entry->key == NULL)
	{
		m->last->next = entry;
		m->last = entry;
		entry->next = NULL;

		++m->count;

		entry->key = key;
		entry->ksize = ksize;
		entry->hash = hash;
	}
	entry->value = val;
}

static int hashmap_get_set(hashmap* m, void* key, size_t ksize, uintptr_t* out_in)
{
	uint32_t hash;
	struct bucket * entry;

	if (m->count + 1 > HASHMAP_MAX_LOAD * m->capacity)
		hashmap_resize(m);

	hash = hash_data(key, ksize);
	entry = find_entry(m, key, ksize, hash);
	if (entry->key == NULL)
	{
		m->last->next = entry;
		m->last = entry;
		entry->next = NULL;

		++m->count;

		entry->value = *out_in;
		entry->key = key;
		entry->ksize = ksize;
		entry->hash = hash;

		return 0;
	}
	*out_in = entry->value;
	return 1;
}

static void hashmap_set_free(hashmap* m, void* key, size_t ksize, uintptr_t val, hashmap_callback c, void* usr)
{
	uint32_t hash;
	struct bucket * entry;

	if (m->count + 1 > HASHMAP_MAX_LOAD * m->capacity)
		hashmap_resize(m);

	hash = hash_data(key, ksize);
	entry = find_entry(m, key, ksize, hash);
	if (entry->key == NULL)
	{
		m->last->next = entry;
		m->last = entry;
		entry->next = NULL;

		++m->count;

		entry->key = key;
		entry->ksize = ksize;
		entry->hash = hash;
		entry->value = val;
		return;
	}
	/* allow the callback to free entry data.
	 * use old key and value so the callback can free them.
	 * the old key and value will be overwritten after this call. */
	c(entry->key, ksize, entry->value, usr);

	/* overwrite the old key pointer in case the callback frees it. */
	entry->key = key;
	entry->value = val;
}

static int hashmap_get(hashmap* m, void* key, size_t ksize, uintptr_t* out_val)
{
	uint32_t hash = hash_data(key, ksize);
	struct bucket* entry = find_entry(m, key, ksize, hash);

	/* if there is no match, output val will just be NULL */
	*out_val = entry->value;

	return entry->key != NULL;
}

static int hashmap_size(hashmap* m)
{
	return m->count;
}

static void hashmap_iterate(hashmap* m, hashmap_callback c, void* user_ptr)
{
	/* loop through the linked list of valid entries
	 * this way we can skip over empty buckets */
	struct bucket* current = m->first;
	
	int co = 0;

	while (current != NULL)
	{
		c(current->key, current->ksize, current->value, user_ptr);
		
		current = current->next;

		if (co > 1000)
		{
			break;
		}
		co++;

	}
}

#endif