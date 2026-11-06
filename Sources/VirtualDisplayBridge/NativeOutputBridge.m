#import "NativeOutputBridge.h"

#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <limits.h>
#import <math.h>
#import <stddef.h>
#import <stdlib.h>
#import <string.h>

// Optional PRIVATE SkyLight APIs. Signatures, 16-byte aggregate argument ABI,
// selection-index semantics, and field mapping were checked against complete
// macOS 27.2 arm64 disassembly before the read-only getters were exercised.
// WS::Displays::make_link_description(CADisplayMode const*) maps the imported
// kCADisplayRGBFullRange / RGBLimitedRange / YCbCr* constants into these fields.
// These descriptions control connection output; no mirroring, capture, virtual
// screen, CPU frame copies, or rendering pipeline is introduced here.

_Static_assert(sizeof(PNOutputMode) == 16, "SLSLinkDescription must be 16 bytes");
_Static_assert(offsetof(PNOutputMode, bitDepth) == 0, "Unexpected bitDepth offset");
_Static_assert(offsetof(PNOutputMode, fullRange) == 4, "Unexpected fullRange offset");
_Static_assert(offsetof(PNOutputMode, transfer) == 8, "Unexpected transfer offset");
_Static_assert(offsetof(PNOutputMode, encoding) == 12, "Unexpected encoding offset");

typedef CGError (*PNGetCurrentModeFn)(CGDirectDisplayID, uint32_t *);
typedef CGError (*PNGetOutputCountFn)(CGDirectDisplayID, int32_t, int32_t *);
typedef CGError (*PNGetOutputsFn)(CGDirectDisplayID, int32_t, PNOutputMode *,
                                  int32_t *, int32_t *);
typedef CGError (*PNConfigureOutputFn)(CGDisplayConfigRef, CGDirectDisplayID,
                                      PNOutputMode);
typedef CGError (*PNGetDirectCountFn)(CGDirectDisplayID, uint32_t *);
typedef CGError (*PNDescribeDirectFn)(CGDirectDisplayID, int32_t, void *, int32_t);
typedef CGError (*PNConfigureDirectFn)(CGDisplayConfigRef, CGDirectDisplayID,
                                      uint32_t);

static const int32_t PNMaximumOutputModes = 4096;
static void *gSkyLightHandle;
static PNGetCurrentModeFn gGetCurrentMode;
static PNGetOutputCountFn gGetOutputCount;
static PNGetOutputsFn gGetOutputs;
static PNConfigureOutputFn gConfigureOutput;
static PNGetDirectCountFn gGetDirectCount;
static PNDescribeDirectFn gDescribeDirect;
static PNConfigureDirectFn gConfigureDirect;

bool PNOutputAPIAvailable(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gSkyLightHandle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL);
        if (!gSkyLightHandle) return;
        gGetCurrentMode = (PNGetCurrentModeFn)dlsym(gSkyLightHandle, "SLSGetCurrentDisplayMode");
        gGetOutputCount = (PNGetOutputCountFn)dlsym(gSkyLightHandle, "SLSGetDisplayOutputModeCount");
        gGetOutputs = (PNGetOutputsFn)dlsym(gSkyLightHandle, "SLSGetDisplayOutputModeLinkDescriptions");
        gConfigureOutput = (PNConfigureOutputFn)dlsym(gSkyLightHandle, "SLSConfigureDisplayOutputMode");
        // The CGS aliases remain exported by SkyLight. Their argument layout
        // is corroborated by AllRez/displayplacer and macOS 27.2 disassembly.
        gGetDirectCount = (PNGetDirectCountFn)dlsym(gSkyLightHandle, "CGSGetNumberOfDisplayModes");
        gDescribeDirect = (PNDescribeDirectFn)dlsym(gSkyLightHandle, "CGSGetDisplayModeDescriptionOfLength");
        gConfigureDirect = (PNConfigureDirectFn)dlsym(gSkyLightHandle, "CGSConfigureDisplayMode");
        if (!gGetDirectCount) gGetDirectCount = (PNGetDirectCountFn)dlsym(gSkyLightHandle, "SLSGetNumberOfDisplayModes");
        if (!gDescribeDirect) gDescribeDirect = (PNDescribeDirectFn)dlsym(gSkyLightHandle, "SLSGetDisplayModeDescriptionOfLength");
        if (!gConfigureDirect) gConfigureDirect = (PNConfigureDirectFn)dlsym(gSkyLightHandle, "SLSConfigureDisplayMode");
        // The handle remains open for the lifetime of the cached function
        // pointers; closing it here could invalidate those pointers.
    });
    return gGetCurrentMode && gGetOutputCount && gGetOutputs && gConfigureOutput;
}

