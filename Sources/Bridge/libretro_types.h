// Minimal subset of libretro.h — only the types CoreBridge.mm references.
// Full reference: https://github.com/libretro/libretro-common/blob/master/include/libretro.h
// License: MIT (© 2010-2024 The RetroArch team)

#pragma once

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Callback typedefs
// ---------------------------------------------------------------------------

typedef bool    (*retro_environment_t)(unsigned cmd, void* data);
typedef void    (*retro_video_refresh_t)(const void* data, unsigned width,
                                         unsigned height, size_t pitch);
typedef void    (*retro_audio_sample_t)(int16_t left, int16_t right);
typedef size_t  (*retro_audio_sample_batch_t)(const int16_t* data, size_t frames);
typedef void    (*retro_input_poll_t)(void);
typedef int16_t (*retro_input_state_t)(unsigned port, unsigned device,
                                       unsigned index, unsigned id);

// ---------------------------------------------------------------------------
// Game info struct (passed to retro_load_game)
// ---------------------------------------------------------------------------

struct retro_game_info {
    const char* path;
    const void* data;
    size_t      size;
    const char* meta;
};

// ---------------------------------------------------------------------------
// Device constants (RETRO_DEVICE_*)
// ---------------------------------------------------------------------------

#define RETRO_DEVICE_NONE     0
#define RETRO_DEVICE_JOYPAD   1
#define RETRO_DEVICE_MOUSE    2
#define RETRO_DEVICE_KEYBOARD 3
#define RETRO_DEVICE_LIGHTGUN 4
#define RETRO_DEVICE_ANALOG   5
#define RETRO_DEVICE_POINTER  6

// ---------------------------------------------------------------------------
// Environment commands (RETRO_ENVIRONMENT_*)
// ---------------------------------------------------------------------------

#define RETRO_ENVIRONMENT_GET_CAN_DUPE      3
#define RETRO_ENVIRONMENT_GET_LOG_INTERFACE 27

#ifdef __cplusplus
}
#endif
