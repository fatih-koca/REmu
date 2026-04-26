// CoreBridge.mm
// Objective-C++ skeleton bridging Swift ↔ Libretro C++ cores.
// Replace the "STUB:" sections with actual dylib loading and retro_* calls.

#import "CoreBridge.h"
#import "libretro_types.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <atomic>

// ---------------------------------------------------------------------------
// Libretro function pointer typedefs (subset used here)
// ---------------------------------------------------------------------------
typedef void    (*retro_init_t)(void);
typedef void    (*retro_deinit_t)(void);
typedef bool    (*retro_load_game_t)(const struct retro_game_info*);
typedef void    (*retro_unload_game_t)(void);
typedef void    (*retro_run_t)(void);
typedef size_t  (*retro_serialize_size_t)(void);
typedef bool    (*retro_serialize_t)(void*, size_t);
typedef bool    (*retro_unserialize_t)(const void*, size_t);
typedef void    (*retro_set_video_refresh_t)(retro_video_refresh_t);
typedef void    (*retro_set_input_poll_t)(retro_input_poll_t);
typedef void    (*retro_set_input_state_t)(retro_input_state_t);
typedef void    (*retro_set_audio_sample_batch_t)(retro_audio_sample_batch_t);
typedef void    (*retro_set_environment_t)(retro_environment_t);

// ---------------------------------------------------------------------------
// Global state
// ---------------------------------------------------------------------------
namespace {
    void*  g_core_handle  = nullptr;
    retro_init_t              g_retro_init              = nullptr;
    retro_deinit_t            g_retro_deinit            = nullptr;
    retro_load_game_t         g_retro_load_game         = nullptr;
    retro_unload_game_t       g_retro_unload_game       = nullptr;
    retro_run_t               g_retro_run               = nullptr;
    retro_serialize_size_t    g_retro_serialize_size    = nullptr;
    retro_serialize_t         g_retro_serialize         = nullptr;
    retro_unserialize_t       g_retro_unserialize       = nullptr;

    // Input state
    std::atomic<uint32_t> g_button_mask{0};
    float g_analog[2][2] = {{0,0},{0,0}};  // [stick][axis]

    // App-level callbacks
    RNVideoCallback  g_video_cb   = nullptr;
    void*            g_video_ud   = nullptr;
    RNAudioCallback  g_audio_cb   = nullptr;
    void*            g_audio_ud   = nullptr;
}

// ---------------------------------------------------------------------------
// Libretro → CoreBridge callbacks (registered with the core)
// ---------------------------------------------------------------------------

static void libretro_video_refresh(const void* data, unsigned width, unsigned height, size_t pitch) {
    if (!g_video_cb || !data) return;
    RNPixelBuffer frame { data, (int)width, (int)height, pitch };
    g_video_cb(&frame, g_video_ud);
}

static void libretro_input_poll(void) {
    // Input is pushed via rn_input_set_buttons; nothing to poll here.
}

static int16_t libretro_input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port != 0) return 0;
    // RETRO_DEVICE_JOYPAD buttons
    if (device == 1 /* RETRO_DEVICE_JOYPAD */) {
        // Map Libretro button IDs to our bitmask
        static const uint32_t id_to_mask[] = {
            RN_BTN_DPAD_UP,  // RETRO_DEVICE_ID_JOYPAD_UP    = 4 → remap below
        };
        // Simple direct bit mapping for common IDs:
        switch (id) {
            case 0:  return (g_button_mask & RN_BTN_DPAD_DN) ? 1 : 0;   // B / Cross
            case 1:  return (g_button_mask & RN_BTN_CIRCLE)  ? 1 : 0;   // Y / Circle
            case 2:  return (g_button_mask & RN_BTN_SELECT)  ? 1 : 0;
            case 3:  return (g_button_mask & RN_BTN_START)   ? 1 : 0;
            case 4:  return (g_button_mask & RN_BTN_DPAD_UP) ? 1 : 0;
            case 5:  return (g_button_mask & RN_BTN_DPAD_DN) ? 1 : 0;
            case 6:  return (g_button_mask & RN_BTN_DPAD_LT) ? 1 : 0;
            case 7:  return (g_button_mask & RN_BTN_DPAD_RT) ? 1 : 0;
            case 8:  return (g_button_mask & RN_BTN_SQUARE)  ? 1 : 0;   // A
            case 9:  return (g_button_mask & RN_BTN_TRIANGLE)? 1 : 0;   // X
            case 10: return (g_button_mask & RN_BTN_L1)      ? 1 : 0;
            case 11: return (g_button_mask & RN_BTN_R1)      ? 1 : 0;
            case 12: return (g_button_mask & RN_BTN_L2)      ? 1 : 0;
            case 13: return (g_button_mask & RN_BTN_R2)      ? 1 : 0;
        }
    }
    if (device == 5 /* RETRO_DEVICE_ANALOG */ && index < 2 && id < 2) {
        return (int16_t)(g_analog[index][id] * 32767.0f);
    }
    return 0;
}

static size_t libretro_audio_batch(const int16_t* data, size_t frames) {
    if (g_audio_cb) g_audio_cb(data, frames, g_audio_ud);
    return frames;
}

static bool libretro_environment(unsigned cmd, void* data) {
    // Minimal environment handler — expand as needed per core requirements
    switch (cmd) {
        case 3: // RETRO_ENVIRONMENT_GET_CAN_DUPE
            *(bool*)data = true;
            return true;
        case 27: // RETRO_ENVIRONMENT_GET_LOG_INTERFACE
            // TODO: wire up NSLog-based logger
            return false;
        default:
            return false;
    }
}