/// On success the caller owns *modes and must free it. All failure paths leave
/// the output pointer NULL. Always allocate the bounded maximum so a hotplug
/// between the count and list calls cannot overflow or truncate the buffer.
static CGError PNCopyModes(uint32_t display, PNOutputMode **modes,
                           int32_t *count, int32_t *selectedIndex) {
    *modes = NULL;
    *count = 0;
    *selectedIndex = -1;
    if (display == kCGNullDirectDisplay) return kCGErrorIllegalArgument;
    if (!PNOutputAPIAvailable()) return kCGErrorNotImplemented;
    // This public call also initializes the CoreGraphics display client before
    // the private getters read its cached WindowServer state.
    if (!CGDisplayIsOnline(display)) return kCGErrorInvalidOperation;

    uint32_t modeIndex = 0;
    CGError result = gGetCurrentMode(display, &modeIndex);
    if (result != kCGErrorSuccess) return result;
    if (modeIndex > INT32_MAX) return kCGErrorRangeCheck;

    int32_t advertised = 0;
    result = gGetOutputCount(display, (int32_t)modeIndex, &advertised);
    if (result != kCGErrorSuccess) return result;
    if (advertised < 0 || advertised > PNMaximumOutputModes) return kCGErrorRangeCheck;
    if (advertised == 0) return kCGErrorNoneAvailable;

    PNOutputMode *values = calloc((size_t)PNMaximumOutputModes, sizeof(PNOutputMode));
    if (!values) return kCGErrorCannotComplete;
    int32_t capacity = PNMaximumOutputModes;
    int32_t selected = -1;
    result = gGetOutputs(display, (int32_t)modeIndex, values, &capacity, &selected);
    if (result == kCGErrorSuccess &&
        (capacity <= 0 || capacity > PNMaximumOutputModes ||
         selected < 0 || selected >= capacity)) {
        result = kCGErrorRangeCheck;
    }
    // A resolution switch in another app invalidates the mode-index lookup.
    // Fail so callers refresh rather than applying stale output-color options.
    if (result == kCGErrorSuccess) {
        uint32_t finalModeIndex = 0;
        result = gGetCurrentMode(display, &finalModeIndex);
        if (result == kCGErrorSuccess && finalModeIndex != modeIndex) {
            result = kCGErrorInvalidOperation;
        }
    }
    if (result != kCGErrorSuccess) {
        free(values);
        return result;
    }
    *modes = values;
    *count = capacity;
    *selectedIndex = selected;
    return kCGErrorSuccess;
}

int32_t PNCopyAvailableOutputModes(uint32_t display, PNOutputMode *buffer,
                                 int32_t capacity, int32_t *actualCount,
                                 int32_t *selectedIndex) {
    if (actualCount) *actualCount = 0;
    if (selectedIndex) *selectedIndex = -1;
    if (!actualCount || !selectedIndex || capacity < 0 ||
        capacity > PNMaximumOutputModes || (capacity > 0 && !buffer)) {
        return kCGErrorIllegalArgument;
    }
    PNOutputMode *values = NULL;
    CGError result = PNCopyModes(display, &values, actualCount, selectedIndex);
    if (result != kCGErrorSuccess) return (int32_t)result;
    if (capacity == 0) {
        free(values);
        return kCGErrorSuccess;
    }
    if (capacity < *actualCount) {
        free(values);
        return kCGErrorRangeCheck;
    }
    memcpy(buffer, values, (size_t)*actualCount * sizeof(PNOutputMode));
    free(values);
    return kCGErrorSuccess;
}

int32_t PNCopyCurrentOutputMode(uint32_t display, PNOutputMode *out) {
    if (!out) return kCGErrorIllegalArgument;
    memset(out, 0, sizeof(*out));
    PNOutputMode *values = NULL;
    int32_t count = 0, selected = -1;
    CGError result = PNCopyModes(display, &values, &count, &selected);
    if (result != kCGErrorSuccess) return (int32_t)result;
    // PNCopyModes already checked that selected is inside the complete list.
    *out = values[selected];
    free(values);
    return kCGErrorSuccess;
}

