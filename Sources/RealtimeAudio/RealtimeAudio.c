#include "RealtimeAudio.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "The audio controls require lock-free 64-bit atomics.");
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "The event queue requires lock-free atomic integers.");
_Static_assert(ATOMIC_BOOL_LOCK_FREE == 2, "The transport requires a lock-free atomic flag.");

#define VOICES 5
#define KINDS 3
#define EVENTS 512

typedef struct { float *samples; uint32_t count; } Clip;
struct FDMEngine {
    double sampleRate;
    _Atomic uint64_t requested, epoch;
    _Atomic bool running;
    _Atomic uint32_t writeIndex, readIndex;
    FDMBeatEvent events[EVENTS];
    Clip clips[VOICES][KINDS];

    /* Everything below is accessed only by the audio thread. */
    uint64_t seenEpoch, frame, number;
    double nextFrame;
    FDMConfig active;
    uint32_t beat, subdivision, random;
    uint32_t audibleBarsLeft, silentBarsLeft, gapRemaining;
    bool needsGapPlan, silent;
    const Clip *clip;
    uint32_t clipPosition;
};

static uint32_t bound(uint32_t x, uint32_t lo, uint32_t hi) {
    return x < lo ? lo : (x > hi ? hi : x);
}
static FDMConfig sanitized(FDMConfig c) {
    c.bpm = bound(c.bpm, 30, 252);
    c.beats = bound(c.beats, 1, 9);
    c.subdivisions = bound(c.subdivisions, 1, 4);
    c.voice = bound(c.voice, 0, VOICES - 1);
    c.gapBars = bound(c.gapBars, 1, 8);
    if (c.gap != -1 && c.gap != 0 && c.gap != 1 && c.gap != 2 && c.gap != 4) c.gap = 0;
    return c;
}
static uint64_t pack(FDMConfig c) {
    c = sanitized(c);
    uint64_t gap = c.gap == -1 ? 7 : (uint64_t)c.gap;
    return (uint64_t)c.bpm | ((uint64_t)c.beats << 8) |
        ((uint64_t)c.subdivisions << 12) | ((uint64_t)c.voice << 15) |
        ((uint64_t)c.accent << 18) | (gap << 19) | ((uint64_t)c.gapBars << 22);
}
static FDMConfig unpack(uint64_t p) {
    uint32_t gap = (uint32_t)((p >> 19) & 7);
    FDMConfig c = {
        .bpm = (uint32_t)(p & 255), .beats = (uint32_t)((p >> 8) & 15),
        .subdivisions = (uint32_t)((p >> 12) & 7), .voice = (uint32_t)((p >> 15) & 7),
        .accent = ((p >> 18) & 1) != 0, .gap = gap == 7 ? -1 : (int32_t)gap,
        .gapBars = (uint32_t)((p >> 22) & 15)
    };
    return c;
}
FDMEngine *FDMEngineCreate(double sampleRate, uint32_t randomSeed) {
    if (!isfinite(sampleRate) || sampleRate <= 0) return NULL;
    FDMEngine *e = calloc(1, sizeof(*e));
    if (!e) return NULL;
    e->sampleRate = sampleRate;
    e->random = randomSeed ? randomSeed : 1;
    atomic_init(&e->requested, pack((FDMConfig){120, 4, 1, 0, true, 0, 1}));
    atomic_init(&e->epoch, 0);
    atomic_init(&e->running, false);
    atomic_init(&e->writeIndex, 0);
    atomic_init(&e->readIndex, 0);
    return e;
}
void FDMEngineDestroy(FDMEngine *e) {
    if (!e) return;
    for (uint32_t v = 0; v < VOICES; ++v)
        for (uint32_t k = 0; k < KINDS; ++k) free(e->clips[v][k].samples);
    free(e);
}
bool FDMEngineSetVoice(FDMEngine *e, uint32_t voice, uint32_t kind, const float *samples, uint32_t count) {
    if (!e || voice >= VOICES || kind >= KINDS || !samples || !count) return false;
    float *copy = malloc(sizeof(float) * count);
    if (!copy) return false;
    memcpy(copy, samples, sizeof(float) * count);
    free(e->clips[voice][kind].samples);
    e->clips[voice][kind] = (Clip){copy, count};
    return true;
}
void FDMEngineConfigure(FDMEngine *e, FDMConfig c) {
    atomic_store_explicit(&e->requested, pack(c), memory_order_release);
}
uint64_t FDMEngineStart(FDMEngine *e) {
    uint64_t epoch = atomic_fetch_add_explicit(&e->epoch, 1, memory_order_acq_rel) + 1;
    atomic_store_explicit(&e->running, true, memory_order_release);
    return epoch;
}
void FDMEngineStop(FDMEngine *e) {
    atomic_store_explicit(&e->running, false, memory_order_release);
    atomic_fetch_add_explicit(&e->epoch, 1, memory_order_acq_rel);
}
static void push(FDMEngine *e, FDMBeatEvent event) {
    uint32_t w = atomic_load_explicit(&e->writeIndex, memory_order_relaxed);
    uint32_t r = atomic_load_explicit(&e->readIndex, memory_order_acquire);
    /* A stalled UI may lose display events; it must never interrupt audio. */
    if ((uint32_t)(w - r) >= EVENTS) return;
    e->events[w % EVENTS] = event;
    atomic_store_explicit(&e->writeIndex, w + 1, memory_order_release);
}
bool FDMEnginePoll(FDMEngine *e, FDMBeatEvent *event) {
    uint32_t r = atomic_load_explicit(&e->readIndex, memory_order_relaxed);
    uint32_t w = atomic_load_explicit(&e->writeIndex, memory_order_acquire);
    if (r == w) return false;
    *event = e->events[r % EVENTS];
    atomic_store_explicit(&e->readIndex, r + 1, memory_order_release);
    return true;
}
static uint32_t audibleCount(FDMEngine *e) {
    if (e->active.gap != -1) return (uint32_t)e->active.gap;
    uint32_t x = e->random;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5; e->random = x;
    const uint32_t choices[] = {1, 2, 4};
    return choices[x % 3];
}
static void beginBar(FDMEngine *e) {
    if (!e->active.gap) {
        e->silent = false; e->gapRemaining = 0; e->needsGapPlan = true;
        return;
    }
    if (e->needsGapPlan) {
        e->audibleBarsLeft = audibleCount(e);
        e->silentBarsLeft = e->active.gapBars;
        e->needsGapPlan = false;
    }
    if (e->audibleBarsLeft) {
        --e->audibleBarsLeft;
        e->silent = false; e->gapRemaining = 0;
    } else {
        e->silent = true; e->gapRemaining = e->silentBarsLeft;
        if (--e->silentBarsLeft == 0) e->needsGapPlan = true;
    }
}
static void beginBeat(FDMEngine *e, uint64_t hostTime) {
    FDMConfig requested = unpack(atomic_load_explicit(&e->requested, memory_order_acquire));
    e->active.bpm = requested.bpm;
    e->active.subdivisions = requested.subdivisions;
    e->active.voice = requested.voice;
    e->active.accent = requested.accent;
    if (!e->beat) {
        if (e->active.gap != requested.gap || e->active.gapBars != requested.gapBars)
            e->needsGapPlan = true;
        e->active.beats = requested.beats;
        e->active.gap = requested.gap;
        e->active.gapBars = requested.gapBars;
        beginBar(e);
    }
    push(e, (FDMBeatEvent){
        .epoch = e->seenEpoch, .hostTime = hostTime, .number = ++e->number,
        .beat = e->beat, .gapBarsRemaining = e->gapRemaining, .config = e->active
    });
}
void FDMEngineRender(FDMEngine *e, float *output, uint32_t frames, uint64_t hostTime, double hostTicksPerFrame) {
    if (!atomic_load_explicit(&e->running, memory_order_acquire)) {
        memset(output, 0, sizeof(float) * frames);
        e->clip = NULL;
        e->frame += frames;
        return;
    }
    uint64_t epoch = atomic_load_explicit(&e->epoch, memory_order_acquire);
    if (epoch != e->seenEpoch) {
        e->seenEpoch = epoch;
        e->active = unpack(atomic_load_explicit(&e->requested, memory_order_acquire));
        e->nextFrame = (double)e->frame;
        e->beat = e->subdivision = 0; e->number = 0;
        e->needsGapPlan = true; e->gapRemaining = 0; e->clip = NULL;
    }
    for (uint32_t i = 0; i < frames; ++i, ++e->frame) {
        if ((double)e->frame + 0.5 >= e->nextFrame) {
            if (!e->subdivision)
                beginBeat(e, hostTime + (uint64_t)llround((double)i * hostTicksPerFrame));
            uint32_t kind = e->subdivision ? 2 : (e->active.accent && !e->beat ? 0 : 1);
            e->clip = e->silent ? NULL : &e->clips[e->active.voice][kind];
            e->clipPosition = 0;
            e->nextFrame += e->sampleRate * 60.0 / e->active.bpm / e->active.subdivisions;
            if (++e->subdivision == e->active.subdivisions) {
                e->subdivision = 0;
                if (++e->beat == e->active.beats) e->beat = 0;
            }
        }
        output[i] = e->clip && e->clipPosition < e->clip->count ? e->clip->samples[e->clipPosition++] : 0;
    }
}

