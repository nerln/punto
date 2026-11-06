#ifndef NATIVE_OUTPUT_BRIDGE_H
#define NATIVE_OUTPUT_BRIDGE_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Exact 16-byte SLSLinkDescription layout verified on macOS 27.2 arm64.
/// bitDepth is bits per channel; fullRange is 1 for full, 0 for limited.
/// transfer: 0=SDR, 2=HDR10. encoding: 0=RGB, 1=YCbCr444, 2=422, 3=420.
/// Preserve all four words verbatim when saving a mode for recovery.
typedef struct PNOutputMode {
    uint32_t bitDepth;
    uint32_t fullRange;
    uint32_t transfer;
    uint32_t encoding;
} PNOutputMode;

/// Runtime symbol availability only. It does not prove that the driver exposes
/// output-color controls for a particular display or macOS version.
bool PNOutputAPIAvailable(void);

/// Returns a raw CGError value. actualCount and selectedIndex are required.
/// A NULL buffer with capacity=0 queries count and selection without copying.
/// Otherwise capacity must be 1...4096; insufficient capacity returns
/// kCGErrorRangeCheck and reports the required count without a partial copy.
/// A successful selectedIndex always indexes the full returned mode list.
int32_t PNCopyAvailableOutputModes(uint32_t display, PNOutputMode *buffer,
                                 int32_t capacity, int32_t *actualCount,
                                 int32_t *selectedIndex);

/// Copies the actual selected connection-level description, not framebuffer
/// encoding or an inferred ColorElements capability. Returns a raw CGError.
int32_t PNCopyCurrentOutputMode(uint32_t display, PNOutputMode *out);

/// Adds an advertised color mode to the caller's open display transaction.
/// Only external, online, awake displays are accepted. This function does not
/// create/complete a transaction, change resolution, or choose a fallback.
/// The caller must arrange rollback and verify the selected mode afterward.
int32_t PNConfigureOutputMode(CGDisplayConfigRef config, uint32_t display,
                              PNOutputMode mode);

/// WindowServer's direct mode table includes modes filtered out by the public
/// CGDisplayCopyAllDisplayModes API. pixelWidth/Height describe the backing
/// image, not the cable timing. A listed hidden mode can still be rejected by
/// the display driver when the caller completes its transaction.
typedef struct PNDirectMode {
    int32_t modeIndex;
    uint32_t flags;
    uint32_t width;
    uint32_t height;
    uint32_t pixelWidth;
    uint32_t pixelHeight;
    double refreshRate;
    float density;
} PNDirectMode;

/// Returns raw CGError. actualCount is required. NULL buffer and capacity=0
/// queries required capacity. Bounds are 0...4096; a short nonzero buffer
/// returns kCGErrorRangeCheck and required count without copying partial data.
/// Includes invalid/duplicate entries so callers can inspect the complete table.
int32_t PNCopyDirectModes(uint32_t display, PNDirectMode *buffer,
                         int32_t capacity, int32_t *actualCount);

/// Reads the selected private mode index and its logical/backing dimensions.
int32_t PNCopyCurrentDirectMode(uint32_t display, PNDirectMode *out);

/// Stages an existing, valid direct mode for an external, active, awake display.
/// Validates index plus every expected field against a fresh table description.
/// No new mode is generated and no transaction is completed here. Hidden flags
/// do not prove driver acceptance: callers must complete, verify and recover.
int32_t PNConfigureDirectMode(CGDisplayConfigRef config, uint32_t display,
                              PNDirectMode expected);

#ifdef __cplusplus
}
#endif

#endif
