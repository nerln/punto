import AppKit
import CoreGraphics

/// Explicit integration test entry points. Never invoked by a normal app launch.
enum DisplaySmoke {
    @MainActor static func run(virtual: Bool, crash: Bool = false, nativeRGB: Bool = false, nativeHiDPI: Bool = false) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            let saved = SavedDisplay.capture()
            let store = DisplayStore()
            guard let display = store.displays.first(where: { !$0.isBuiltin && !$0.isMirrored }) else {
                print("FAIL: no unmirrored external display"); Darwin.exit(2)
            }
            store.selectedDisplayID = display.id
            if nativeHiDPI {
                print("TEST: native direct HiDPI2× at100% workspace, no virtual display")
                store.applyDirectHiDPI()
            } else if nativeRGB {
                print("TEST: native RGB full-range, before=\((try? NativeLink.current(display.id).description) ?? "unknown")")
                store.applyNativeRGB()
            } else {
                let wanted = store.profiles.first { p in
                    virtual ? (p.requiresVirtual && p.logicalWidth < display.nativeWidth) : (p.mode?.isHiDPI == true && p.isExact)
                }
                guard let wanted else { print("FAIL: test profile unavailable"); Darwin.exit(2) }
                print("TEST: \(wanted.title), \(wanted.logicalWidth)×\(wanted.logicalHeight) → \(wanted.renderWidth)×\(wanted.renderHeight)")
                store.selectedProfileID = wanted.id
                store.applySelected()
            }
            for _ in 0..<80 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if store.pending || (!store.isWorking && store.error != nil) { break }
            }
            let succeeded = store.pending
            if succeeded {
                if nativeHiDPI, let actual = try? DirectModes.current(display.id) {
                    print("DIRECT: index=\(actual.modeIndex), logical=\(actual.width)×\(actual.height), backing=\(actual.pixelWidth)×\(actual.pixelHeight), density=\(actual.density), Hz=\(actual.refreshRate)")
                    if let timing = PanelTiming.read(display: display.id) { print("PHYSICAL TIMING: \(timing.width)×\(timing.height) @\(timing.refreshRate) Hz") }
                }
                if nativeRGB { print("OUTPUT: \((try? NativeLink.current(display.id).description) ?? "unknown")") }
                print("APPLIED: verified logical/backing dimensions; virtual=\(store.activeVirtualID.map(String.init) ?? "none")")
                if crash {
                    print("TEST: deliberate process exit; independent watchdog must restore")
                    fflush(stdout)
                    Darwin._exit(0)
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            } else { print("APPLY FAILED: \(store.error ?? "timeout")") }
            store.revert()
            try? await Task.sleep(nanoseconds: 500_000_000)
            let online = DisplayInventory.onlineIDs()
            let restored = saved.allSatisfy { previous in
                guard let id = online.first(where: { DisplayInventory.uuid($0) == previous.uuid }), let mode = CGDisplayCopyDisplayMode(id) else { return false }
                let mirror = CGDisplayMirrorsDisplay(id)
                let mirrorUUID = mirror == 0 ? nil : DisplayInventory.uuid(mirror)
                let bounds = CGDisplayBounds(id)
                let outputRestored = previous.output == nil || (try? NativeLink.current(id)) == previous.output
                return outputRestored && Int32(bounds.minX) == previous.x && Int32(bounds.minY) == previous.y && mode.width == previous.width && mode.height == previous.height && mode.pixelWidth == previous.pixelWidth && mode.pixelHeight == previous.pixelHeight && mirrorUUID == previous.mirrorUUID
            }
            print(restored ? "RESTORED: all original resolutions, origins, mirror topology and native output formats" : "FAIL: restore mismatch")
            fflush(stdout)
            Darwin.exit(succeeded && restored ? 0 : 1)
        }
        app.run()
    }
}
