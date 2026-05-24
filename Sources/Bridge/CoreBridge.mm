// CoreBridge.mm
// Objective-C++ shim that loads a Libretro core via dlopen, wires its retro_*
// entry points to our Swift-facing C API, negotiates pixel format / paths /
// logging, and converts video frames to BGRA8 for Metal.
//
// Each retro_* function pointer is resolved once at load time; the per-frame
// hot path is just `g_retro_run()` and (when needed) a 16→32 bit pixel walk.

#import "CoreBridge.h"
#import "libretro_types.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <atomic>
#import <vector>
#import <cstdarg>

// ---------------------------------------------------------------------------
// Libretro function pointer typedefs (subset used here)
// ---------------------------------------------------------------------------
typedef void    (*retro_init_t)(void);
typedef void    (*retro_deinit_t)(void);
typedef bool    (*retro_load_game_t)(const struct retro_game_info*);
typedef void    (*retro_unload_game_t)(void);
typedef void    (*retro_run_t)(void);
typedef void    (*retro_reset_t)(void);
typedef size_t  (*retro_serialize_size_t)(void);
typedef bool    (*retro_serialize_t)(void*, size_t);
typedef bool    (*retro_unserialize_t)(const void*, size_t);
typedef void    (*retro_set_video_refresh_t)(retro_video_refresh_t);
typedef void    (*retro_set_input_poll_t)(retro_input_poll_t);
typedef void    (*retro_set_input_state_t)(retro_input_state_t);
typedef void    (*retro_set_audio_sample_t)(retro_audio_sample_t);
typedef void    (*retro_set_audio_sample_batch_t)(retro_audio_sample_batch_t);
typedef void    (*retro_set_environment_t)(retro_environment_t);
typedef void    (*retro_get_system_av_info_t)(struct retro_system_av_info*);
typedef void    (*retro_get_system_info_t)(struct retro_system_info*);

// ---------------------------------------------------------------------------
// Global state
// ---------------------------------------------------------------------------
namespace {
    void*  g_core_handle  = nullptr;

    retro_init_t                   g_retro_init               = nullptr;
    retro_deinit_t                 g_retro_deinit             = nullptr;
    retro_load_game_t              g_retro_load_game          = nullptr;
    retro_unload_game_t            g_retro_unload_game        = nullptr;
    retro_run_t                    g_retro_run                = nullptr;
    retro_reset_t                  g_retro_reset              = nullptr;
    retro_serialize_size_t         g_retro_serialize_size     = nullptr;
    retro_serialize_t              g_retro_serialize          = nullptr;
    retro_unserialize_t            g_retro_unserialize        = nullptr;
    retro_get_system_av_info_t     g_retro_get_system_av_info = nullptr;

    // Input state pushed in by Swift on every gamepad event.
    std::atomic<uint32_t> g_button_mask{0};
    float g_analog[2][2] = {{0,0},{0,0}};  // [stick][axis]

    // App-level callbacks
    RNVideoCallback  g_video_cb   = nullptr;
    void*            g_video_ud   = nullptr;
    RNAudioCallback  g_audio_cb   = nullptr;
    void*            g_audio_ud   = nullptr;

    // Pixel format the core asked us to use (defaults to libretro's legacy default).
    int g_pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;

    // BGRA8 staging buffer used when the core delivers 16-bit frames.
    std::vector<uint32_t> g_pixel_conv_buf;

    // AV info captured after retro_load_game succeeds.
    double   g_sample_rate = 0.0;
    double   g_fps         = 0.0;
    unsigned g_base_width  = 0;
    unsigned g_base_height = 0;

    // Cached system / save directories returned to the core. NSString-backed
    // so the C strings we hand back stay valid for the core's lifetime.
    NSString* g_system_dir = nil;
    NSString* g_save_dir   = nil;
}

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

