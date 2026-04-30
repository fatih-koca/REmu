#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// ---------------------------------------------------------------------------
// Pixel buffer passed from core → Metal renderer
// ---------------------------------------------------------------------------
typedef struct {
    const void* data;     // BGRA8 pixel bytes
    int         width;
    int         height;
    size_t      pitch;    // bytes per row
} RNPixelBuffer;

// ---------------------------------------------------------------------------
// Input bitmask — mirrors Libretro retro_input_state_t device IDs
// ---------------------------------------------------------------------------
typedef enum : uint32_t {
    RN_BTN_CROSS    = 1 << 0,
    RN_BTN_CIRCLE   = 1 << 1,
    RN_BTN_SQUARE   = 1 << 2,
    RN_BTN_TRIANGLE = 1 << 3,
    RN_BTN_L1       = 1 << 4,
    RN_BTN_R1       = 1 << 5,
    RN_BTN_L2       = 1 << 6,
    RN_BTN_R2       = 1 << 7,
    RN_BTN_START    = 1 << 8,
    RN_BTN_SELECT   = 1 << 9,
    RN_BTN_DPAD_UP  = 1 << 10,
    RN_BTN_DPAD_DN  = 1 << 11,
    RN_BTN_DPAD_LT  = 1 << 12,
    RN_BTN_DPAD_RT  = 1 << 13,
} RNButtonMask;

// ---------------------------------------------------------------------------
// Core lifecycle
// ---------------------------------------------------------------------------
bool rn_core_load(const char* core_id, const char* rom_path);
void rn_core_start(void);
void rn_core_stop(void);
void rn_core_reset(void);

// ---------------------------------------------------------------------------
// Per-frame step (call from CADisplayLink callback)
// ---------------------------------------------------------------------------
void rn_core_run_frame(void);

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------
void rn_input_set_buttons(uint32_t button_mask);   // bitmask of RNButtonMask
void rn_input_set_analog(int stick, float x, float y); // stick: 0=left 1=right

// ---------------------------------------------------------------------------
// Save states (Libretro retro_serialize / retro_unserialize)
// ---------------------------------------------------------------------------
size_t  rn_state_size(void);
bool    rn_state_save(void* buffer, size_t size);
bool    rn_state_load(const void* buffer, size_t size);

// ---------------------------------------------------------------------------
// AV info — populated by retro_get_system_av_info after a successful load.
// Sample rate is forwarded to AVAudioEngine so we can match the core's native
// rate (SNES9x is 32040 Hz, GB/A 32768 Hz, etc.) instead of resampling blindly.
// ---------------------------------------------------------------------------
double  rn_audio_sample_rate(void);   // returns 0 before a core has loaded
double  rn_video_fps(void);           // e.g. 60.0988 for NTSC SNES
int     rn_video_base_width(void);
int     rn_video_base_height(void);

// ---------------------------------------------------------------------------
// Video frame callback registration
// ---------------------------------------------------------------------------
typedef void (*RNVideoCallback)(const RNPixelBuffer* frame, void* userdata);
void rn_set_video_callback(RNVideoCallback cb, void* userdata);

// ---------------------------------------------------------------------------
// Audio frame callback registration  (16-bit stereo interleaved)
// ---------------------------------------------------------------------------
typedef void (*RNAudioCallback)(const int16_t* samples, size_t frame_count, void* userdata);
void rn_set_audio_callback(RNAudioCallback cb, void* userdata);

#ifdef __cplusplus
}
#endif