int32_t PNConfigureOutputMode(CGDisplayConfigRef config, uint32_t display,
                              PNOutputMode mode) {
    if (!config || display == kCGNullDirectDisplay) return kCGErrorIllegalArgument;
    if (!CGDisplayIsOnline(display) || CGDisplayIsBuiltin(display) ||
        CGDisplayIsAsleep(display)) return kCGErrorInvalidOperation;
    PNOutputMode *values = NULL;
    int32_t count = 0, selected = -1;
    CGError result = PNCopyModes(display, &values, &count, &selected);
    if (result != kCGErrorSuccess) return (int32_t)result;
    bool advertised = false;
    for (int32_t i = 0; i < count; i++) {
        if (memcmp(&mode, &values[i], sizeof(PNOutputMode)) == 0) {
            advertised = true;
            break;
        }
    }
    free(values);
    if (!advertised) return kCGErrorIllegalArgument;
    // Do not call SLSSetDisplayOutputMode: it completes its own transaction
    // with a potentially persistent option. The caller owns session scope,
    // recovery deadlines, cancellation, completion and read-back verification.
    return (int32_t)gConfigureOutput(config, display, mode);
}

// The following path selects WindowServer-generated direct modes. It does not
// use CGVirtualDisplay or mirror another screen. Some modes carry 0x00200000
// (valid for mirroring) and are omitted by public CG mode enumeration; the flag
// itself does not guarantee that direct activation will succeed on every Mac.

static bool PNDirectAPIAvailable(void) {
    (void)PNOutputAPIAvailable(); // Initializes the shared library once.
    return gGetCurrentMode && gGetDirectCount && gDescribeDirect && gConfigureDirect;
}

static uint32_t PNRead32(const unsigned char *bytes, size_t offset) {
    uint32_t value = 0;
    memcpy(&value, bytes + offset, sizeof(value));
    return value;
}

static CGError PNDirectCount(uint32_t display, uint32_t *count) {
    *count = 0;
    if (display == kCGNullDirectDisplay) return kCGErrorIllegalArgument;
    if (!PNDirectAPIAvailable()) return kCGErrorNotImplemented;
    if (!CGDisplayIsOnline(display)) return kCGErrorInvalidOperation;
    CGError result = gGetDirectCount(display, count);
    if (result != kCGErrorSuccess) return result;
    if (*count > (uint32_t)PNMaximumOutputModes) return kCGErrorRangeCheck;
    if (*count == 0) return kCGErrorNoneAvailable;
    return kCGErrorSuccess;
}

static CGError PNDescribeDirectMode(uint32_t display, int32_t index,
                                    PNDirectMode *mode) {
    memset(mode, 0, sizeof(*mode));
    if (index < 0 || index >= PNMaximumOutputModes) return kCGErrorIllegalArgument;
    // CGSDisplayModeDescription is versioned by the requested byte length.
    // A generously sized, zeroed backing buffer avoids struct packing or
    // alignment assumptions. Known v0xd4 fields are copied at fixed offsets.
    unsigned char bytes[512] = {0};
    CGError result = gDescribeDirect(display, index, bytes, 0xd4);
    if (result != kCGErrorSuccess) return result;
    uint32_t reportedIndex = PNRead32(bytes, 0);
    if (reportedIndex > INT32_MAX || reportedIndex != (uint32_t)index) {
        return kCGErrorRangeCheck;
    }
    mode->modeIndex = (int32_t)reportedIndex;
    mode->flags = PNRead32(bytes, 4);
    mode->width = PNRead32(bytes, 8);
    mode->height = PNRead32(bytes, 12);
    mode->pixelWidth = PNRead32(bytes, 0xc8);
    mode->pixelHeight = PNRead32(bytes, 0xcc);
    mode->refreshRate = (double)PNRead32(bytes, 0xbc) / 65536.0;
    memcpy(&mode->density, bytes + 0xd0, sizeof(mode->density));
    if (!isfinite(mode->density) || mode->density <= 0 ||
        mode->density > 16 || mode->width == 0 || mode->height == 0 ||
        mode->pixelWidth == 0 || mode->pixelHeight == 0) {
        memset(mode, 0, sizeof(*mode));
        return kCGErrorRangeCheck;
    }
    return kCGErrorSuccess;
}

