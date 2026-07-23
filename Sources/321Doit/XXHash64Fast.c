#include "XXHash64Fast.h"

#include <stdlib.h>
#include <string.h>

#define XXH_PRIME64_1 11400714785074694791ULL
#define XXH_PRIME64_2 14029467366897019727ULL
#define XXH_PRIME64_3 1609587929392839161ULL
#define XXH_PRIME64_4 9650029242287828579ULL
#define XXH_PRIME64_5 2870177450012600261ULL

struct DoitXXH64State {
    uint64_t seed;
    uint64_t total_len;
    uint64_t v1;
    uint64_t v2;
    uint64_t v3;
    uint64_t v4;
    uint8_t memory[32];
    size_t memory_size;
};

static inline uint64_t rotl64(uint64_t value, int amount) {
    return (value << amount) | (value >> (64 - amount));
}

static inline uint64_t read64le(const void *ptr) {
    uint64_t value;
    memcpy(&value, ptr, sizeof(value));
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    value = __builtin_bswap64(value);
#endif
    return value;
}

static inline uint32_t read32le(const void *ptr) {
    uint32_t value;
    memcpy(&value, ptr, sizeof(value));
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    value = __builtin_bswap32(value);
#endif
    return value;
}

static inline uint64_t xxh64_round(uint64_t acc, uint64_t input) {
    acc += input * XXH_PRIME64_2;
    acc = rotl64(acc, 31);
    acc *= XXH_PRIME64_1;
    return acc;
}

static inline uint64_t xxh64_merge_round(uint64_t acc, uint64_t value) {
    acc ^= xxh64_round(0, value);
    acc = acc * XXH_PRIME64_1 + XXH_PRIME64_4;
    return acc;
}

static inline void process_stripe(DoitXXH64State *state, const uint8_t *ptr) {
    state->v1 = xxh64_round(state->v1, read64le(ptr));
    state->v2 = xxh64_round(state->v2, read64le(ptr + 8));
    state->v3 = xxh64_round(state->v3, read64le(ptr + 16));
    state->v4 = xxh64_round(state->v4, read64le(ptr + 24));
}

DoitXXH64State *doit_xxh64_create(void) {
    DoitXXH64State *state = (DoitXXH64State *)calloc(1, sizeof(DoitXXH64State));
    if (state == NULL) {
        return NULL;
    }

    state->seed = 0;
    state->v1 = state->seed + XXH_PRIME64_1 + XXH_PRIME64_2;
    state->v2 = state->seed + XXH_PRIME64_2;
    state->v3 = state->seed;
    state->v4 = state->seed - XXH_PRIME64_1;
    return state;
}

void doit_xxh64_update(DoitXXH64State *state, const void *data, size_t length) {
    if (state == NULL || data == NULL || length == 0) {
        return;
    }

    const uint8_t *ptr = (const uint8_t *)data;
    size_t remaining = length;
    state->total_len += (uint64_t)length;

    if (state->memory_size > 0) {
        size_t needed = 32 - state->memory_size;
        if (remaining < needed) {
            memcpy(state->memory + state->memory_size, ptr, remaining);
            state->memory_size += remaining;
            return;
        }

        memcpy(state->memory + state->memory_size, ptr, needed);
        process_stripe(state, state->memory);
        state->memory_size = 0;
        ptr += needed;
        remaining -= needed;
    }

    while (remaining >= 32) {
        process_stripe(state, ptr);
        ptr += 32;
        remaining -= 32;
    }

    if (remaining > 0) {
        memcpy(state->memory, ptr, remaining);
        state->memory_size = remaining;
    }
}

uint64_t doit_xxh64_digest(const DoitXXH64State *state) {
    if (state == NULL) {
        return 0;
    }

    uint64_t hash;
    if (state->total_len >= 32) {
        hash = rotl64(state->v1, 1)
            + rotl64(state->v2, 7)
            + rotl64(state->v3, 12)
            + rotl64(state->v4, 18);
        hash = xxh64_merge_round(hash, state->v1);
        hash = xxh64_merge_round(hash, state->v2);
        hash = xxh64_merge_round(hash, state->v3);
        hash = xxh64_merge_round(hash, state->v4);
    } else {
        hash = state->seed + XXH_PRIME64_5;
    }

    hash += state->total_len;

    const uint8_t *ptr = state->memory;
    size_t remaining = state->memory_size;

    while (remaining >= 8) {
        uint64_t k1 = xxh64_round(0, read64le(ptr));
        hash ^= k1;
        hash = rotl64(hash, 27) * XXH_PRIME64_1 + XXH_PRIME64_4;
        ptr += 8;
        remaining -= 8;
    }

    if (remaining >= 4) {
        hash ^= (uint64_t)read32le(ptr) * XXH_PRIME64_1;
        hash = rotl64(hash, 23) * XXH_PRIME64_2 + XXH_PRIME64_3;
        ptr += 4;
        remaining -= 4;
    }

    while (remaining > 0) {
        hash ^= (uint64_t)(*ptr) * XXH_PRIME64_5;
        hash = rotl64(hash, 11) * XXH_PRIME64_1;
        ptr += 1;
        remaining -= 1;
    }

    hash ^= hash >> 33;
    hash *= XXH_PRIME64_2;
    hash ^= hash >> 29;
    hash *= XXH_PRIME64_3;
    hash ^= hash >> 32;
    return hash;
}

void doit_xxh64_free(DoitXXH64State *state) {
    free(state);
}
