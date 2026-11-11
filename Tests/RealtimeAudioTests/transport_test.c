#include "RealtimeAudio.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

#define CAPACITY 20000
typedef struct { uint64_t frame; float value; } Click;
typedef struct {
    FDMEngine *engine;
    uint64_t frame;
    FDMBeatEvent events[CAPACITY];
    Click clicks[CAPACITY];
    unsigned eventCount, clickCount;
} Harness;

static FDMConfig config(void) { return (FDMConfig){120, 4, 1, 0, true, 0, 1}; }
static Harness *create(FDMConfig c) {
    Harness *h = calloc(1, sizeof(*h));
    assert(h);
    h->engine = FDMEngineCreate(48000, 17);
    assert(h->engine);
    for (unsigned v = 0; v < 5; ++v) for (unsigned k = 0; k < 3; ++k) {
        float impulse = (float)(v * 3 + k + 1);
        assert(FDMEngineSetVoice(h->engine, v, k, &impulse, 1));
    }
    FDMEngineConfigure(h->engine, c);
    FDMEngineStart(h->engine);
    return h;
}
static void collect(Harness *h) {
    FDMBeatEvent event;
    while (FDMEnginePoll(h->engine, &event)) {
        assert(h->eventCount < CAPACITY);
        h->events[h->eventCount++] = event;
    }
}
static void advance(Harness *h, uint64_t target, bool poll) {
    while (h->frame < target) {
        float output[257];
        unsigned n = target - h->frame > 257 ? 257 : (unsigned)(target - h->frame);
        FDMEngineRender(h->engine, output, n, h->frame, 1);
        for (unsigned i = 0; i < n; ++i) if (output[i] != 0) {
            assert(h->clickCount < CAPACITY);
            h->clicks[h->clickCount++] = (Click){h->frame + i, output[i]};
        }
        h->frame += n;
        if (poll) collect(h);
    }
}
static void destroy(Harness *h) { FDMEngineDestroy(h->engine); free(h); }
static void nextBeatAndBar(void) {
    FDMConfig c = config();
    Harness *h = create(c);
    advance(h, 6000, true);
    c.bpm = 180; c.voice = 2; c.accent = false; c.subdivisions = 3; c.beats = 3;
    FDMEngineConfigure(h->engine, c);
    advance(h, 24000, true);
    assert(h->clickCount == 1 && h->eventCount == 1);
    advance(h, 104001, true);
    const uint64_t expected[] = {0, 24000, 40000, 56000, 72000, 88000, 104000};
    for (unsigned i = 0; i < 7; ++i) {
        FDMBeatEvent e = h->events[i];
        assert(e.hostTime == expected[i] && e.number == i + 1);
        assert(e.beat == (i < 4 ? i : (i - 4) % 3));
        assert(e.config.beats == (i < 4 ? 4 : 3));
        assert(e.config.bpm == (i ? 180 : 120));
        assert(e.config.voice == (i ? 2 : 0));
        assert(e.config.accent == (i == 0));
    }
    assert(h->clicks[1].frame == 24000 && h->clicks[1].value == 8);
    assert(h->clicks[2].frame == 29333 && h->clicks[2].value == 9);
    assert(h->clicks[3].frame == 34667 && h->clicks[3].value == 9);
    destroy(h);
}
static void finishCurrentSubdivision(void) {
    FDMConfig c = config(); c.subdivisions = 2;
    Harness *h = create(c);
    advance(h, 6000, true);
    c.subdivisions = 1; c.voice = 4; c.accent = false;
    FDMEngineConfigure(h->engine, c);
    advance(h, 48001, true);
    assert(h->clickCount == 4);
    assert(h->clicks[1].frame == 12000 && h->clicks[1].value == 3);
    assert(h->clicks[2].frame == 24000 && h->clicks[2].value == 14);
    assert(h->events[1].number == 2 && h->events[1].beat == 1);
    destroy(h);
}
static void gapCountdown(void) {
    FDMConfig c = config(); c.beats = 2; c.gap = 1; c.gapBars = 2;
    Harness *h = create(c);
    advance(h, 150001, true);
    const unsigned remaining[] = {0,0,2,2,1,1,0};
    assert(h->eventCount == 7 && h->clickCount == 3);
    for (unsigned i = 0; i < 7; ++i) {
        assert(h->events[i].gapBarsRemaining == remaining[i]);
        assert(h->events[i].beat == i % 2 && h->events[i].number == i + 1);
    }
    destroy(h);
}
static void editsDuringGap(void) {
    FDMConfig c = config(); c.beats = 2; c.gap = 1; c.gapBars = 2;
    Harness *h = create(c);
    advance(h, 54000, true); // First silent bar, after its first beat.
    c.bpm = 240; c.voice = 3; c.subdivisions = 4;
    FDMEngineConfigure(h->engine, c);
    advance(h, 108001, true);
    assert(h->clickCount == 3); // Two initial clicks and first beat after the gap.
    assert(h->clicks[2].frame == 108000 && h->clicks[2].value == 10);
    assert(h->events[3].hostTime == 72000 && h->events[3].beat == 1);
    assert(h->events[3].config.bpm == 240 && h->events[3].gapBarsRemaining == 2);
    assert(h->events[4].hostTime == 84000 && h->events[4].gapBarsRemaining == 1);
    assert(h->events[6].number == 7 && h->events[6].gapBarsRemaining == 0);
    assert(h->events[3].cycleBar == 1 && h->events[4].cycleBar == 2);
    assert(h->events[6].cycleBar == 0 && h->events[6].cycleAudibleBars == 1);
    destroy(h);
}
static void gapEditAtBar(void) {
    FDMConfig c = config(); c.beats = 2; c.gap = 1; c.gapBars = 2;
    Harness *h = create(c);
    advance(h, 54000, true);
    c.gap = 0; c.beats = 3; c.gapBars = 8;
    FDMEngineConfigure(h->engine, c);
    advance(h, 144001, true);
    assert(h->events[3].beat == 1 && h->events[3].config.beats == 2);
    assert(h->events[3].config.gapBars == 2 && h->events[3].gapBarsRemaining == 2);
    assert(h->events[4].beat == 0 && h->events[4].config.beats == 3);
    assert(h->events[4].gapBarsRemaining == 0 && h->events[4].config.gapBars == 8);
    assert(h->clicks[2].frame == 96000);
    assert(h->events[6].beat == 2 && h->events[6].number == 7);
    destroy(h);
}
static void randomWholeBars(void) {
    for (unsigned length = 1; length <= 8; ++length) {
        FDMConfig c = config(); c.bpm = 240; c.beats = 1; c.gap = -1; c.gapBars = length;
        Harness *h = create(c);
        advance(h, 12000 * 200 + 1, true);
        unsigned audible = 0, cycles = 0;
        for (unsigned i = 0; i < h->eventCount; ++i) {
            FDMBeatEvent e = h->events[i];
            assert(e.number == i + 1 && e.beat == 0);
            assert(e.cycleAudibleBars == 1 || e.cycleAudibleBars == 2 || e.cycleAudibleBars == 4);
            assert(e.cycleBar < e.cycleAudibleBars + length);
            if (e.gapBarsRemaining)
                assert(e.cycleBar == e.cycleAudibleBars + length - e.gapBarsRemaining);
            else
                assert(e.cycleBar == audible);
            if (!e.gapBarsRemaining) { ++audible; continue; }
            if (e.gapBarsRemaining == length) {
                assert(audible == 1 || audible == 2 || audible == 4);
                audible = 0; ++cycles;
            } else {
                assert(i && h->events[i-1].gapBarsRemaining == e.gapBarsRemaining + 1);
            }
        }
        assert(cycles > 10);
        destroy(h);
    }
}
static void fractionalClock(void) {
    FDMConfig c = config(); c.bpm = 137; c.subdivisions = 3;
    Harness *h = create(c);
    double interval = 48000.0 * 60 / 137 / 3;
    advance(h, (uint64_t)llround(interval * 3000) + 1, true);
    assert(h->clickCount == 3001);
    for (unsigned i = 0; i < h->clickCount; ++i)
        assert(h->clicks[i].frame == (uint64_t)llround(interval * i));
    for (unsigned i = 0; i < h->eventCount; ++i)
        assert(h->events[i].number == i + 1 && h->events[i].beat == i % 4);
    destroy(h);
}
static void stalledUIAndRestart(void) {
    FDMConfig c = config(); c.bpm = 240;
    Harness *h = create(c);
    advance(h, 12000 * 600 + 1, false);
    assert(h->clickCount == 601); // Ring full cannot interrupt the clock.
    collect(h);
    assert(h->eventCount == 512);
    h->eventCount = 0;
    advance(h, 12000 * 601 + 1, true);
    assert(h->events[0].number == 602);
    uint64_t oldEpoch = h->events[0].epoch;
    FDMEngineStop(h->engine);
    unsigned clicks = h->clickCount;
    advance(h, h->frame + 20000, true);
    assert(h->clickCount == clicks);
    uint64_t epoch = FDMEngineStart(h->engine);
    h->eventCount = 0;
    uint64_t startFrame = h->frame;
    advance(h, startFrame + 1, true);
    assert(epoch != oldEpoch && h->events[0].epoch == epoch);
    assert(h->events[0].beat == 0 && h->events[0].number == 1);
    assert(h->clicks[h->clickCount-1].frame == startFrame);
    destroy(h);
}
static void barSequencePositions(void) {
    FDMConfig c = config(); c.gap = 2; c.gapBars = 2; c.subdivisions = 3;
    Harness *h = create(c);
    advance(h, 384001, true); // Four 4-beat bars plus the next cycle's downbeat.
    assert(h->eventCount == 17);
    for (unsigned i = 0; i < h->eventCount; ++i) {
        FDMBeatEvent e = h->events[i];
        unsigned bar = (i / 4) % 4;
        assert(e.cycleAudibleBars == 2 && e.cycleBar == bar);
        assert(e.gapBarsRemaining == (bar < 2 ? 0 : 4 - bar));
        assert(e.beat == i % 4);
    }
    // Gap Off commits on the next bar and removes all sequence state.
    c.gap = 0;
    FDMEngineConfigure(h->engine, c);
    advance(h, 480001, true);
    FDMBeatEvent last = h->events[h->eventCount - 1];
    assert(last.beat == 0 && last.config.gap == 0);
    assert(last.cycleAudibleBars == 0 && last.cycleBar == 0);
    destroy(h);
}
static void coalescedEdits(void) {
    FDMConfig c = config();
    Harness *h = create(c);
    advance(h, 6000, true);
    c.bpm = 60; c.subdivisions = 4; c.voice = 1;
    FDMEngineConfigure(h->engine, c);
    advance(h, 12000, true);
    c.bpm = 240; c.subdivisions = 2; c.voice = 4;
    FDMEngineConfigure(h->engine, c);
    advance(h, 36001, true);
    assert(h->events[1].hostTime == 24000 && h->events[1].config.bpm == 240);
    assert(h->events[1].config.voice == 4 && h->events[1].config.subdivisions == 2);
    assert(h->events[2].hostTime == 36000 && h->events[2].number == 3);
    assert(h->clicks[1].frame == 24000 && h->clicks[2].frame == 30000);
    destroy(h);
}
static void *writeControls(void *engine) {
    FDMConfig first = config(), second = config();
    second.bpm = 240; second.voice = 4; second.subdivisions = 3;
    for (unsigned i = 0; i < 200000; ++i)
        FDMEngineConfigure(engine, i % 2 ? first : second);
    return NULL;
}
static void concurrentControls(void) {
    Harness *h = create(config());
    pthread_t writer;
    assert(pthread_create(&writer, NULL, writeControls, h->engine) == 0);
    advance(h, 48000 * 20, true);
    assert(pthread_join(writer, NULL) == 0);
    assert(h->eventCount > 30);
    for (unsigned i = 0; i < h->eventCount; ++i) {
        FDMBeatEvent e = h->events[i];
        assert((e.config.bpm == 120 && e.config.voice == 0 && e.config.subdivisions == 1) ||
               (e.config.bpm == 240 && e.config.voice == 4 && e.config.subdivisions == 3));
        assert(e.number == i + 1 && e.beat == i % 4);
    }
    destroy(h);
}
static void cappedMeter(void) {
    FDMConfig c = config(); c.beats = 9;
    Harness *h = create(c);
    advance(h, 168001, true);
    assert(h->eventCount == 8);
    for (unsigned i = 0; i < h->eventCount; ++i) {
        assert(h->events[i].config.beats == 7);
        assert(h->events[i].beat == i % 7);
        assert(h->events[i].number == i + 1);
    }
    destroy(h);
}
int main(void) {
    nextBeatAndBar(); finishCurrentSubdivision(); gapCountdown();
    editsDuringGap(); gapEditAtBar(); randomWholeBars();
    fractionalClock(); stalledUIAndRestart(); coalescedEdits(); concurrentControls(); barSequencePositions();
    cappedMeter();
    puts("Transport: 12 regression scenarios passed.");
    return 0;
}