// ---------------------------------------------------------------------------
// Symbol loading helper
// ---------------------------------------------------------------------------

template<typename T>
static bool load_sym(void* handle, const char* name, T& out) {
    out = reinterpret_cast<T>(dlsym(handle, name));
    if (!out) {
        NSLog(@"[CoreBridge] Missing symbol: %s", name);
        return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Public C API implementation
// ---------------------------------------------------------------------------

bool rn_core_load(const char* core_id, const char* rom_path) {
    // STUB: Resolve .dylib path from bundle/Documents for the given core_id.
    // On a sideloaded or developer-signed app, cores live in the app bundle:
    //   e.g. "mednafen_psx_libretro_ios.dylib"
    NSString* coreName = [NSString stringWithFormat:@"%s_libretro_ios", core_id];
    NSString* corePath = [[NSBundle mainBundle] pathForResource:coreName ofType:@"dylib"];
    if (!corePath) {
        NSLog(@"[CoreBridge] Core not found: %@", coreName);
        return false;
    }

    g_core_handle = dlopen(corePath.UTF8String, RTLD_LAZY);
    if (!g_core_handle) {
        NSLog(@"[CoreBridge] dlopen failed: %s", dlerror());
        return false;
    }

    // Load symbols
    bool ok = true;
    ok &= load_sym(g_core_handle, "retro_init",           g_retro_init);
    ok &= load_sym(g_core_handle, "retro_deinit",         g_retro_deinit);
    ok &= load_sym(g_core_handle, "retro_load_game",      g_retro_load_game);
    ok &= load_sym(g_core_handle, "retro_unload_game",    g_retro_unload_game);
    ok &= load_sym(g_core_handle, "retro_run",            g_retro_run);
    ok &= load_sym(g_core_handle, "retro_serialize_size", g_retro_serialize_size);
    ok &= load_sym(g_core_handle, "retro_serialize",      g_retro_serialize);
    ok &= load_sym(g_core_handle, "retro_unserialize",    g_retro_unserialize);
    if (!ok) return false;

    // Register callbacks
    void (*set_video)(retro_video_refresh_t)      = nullptr;
    void (*set_input_poll)(retro_input_poll_t)    = nullptr;
    void (*set_input_state)(retro_input_state_t)  = nullptr;
    void (*set_audio)(retro_audio_sample_batch_t) = nullptr;
    void (*set_env)(retro_environment_t)          = nullptr;

    load_sym(g_core_handle, "retro_set_video_refresh",      set_video);
    load_sym(g_core_handle, "retro_set_input_poll",         set_input_poll);
    load_sym(g_core_handle, "retro_set_input_state",        set_input_state);
    load_sym(g_core_handle, "retro_set_audio_sample_batch", set_audio);
    load_sym(g_core_handle, "retro_set_environment",        set_env);

    if (set_env)         set_env(libretro_environment);
    if (set_video)       set_video(libretro_video_refresh);
    if (set_input_poll)  set_input_poll(libretro_input_poll);
    if (set_input_state) set_input_state(libretro_input_state);
    if (set_audio)       set_audio(libretro_audio_batch);

    g_retro_init();

    // Load ROM
    struct retro_game_info info { rom_path, nullptr, 0, nullptr };
    // For cores requiring full ROM data in memory (PS1 etc.):
    NSData* romData = [NSData dataWithContentsOfFile:@(rom_path)];
    if (romData) {
        info.data = romData.bytes;
        info.size = romData.length;
    }

    if (!g_retro_load_game(&info)) {
        NSLog(@"[CoreBridge] retro_load_game failed for: %s", rom_path);
        return false;
    }

    NSLog(@"[CoreBridge] Core '%s' loaded successfully", core_id);
    return true;
}

void rn_core_start(void) {
    // CADisplayLink / Timer is managed by MetalGameViewController.
    // Each tick calls rn_core_run_frame().
}

void rn_core_stop(void) {
    if (g_retro_unload_game) g_retro_unload_game();
    if (g_retro_deinit)      g_retro_deinit();
    if (g_core_handle)       dlclose(g_core_handle);
    g_core_handle = nullptr;
}

void rn_core_reset(void) {
    using retro_reset_t = void(*)(void);
    retro_reset_t fn = nullptr;
    if (g_core_handle) load_sym(g_core_handle, "retro_reset", fn);
    if (fn) fn();
}

void rn_core_run_frame(void) {
    if (g_retro_run) g_retro_run();
}

void rn_input_set_buttons(uint32_t mask) {
    g_button_mask.store(mask, std::memory_order_relaxed);
}

void rn_input_set_analog(int stick, float x, float y) {
    if (stick < 0 || stick > 1) return;
    g_analog[stick][0] = x;
    g_analog[stick][1] = y;
}

size_t rn_state_size(void) {
    return g_retro_serialize_size ? g_retro_serialize_size() : 0;
}

bool rn_state_save(void* buffer, size_t size) {
    return g_retro_serialize ? g_retro_serialize(buffer, size) : false;
}

bool rn_state_load(const void* buffer, size_t size) {
    return g_retro_unserialize ? g_retro_unserialize(buffer, size) : false;
}

void rn_set_video_callback(RNVideoCallback cb, void* ud) {
    g_video_cb = cb;
    g_video_ud = ud;
}

void rn_set_audio_callback(RNAudioCallback cb, void* ud) {
    g_audio_cb = cb;
    g_audio_ud = ud;
}
