#include "NativeOutputBridge.h"
#ifndef VIRTUAL_DISPLAY_BRIDGE_H
#define VIRTUAL_DISPLAY_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Whether the undocumented CoreGraphics virtual-display classes and required
/// methods exist. Availability does not guarantee that WindowServer accepts them.
bool PVVirtualDisplayAvailable(void);

/// Creates one process-owned display. Call on the main thread with an active
/// NSApplication session. Zero means failure; *error is borrowed until the next
/// bridge call. This function refuses to replace an existing live display.
uint32_t PVCreateVirtualDisplay(uint32_t logicalWidth, uint32_t logicalHeight,
                               double refreshRate, double widthMM,
                               double heightMM, const char **error);

/// Call from the main thread after yielding the run loop following creation.
/// A successful return means settings were submitted, not that a particular
/// mode is active: enumerate and verify its points AND backing pixels in Swift.
bool PVApplyVirtualSettings(const char **error);

uint32_t PVVirtualDisplayID(void);

/// Call on the main thread after ending any mirror relationship. Releasing
/// the process-owned object disconnects the virtual display from WindowServer.
void PVDestroyVirtualDisplay(void);

#ifdef __cplusplus
}
#endif

#endif
