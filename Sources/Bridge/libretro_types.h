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
// System / AV info (returned by retro_get_system_av_info)
// ---------------------------------------------------------------------------

struct retro_system_timing {
    double fps;          // e.g. SNES ≈ 60.0988
    double sample_rate;  // e.g. SNES ≈ 32040.0
};

struct retro_game_geometry {
    unsigned base_width;
    unsigned base_height;
    unsigned max_width;
    unsigned max_height;
    float    aspect_ratio;
};

struct retro_system_av_info {
    struct retro_game_geometry geometry;
    struct retro_system_timing timing;
};

// ---------------------------------------------------------------------------
// Static system info (returned by retro_get_system_info — safe to call before
// retro_init). `need_fullpath` decides whether we hand the core a path or a
// memory buffer in retro_load_game.
// ---------------------------------------------------------------------------

struct retro_system_info {
    const char* library_name;
    const char* library_version;
    const char* valid_extensions;
    bool        need_fullpath;
    bool        block_extract;
};

// ---------------------------------------------------------------------------
// Pixel formats (RETRO_PIXEL_FORMAT_*) — what cores ask the frontend to use
// via RETRO_ENVIRONMENT_SET_PIXEL_FORMAT (cmd 10)
// ---------------------------------------------------------------------------

enum retro_pixel_format {
    RETRO_PIXEL_FORMAT_0RGB1555 = 0,  // legacy default
    RETRO_PIXEL_FORMAT_XRGB8888 = 1,  // 32-bit, X in MSB → BGRA byte order on LE
    RETRO_PIXEL_FORMAT_RGB565   = 2,  // SNES9x default
    RETRO_PIXEL_FORMAT_UNKNOWN  = 0xFFFF
};

// ---------------------------------------------------------------------------
// Logging interface (RETRO_ENVIRONMENT_GET_LOG_INTERFACE → struct retro_log_callback)
// ---------------------------------------------------------------------------

enum retro_log_level {
    RETRO_LOG_DEBUG = 0,
    RETRO_LOG_INFO  = 1,
    RETRO_LOG_WARN  = 2,
    RETRO_LOG_ERROR = 3
};

typedef void (*retro_log_printf_t)(enum retro_log_level level,
                                   const char* fmt, ...);

struct retro_log_callback {
    retro_log_printf_t log;
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

#define RETRO_ENVIRONMENT_GET_CAN_DUPE          3
#define RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY  9
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT      10
#define RETRO_ENVIRONMENT_GET_VARIABLE          15
#define RETRO_ENVIRONMENT_SET_VARIABLES         16
#define RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE   17
#define RETRO_ENVIRONMENT_GET_LOG_INTERFACE     27
#define RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY    31
#define RETRO_ENVIRONMENT_GET_INPUT_BITMASKS    51
#define RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE 47

#ifdef __cplusplus
}
#endif
