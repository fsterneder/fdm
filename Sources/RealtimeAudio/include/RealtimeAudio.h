#ifndef FDM_REALTIME_AUDIO_H
#define FDM_REALTIME_AUDIO_H
#include <stdbool.h>
#include <stdint.h>

typedef struct FDMEngine FDMEngine;
typedef struct {
    uint32_t bpm, beats, subdivisions, voice;
    bool accent;
    int32_t gap;
    uint32_t gapBars;
} FDMConfig;
typedef struct {
    uint64_t epoch, hostTime, number;
    uint32_t beat, gapBarsRemaining;
    FDMConfig config;
} FDMBeatEvent;

/* Create/load/destroy on the control thread, before/after audio rendering. */
FDMEngine *FDMEngineCreate(double sampleRate, uint32_t randomSeed);
void FDMEngineDestroy(FDMEngine *engine);
bool FDMEngineSetVoice(FDMEngine *engine, uint32_t voice, uint32_t kind,
                       const float *samples, uint32_t count);

/* Lock-free control updates. Start/Stop are the only transport resets. */
void FDMEngineConfigure(FDMEngine *engine, FDMConfig config);
uint64_t FDMEngineStart(FDMEngine *engine);
void FDMEngineStop(FDMEngine *engine);

/* Audio thread only: no allocation, locking, Objective-C, or UI work. */
void FDMEngineRender(FDMEngine *engine, float *output, uint32_t frames,
                     uint64_t hostTime, double hostTicksPerFrame);

/* Single consumer, on the UI/control thread. */
bool FDMEnginePoll(FDMEngine *engine, FDMBeatEvent *event);
#endif