static bool PNDirectModeMatches(PNDirectMode actual, PNDirectMode expected) {
    return actual.modeIndex == expected.modeIndex && actual.flags == expected.flags &&
        actual.width == expected.width && actual.height == expected.height &&
        actual.pixelWidth == expected.pixelWidth && actual.pixelHeight == expected.pixelHeight &&
        isfinite(expected.refreshRate) && isfinite(expected.density) &&
        fabs(actual.refreshRate - expected.refreshRate) <= (1.0 / 65536.0) &&
        fabsf(actual.density - expected.density) <= 0.00001f;
}

int32_t PNCopyDirectModes(uint32_t display, PNDirectMode *buffer,
                         int32_t capacity, int32_t *actualCount) {
    if (actualCount) *actualCount = 0;
    if (!actualCount || capacity < 0 || capacity > PNMaximumOutputModes ||
        (capacity > 0 && !buffer)) return kCGErrorIllegalArgument;
    uint32_t count = 0;
    CGError result = PNDirectCount(display, &count);
    if (result != kCGErrorSuccess) return (int32_t)result;
    *actualCount = (int32_t)count;
    if (capacity == 0) return kCGErrorSuccess;
    if ((uint32_t)capacity < count) return kCGErrorRangeCheck;
    PNDirectMode *values = calloc((size_t)count, sizeof(PNDirectMode));
    if (!values) return kCGErrorCannotComplete;
    for (uint32_t i = 0; i < count; i++) {
        result = PNDescribeDirectMode(display, (int32_t)i, &values[i]);
        if (result != kCGErrorSuccess) break;
    }
    if (result == kCGErrorSuccess) {
        uint32_t finalCount = 0;
        result = PNDirectCount(display, &finalCount);
        if (result == kCGErrorSuccess && finalCount != count) {
            result = kCGErrorInvalidOperation;
        }
    }
    if (result == kCGErrorSuccess) {
        memcpy(buffer, values, (size_t)count * sizeof(PNDirectMode));
    }
    free(values);
    return (int32_t)result;
}

int32_t PNCopyCurrentDirectMode(uint32_t display, PNDirectMode *out) {
    if (!out) return kCGErrorIllegalArgument;
    memset(out, 0, sizeof(*out));
    uint32_t count = 0;
    CGError result = PNDirectCount(display, &count);
    if (result != kCGErrorSuccess) return (int32_t)result;
    uint32_t index = 0;
    result = gGetCurrentMode(display, &index);
    if (result != kCGErrorSuccess) return (int32_t)result;
    if (index >= count || index > INT32_MAX) return kCGErrorRangeCheck;
    PNDirectMode mode;
    result = PNDescribeDirectMode(display, (int32_t)index, &mode);
    if (result != kCGErrorSuccess) return (int32_t)result;
    uint32_t finalIndex = 0;
    result = gGetCurrentMode(display, &finalIndex);
    if (result != kCGErrorSuccess) return (int32_t)result;
    if (finalIndex != index) return kCGErrorInvalidOperation;
    *out = mode;
    return kCGErrorSuccess;
}

int32_t PNConfigureDirectMode(CGDisplayConfigRef config, uint32_t display,
                              PNDirectMode expected) {
    if (!config || display == kCGNullDirectDisplay || expected.modeIndex < 0) {
        return kCGErrorIllegalArgument;
    }
    if (!CGDisplayIsOnline(display) || !CGDisplayIsActive(display) ||
        CGDisplayIsBuiltin(display) || CGDisplayIsAsleep(display)) {
        return kCGErrorInvalidOperation;
    }
    uint32_t count = 0;
    CGError result = PNDirectCount(display, &count);
    if (result != kCGErrorSuccess) return (int32_t)result;
    if ((uint32_t)expected.modeIndex >= count) return kCGErrorIllegalArgument;
    PNDirectMode actual;
    result = PNDescribeDirectMode(display, expected.modeIndex, &actual);
    if (result != kCGErrorSuccess) return (int32_t)result;
    if (!PNDirectModeMatches(actual, expected) || !(actual.flags & 0x00000001u) ||
        (actual.flags & 0x40000000u)) return kCGErrorIllegalArgument;
    // The caller must save its original mode first, complete this transaction
    // forSession, then verify actual backing dimensions and monitor timing.
    return (int32_t)gConfigureDirect(config, display, (uint32_t)actual.modeIndex);
}
