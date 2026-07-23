#ifndef XXHASH64FAST_H
#define XXHASH64FAST_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DoitXXH64State DoitXXH64State;

DoitXXH64State *doit_xxh64_create(void);
void doit_xxh64_update(DoitXXH64State *state, const void *data, size_t length);
uint64_t doit_xxh64_digest(const DoitXXH64State *state);
void doit_xxh64_free(DoitXXH64State *state);

#ifdef __cplusplus
}
#endif

#endif