static NSString* documentsSubdir(NSString* sub) {
    NSString* docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString* full = sub.length ? [docs stringByAppendingPathComponent:sub] : docs;
    [NSFileManager.defaultManager createDirectoryAtPath:full
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    return full;
}

/// Reset every dlsym'd function pointer + cached state. Must run after any
/// dlclose so we never call into unmapped pages — that exact race produced the
/// EXC_BAD_ACCESS we saw at rn_core_stop after a failed load.
static void cleanup_core_state() {
    if (g_core_handle) {
        dlclose(g_core_handle);
        g_core_handle = nullptr;
    }
    g_retro_init               = nullptr;
    g_retro_deinit             = nullptr;
    g_retro_load_game          = nullptr;
    g_retro_unload_game        = nullptr;
    g_retro_run                = nullptr;
    g_retro_reset              = nullptr;
    g_retro_serialize_size     = nullptr;
    g_retro_serialize          = nullptr;
    g_retro_unserialize        = nullptr;
    g_retro_get_system_av_info = nullptr;

    g_pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
    g_pixel_conv_buf.clear();
    g_sample_rate = 0.0;
    g_fps         = 0.0;
    g_base_width  = 0;
    g_base_height = 0;

    g_system_dir = nil;
    g_save_dir   = nil;
}

/// Resolve a libretro core bundled with the app. Tries (in order):
///   1. Bundle/Frameworks/<name>.framework/<name>  ← App-Store-legal wrapper
///   2. Bundle/Cores/<name>.dylib                   ← preserved-folder (dev)
///   3. Bundle/<name>.dylib                         ← flattened resource (dev)
///   4. Bundle/Frameworks/<name>.dylib              ← loose dylib (dev)
///
/// App Store review forbids standalone .dylib files anywhere in the bundle
/// (error 90171), so release builds ship each core wrapped in a .framework
/// inside Frameworks/. The framework directory and the Mach-O inside it are
/// both named after the dylib minus its extension, e.g.
/// snes9x_libretro_ios.framework/snes9x_libretro_ios. dlopen()'ing that binary
/// by absolute path behaves exactly like dlopen()'ing the loose dylib did.
/// The loose-dylib paths are kept as fallbacks for local/simulator builds.
static NSString* findCoreDylib(NSString* coreFileName) {
    NSBundle* bundle = NSBundle.mainBundle;
    NSString* base = [coreFileName stringByDeletingPathExtension];
    NSString* frameworkBinary =
        [[base stringByAppendingPathExtension:@"framework"]
            stringByAppendingPathComponent:base];
    NSArray<NSString*>* candidates = @[
        [bundle.privateFrameworksPath stringByAppendingPathComponent:frameworkBinary],
        [bundle.resourcePath stringByAppendingPathComponent:
            [@"Cores" stringByAppendingPathComponent:coreFileName]],
        [bundle.resourcePath stringByAppendingPathComponent:coreFileName],
        [bundle.privateFrameworksPath stringByAppendingPathComponent:coreFileName],
    ];
    for (NSString* p in candidates) {
        if (p.length && [NSFileManager.defaultManager fileExistsAtPath:p]) {
            return p;
        }
    }
    return nil;
}

// ---------------------------------------------------------------------------
// Pixel format conversion: 16-bit (RGB565 / 0RGB1555) → BGRA8 (Metal-ready)
// ---------------------------------------------------------------------------

static inline uint32_t convert_rgb565(uint16_t p) {
    uint8_t r = (uint8_t)(((p >> 11) & 0x1F) * 255 / 31);
    uint8_t g = (uint8_t)(((p >> 5)  & 0x3F) * 255 / 63);
    uint8_t b = (uint8_t)(( p        & 0x1F) * 255 / 31);
    // Memory order on little-endian: B, G, R, A → matches MTLPixelFormatBGRA8Unorm
    return (uint32_t)(0xFFu << 24) | ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
}

static inline uint32_t convert_0rgb1555(uint16_t p) {
    uint8_t r = (uint8_t)(((p >> 10) & 0x1F) * 255 / 31);
    uint8_t g = (uint8_t)(((p >> 5)  & 0x1F) * 255 / 31);
    uint8_t b = (uint8_t)(( p        & 0x1F) * 255 / 31);
    return (uint32_t)(0xFFu << 24) | ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
}

// ---------------------------------------------------------------------------
// Libretro → CoreBridge callbacks (registered with the core)
// ---------------------------------------------------------------------------

static void libretro_video_refresh(const void* data, unsigned width,
                                   unsigned height, size_t pitch) {
    if (!g_video_cb || !data || width == 0 || height == 0) return;

    if (g_pixel_format == RETRO_PIXEL_FORMAT_XRGB8888) {
        // 32-bit XRGB on little-endian = B,G,R,X bytes = matches BGRA8Unorm.
        // The Metal renderer assumes tightly-packed `width*4` bytes per row,
        // so re-pack if pitch indicates row padding.
        if (pitch == (size_t)width * 4) {
            RNPixelBuffer frame { data, (int)width, (int)height, pitch };
            g_video_cb(&frame, g_video_ud);
            return;
        }
        const size_t total = (size_t)width * height;
        if (g_pixel_conv_buf.size() < total) g_pixel_conv_buf.resize(total);
        const uint8_t* src = (const uint8_t*)data;
        for (unsigned y = 0; y < height; ++y) {
            memcpy(g_pixel_conv_buf.data() + (size_t)y * width,
                   src + y * pitch, (size_t)width * 4);
        }
        RNPixelBuffer frame {
            g_pixel_conv_buf.data(),
            (int)width, (int)height,
            (size_t)width * 4
        };
        g_video_cb(&frame, g_video_ud);
        return;
    }

    // 16-bit formats — convert per-pixel.
    const size_t total = (size_t)width * height;
    if (g_pixel_conv_buf.size() < total) g_pixel_conv_buf.resize(total);

    const uint8_t* src_bytes = (const uint8_t*)data;
    uint32_t*      dst       = g_pixel_conv_buf.data();
    const bool     is_565    = (g_pixel_format == RETRO_PIXEL_FORMAT_RGB565);

    for (unsigned y = 0; y < height; ++y) {
        const uint16_t* row = (const uint16_t*)(src_bytes + y * pitch);
        uint32_t*       out = dst + (size_t)y * width;
        if (is_565) {
            for (unsigned x = 0; x < width; ++x) out[x] = convert_rgb565(row[x]);
        } else {
            for (unsigned x = 0; x < width; ++x) out[x] = convert_0rgb1555(row[x]);
        }
    }

    RNPixelBuffer frame {
        g_pixel_conv_buf.data(),
        (int)width, (int)height,
        (size_t)width * 4
    };
    g_video_cb(&frame, g_video_ud);
}

static void libretro_input_poll(void) {
    // Input is pushed via rn_input_set_buttons; nothing to poll here.
}

// Standard libretro JOYPAD IDs — DO NOT renumber. The mapping below converts
// libretro's logical buttons (B/Y/Select/Start/Dpad/A/X/L/R) to our internal
// RNButtonMask, which the on-screen pad and physical controllers feed into.
//
// SNES face-button convention used by REmu's PlayStation-style overlay:
//   Cross (✕ / bottom)  → libretro B  (id 0)
//   Square (□ / left)   → libretro Y  (id 1)
//   Circle (○ / right)  → libretro A  (id 8)
//   Triangle (△ / top)  → libretro X  (id 9)
static int16_t libretro_input_state(unsigned port, unsigned device,
                                    unsigned index, unsigned id) {
    if (port != 0) return 0;

    if (device == RETRO_DEVICE_JOYPAD) {
        const uint32_t mask = g_button_mask.load(std::memory_order_relaxed);
        switch (id) {
            case 0:  return (mask & RN_BTN_CROSS)    ? 1 : 0;  // B
            case 1:  return (mask & RN_BTN_SQUARE)   ? 1 : 0;  // Y
            case 2:  return (mask & RN_BTN_SELECT)   ? 1 : 0;  // Select
            case 3:  return (mask & RN_BTN_START)    ? 1 : 0;  // Start
            case 4:  return (mask & RN_BTN_DPAD_UP)  ? 1 : 0;
            case 5:  return (mask & RN_BTN_DPAD_DN)  ? 1 : 0;
            case 6:  return (mask & RN_BTN_DPAD_LT)  ? 1 : 0;
            case 7:  return (mask & RN_BTN_DPAD_RT)  ? 1 : 0;
            case 8:  return (mask & RN_BTN_CIRCLE)   ? 1 : 0;  // A
            case 9:  return (mask & RN_BTN_TRIANGLE) ? 1 : 0;  // X
            case 10: return (mask & RN_BTN_L1)       ? 1 : 0;  // L
            case 11: return (mask & RN_BTN_R1)       ? 1 : 0;  // R
            case 12: return (mask & RN_BTN_L2)       ? 1 : 0;
            case 13: return (mask & RN_BTN_R2)       ? 1 : 0;
            default: return 0;
        }
    }

    if (device == RETRO_DEVICE_ANALOG && index < 2 && id < 2) {
        return (int16_t)(g_analog[index][id] * 32767.0f);
    }
    return 0;
}

static size_t libretro_audio_batch(const int16_t* data, size_t frames) {
    if (g_audio_cb && data && frames) g_audio_cb(data, frames, g_audio_ud);
    return frames;
}

static void libretro_audio_sample(int16_t left, int16_t right) {
    // Single-sample callback fallback. Most modern cores (snes9x included)
    // use the batch path, but a few still call this — funnel into the same
    // app-level callback with frame_count = 1.
    if (!g_audio_cb) return;
    int16_t pair[2] = { left, right };
    g_audio_cb(pair, 1, g_audio_ud);
}

// ---------------------------------------------------------------------------
// Logging — give the core a printf channel so its diagnostics land in NSLog.
// ---------------------------------------------------------------------------

static void libretro_log_printf(enum retro_log_level level, const char* fmt, ...) {
    char buffer[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);

    const char* tag = "INFO";
    switch (level) {
        case RETRO_LOG_DEBUG: tag = "DEBUG"; break;
        case RETRO_LOG_WARN:  tag = "WARN";  break;
        case RETRO_LOG_ERROR: tag = "ERROR"; break;
        default: break;
    }
    NSLog(@"[Core/%s] %s", tag, buffer);
}

// ---------------------------------------------------------------------------
// Environment dispatcher — the core asks us for capabilities / paths via this
// single callback. Returning false signals "frontend doesn't support X" and
// gives the core a chance to fall back.
// ---------------------------------------------------------------------------

static bool libretro_environment(unsigned cmd, void* data) {
    switch (cmd) {
        case RETRO_ENVIRONMENT_GET_CAN_DUPE: {
            // Yes — re-using the previous frame is fine when the core skips
            // a video update. Our renderer is happy to redraw the cached
            // texture in that case.
            if (data) *(bool*)data = true;
            return true;
        }

        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
            if (!data) return false;
            const enum retro_pixel_format fmt = *(const enum retro_pixel_format*)data;
            if (fmt == RETRO_PIXEL_FORMAT_0RGB1555 ||
                fmt == RETRO_PIXEL_FORMAT_XRGB8888 ||
                fmt == RETRO_PIXEL_FORMAT_RGB565) {
                g_pixel_format = (int)fmt;
                NSLog(@"[CoreBridge] Pixel format set to %d", g_pixel_format);
                return true;
            }
            return false;
        }

        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
            if (!data) return false;
            *(const char**)data = g_system_dir.UTF8String;
            return true;
        }

        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
            if (!data) return false;
            *(const char**)data = g_save_dir.UTF8String;
            return true;
        }

        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
            if (!data) return false;
            ((struct retro_log_callback*)data)->log = libretro_log_printf;
            return true;
        }

        case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
            // We could return a packed bitmask in libretro_input_state, but
            // for now answer "not supported" so the core falls back to the
            // per-id query loop. Cheap enough at SNES rates.
            return false;

        case RETRO_ENVIRONMENT_GET_VARIABLE:
        case RETRO_ENVIRONMENT_SET_VARIABLES:
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
            // No core options UI yet — the core will use its built-in defaults.
            return false;

        default:
            return false;
    }
}

// ---------------------------------------------------------------------------
// Symbol loading helper
// ---------------------------------------------------------------------------

template<typename T>
static bool load_sym(void* handle, const char* name, T& out, bool required = true) {
    out = reinterpret_cast<T>(dlsym(handle, name));
    if (!out && required) {
        NSLog(@"[CoreBridge] Missing required symbol: %s", name);
        return false;
    }
    return out != nullptr || !required;
}

// ---------------------------------------------------------------------------
// Public C API implementation
// ---------------------------------------------------------------------------

bool rn_core_load(const char* core_id, const char* rom_path) {
    if (g_core_handle) {
        NSLog(@"[CoreBridge] rn_core_load called while another core is loaded; "
              @"call rn_core_stop first");
        return false;
    }
    if (!core_id || !rom_path) return false;

    // ── Locate the dylib in the bundle ────────────────────────────────
    NSString* coreFile = [NSString stringWithFormat:@"%s_libretro_ios.dylib", core_id];
    NSString* corePath = findCoreDylib(coreFile);
    if (!corePath) {
        NSLog(@"[CoreBridge] Core dylib not found in bundle: %@", coreFile);
        return false;
    }
    NSLog(@"[CoreBridge] Loading core: %@", corePath);

    g_core_handle = dlopen(corePath.UTF8String, RTLD_LAZY | RTLD_LOCAL);
    if (!g_core_handle) {
        NSLog(@"[CoreBridge] dlopen failed: %s", dlerror());
        return false;
    }

    // ── Resolve required entry points ─────────────────────────────────
    bool ok = true;
    ok &= load_sym(g_core_handle, "retro_init",                  g_retro_init);
    ok &= load_sym(g_core_handle, "retro_deinit",                g_retro_deinit);
    ok &= load_sym(g_core_handle, "retro_load_game",             g_retro_load_game);
    ok &= load_sym(g_core_handle, "retro_unload_game",           g_retro_unload_game);
    ok &= load_sym(g_core_handle, "retro_run",                   g_retro_run);
    ok &= load_sym(g_core_handle, "retro_get_system_av_info",    g_retro_get_system_av_info);
    if (!ok) { cleanup_core_state(); return false; }

    // Optional entry points (all cores have these in practice but be safe).
    load_sym(g_core_handle, "retro_reset",          g_retro_reset,          /*required=*/false);
    load_sym(g_core_handle, "retro_serialize_size", g_retro_serialize_size, false);
    load_sym(g_core_handle, "retro_serialize",      g_retro_serialize,      false);
    load_sym(g_core_handle, "retro_unserialize",    g_retro_unserialize,    false);

    // ── Probe static info BEFORE retro_init. need_fullpath decides whether
    //    we hand the core a memory buffer or just the path. Many ROM-load
    //    failures we hit on iOS turned out to be "we passed both path AND
    //    data, the core only wanted one" — the correct protocol is to obey
    //    the flag the core itself reports here.
    retro_get_system_info_t  get_sys_info = nullptr;
    load_sym(g_core_handle, "retro_get_system_info", get_sys_info, false);

    struct retro_system_info sys_info{};
    if (get_sys_info) {
        get_sys_info(&sys_info);
        NSLog(@"[CoreBridge] Core info: name=%s version=%s exts=%s need_fullpath=%d block_extract=%d",
              sys_info.library_name      ? sys_info.library_name      : "(null)",
              sys_info.library_version   ? sys_info.library_version   : "(null)",
              sys_info.valid_extensions  ? sys_info.valid_extensions  : "(null)",
              sys_info.need_fullpath ? 1 : 0,
              sys_info.block_extract ? 1 : 0);
    } else {
        NSLog(@"[CoreBridge] retro_get_system_info missing — assuming need_fullpath=false");
    }

    // ── Register callbacks (env BEFORE init: the core may probe pixel format /
    //    paths during retro_init, so it must already have our env handler) ──
    retro_set_environment_t        set_env        = nullptr;
    retro_set_video_refresh_t      set_video      = nullptr;
    retro_set_input_poll_t         set_input_poll = nullptr;
    retro_set_input_state_t        set_input_st   = nullptr;
    retro_set_audio_sample_t       set_audio_smp  = nullptr;
    retro_set_audio_sample_batch_t set_audio_batch= nullptr;

    load_sym(g_core_handle, "retro_set_environment",        set_env,         false);
    load_sym(g_core_handle, "retro_set_video_refresh",      set_video,       false);
    load_sym(g_core_handle, "retro_set_input_poll",         set_input_poll,  false);
    load_sym(g_core_handle, "retro_set_input_state",        set_input_st,    false);
    load_sym(g_core_handle, "retro_set_audio_sample",       set_audio_smp,   false);
    load_sym(g_core_handle, "retro_set_audio_sample_batch", set_audio_batch, false);

    // Prepare directories before the core asks for them.
    g_system_dir = documentsSubdir(@"system");
    g_save_dir   = documentsSubdir(@"saves");

    if (set_env)         set_env(libretro_environment);
    if (set_video)       set_video(libretro_video_refresh);
    if (set_input_poll)  set_input_poll(libretro_input_poll);
    if (set_input_st)    set_input_st(libretro_input_state);
    if (set_audio_smp)   set_audio_smp(libretro_audio_sample);
    if (set_audio_batch) set_audio_batch(libretro_audio_batch);

    // ── Initialize the core ───────────────────────────────────────────
    g_retro_init();

    // ── Build retro_game_info per the core's need_fullpath contract ──
    struct retro_game_info info{};
    info.path = rom_path;
    info.meta = nullptr;

    // Keep this NSData alive for the entire retro_load_game call: ARC
    // on the local strong ref guarantees the buffer outlives the C call.
    NSData* romData = nil;

    if (!sys_info.need_fullpath) {
        NSError* err = nil;
        romData = [NSData dataWithContentsOfFile:@(rom_path)
                                         options:NSDataReadingMappedIfSafe
                                           error:&err];
        if (!romData) {
            NSLog(@"[CoreBridge] Could not read ROM file: %s — %@",
                  rom_path, err ?: @"(no error)");
            g_retro_deinit();
            cleanup_core_state();
            return false;
        }
        info.data = romData.bytes;
        info.size = romData.length;

        // Fingerprint the first 8 bytes so a corrupt / 0-byte file is obvious
        // in the log without dumping anything ROM-identifying.
        const uint8_t* head = (const uint8_t*)romData.bytes;
        NSLog(@"[CoreBridge] ROM ready: %zu bytes, head=%02x %02x %02x %02x %02x %02x %02x %02x",
              (size_t)romData.length,
              head[0], head[1], head[2], head[3],
              head[4], head[5], head[6], head[7]);
    } else {
        NSLog(@"[CoreBridge] Core wants full path; not reading ROM into memory");
    }

    NSLog(@"[CoreBridge] Calling retro_load_game(path=%s, data=%p, size=%zu)",
          info.path ? info.path : "(null)", info.data, info.size);

    if (!g_retro_load_game(&info)) {
        NSLog(@"[CoreBridge] retro_load_game returned false. "
              @"Core's own log lines (if any) appear above tagged [Core/...].");
        g_retro_deinit();
        cleanup_core_state();
        return false;
    }

    // ── Pull AV info so AudioEngine + display link can match the core ──
    struct retro_system_av_info av {};
    g_retro_get_system_av_info(&av);
    g_sample_rate = av.timing.sample_rate;
    g_fps         = av.timing.fps;
    g_base_width  = av.geometry.base_width;
    g_base_height = av.geometry.base_height;

    NSLog(@"[CoreBridge] Core '%s' loaded — %ux%u @ %.4f fps / %.1f Hz audio / pixfmt=%d",
          core_id, g_base_width, g_base_height,
          g_fps, g_sample_rate, g_pixel_format);

    return true;
}

void rn_core_start(void) {
    // CADisplayLink in MetalGameViewController drives the pacing.
}

void rn_core_stop(void) {
    // Tear down ONLY if a core is actually loaded. Calling these through
    // dangling pointers is what produced the EXC_BAD_ACCESS we hit when the
    // user backed out of a game whose load had failed.
    if (g_core_handle) {
        if (g_retro_unload_game) g_retro_unload_game();
        if (g_retro_deinit)      g_retro_deinit();
    }
    cleanup_core_state();
}

void rn_core_reset(void) {
    if (g_retro_reset) g_retro_reset();
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

double  rn_audio_sample_rate(void) { return g_sample_rate; }
double  rn_video_fps(void)         { return g_fps; }
int     rn_video_base_width(void)  { return (int)g_base_width; }
int     rn_video_base_height(void) { return (int)g_base_height; }
