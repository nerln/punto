import SwiftUI
import AppKit
import Metal
import VirtualDisplayBridge

@main struct PuntoLauncher {
    @MainActor static func main() {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--watchdog" {
            RecoveryGuard.run(path: CommandLine.arguments[2]); return
        }
        if CommandLine.arguments.contains("--smoke-direct") || CommandLine.arguments.contains("--smoke-virtual") || CommandLine.arguments.contains("--smoke-rgb") || CommandLine.arguments.contains("--smoke-native-hidpi") {
            DisplaySmoke.run(virtual: CommandLine.arguments.contains("--smoke-virtual"), crash: CommandLine.arguments.contains("--simulate-crash"), nativeRGB: CommandLine.arguments.contains("--smoke-rgb"), nativeHiDPI: CommandLine.arguments.contains("--smoke-native-hidpi")); return
        }
        if CommandLine.arguments.contains("--diagnose") {
            let values = DisplayInventory.read()
            if let data = try? Diagnostics.data(displays: values, metal: MTLCreateSystemDefaultDevice()?.name ?? B("Nessuna"), virtualAvailable: PVVirtualDisplayAvailable()), let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        PuntoApplication.main()
    }
}

struct PuntoApplication: App {
    @NSApplicationDelegateAdaptor(PuntoAppDelegate.self) private var appDelegate
    @StateObject private var store = DisplayStore()
    @State private var processedLaunch = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    private var selectedLanguage: AppLanguage { AppLanguage(rawValue: appLanguage) ?? .system }
    private var selectedAppearance: AppAppearance { AppAppearance(rawValue: appAppearance) ?? .system }
    var body: some Scene {
        Window("Punto", id: "main") {
            ContentView().environmentObject(store)
                .environment(\.locale, selectedLanguage.locale)
                .preferredColorScheme(selectedAppearance.colorScheme)
                .onChange(of: appLanguage) { _, _ in store.refresh() }
                .onAppear {
                    PuntoAppDelegate.store = store
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    if !processedLaunch {
                        processedLaunch = true
                        let args = CommandLine.arguments
                        if args.contains("--activate-native-rgb") || args.contains("--activate-native-hidpi") {
                            if args.contains("--activate-native-hidpi") { store.applyDirectHiDPI() } else { store.applyNativeRGB() }
                            Task { @MainActor in
                                for _ in 0..<80 {
                                    try? await Task.sleep(nanoseconds: 150_000_000)
                                    if store.pending { store.confirm(); break }
                                    if !store.isWorking { break }
                                }
                            }
                        }
                        if let index = args.firstIndex(of: "--activate-hidpi"), args.indices.contains(index + 1), let width = Int(args[index + 1]) {
                            store.activateHiDPI(logicalWidth: width)
                        }
                    }
                }
        }
        .defaultSize(width: 1080, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu(B("Monitor")) {
                Button(B("Aggiorna monitor")) { store.refresh() }.keyboardShortcut("r")
                    .disabled(store.pending || store.isWorking)
                Button(B("Ripristina 1:1")) { store.restoreNative() }.disabled(store.pending || store.isWorking)
                Button(B("Annulla prova / termina HiDPI virtuale")) { store.revert() }
                    .disabled(!store.pending && store.activeVirtualID == nil && !store.isWorking)
                Divider()
                Button(B("Esporta diagnostica…")) { store.exportDiagnostics() }
            }
        }
        Settings {
            SettingsView().environment(\.locale, selectedLanguage.locale)
                .preferredColorScheme(selectedAppearance.colorScheme)
        }
        MenuBarExtra("Punto", systemImage: "display") {
            PuntoMenu().environmentObject(store)
                .environment(\.locale, selectedLanguage.locale)
        }
    }
}

private struct PuntoMenu: View {
    @EnvironmentObject private var store: DisplayStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(B("Apri Punto")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        if let display = store.selectedDisplay {
            Text(display.name)
            Text(display.current.label)
        }
        if store.pending {
            Button(B("Mantieni modalità")) { store.confirm() }
            Button(B("Annulla prova")) { store.revert() }
        }
        if store.activeVirtualID != nil { Button(B("Termina HiDPI virtuale")) { store.revert() } }
        Divider()
        Button(B("Esci da Punto")) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

final class PuntoAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var store: DisplayStore?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @MainActor func applicationWillTerminate(_ notification: Notification) { Self.store?.shutdown() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) }
        return true
    }
}

enum Diagnostics {
    static func data(displays: [DisplayInfo], metal: String, virtualAvailable: Bool) throws -> Data {
        let contents: [String: Any] = [
            "app": "Punto 0.1.0", "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "metalDevice": metal, "virtualAPIAvailable": virtualAvailable,
            "notes": "Framebuffer dimensions are not measured cable timing. Pixel-area ratios are theoretical, not measured GPU load. No hardware serial numbers included.",
            "displays": displays.map { display -> [String: Any] in
                ["id": display.id, "name": display.name, "builtIn": display.isBuiltin,
                 "panelNative": ["width": display.nativeWidth, "height": display.nativeHeight, "source": display.nativeSource],
                 "current": mode(display.current), "mirrored": display.isMirrored,
                 "directMode": (try? DirectModes.current(display.id)).map { value in
                     ["modeIndex": value.modeIndex, "logicalWidth": value.width, "logicalHeight": value.height, "framebufferWidth": value.pixelWidth, "framebufferHeight": value.pixelHeight, "density": value.density, "refreshHz": value.refreshRate] as [String: Any]
                 } ?? ["unavailable": true],
                 "panelTiming": PanelTiming.read(display: display.id).map { timing in
                     ["width": timing.width, "height": timing.height, "refreshHz": timing.refreshRate] as [String: Any]
                 } ?? ["unavailable": true],
                 "nativeOutput": (try? NativeLink.outputs(display.id)).map { output in
                     ["selected": nativeOutput(output.selected), "available": output.modes.map(nativeOutput)] as [String: Any]
                 } ?? ["unavailable": true],
                 "modes": display.modes.map { mode($0) }]
            }
        ]
        return try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    }
    static func nativeOutput(_ output: NativeOutputMode) -> [String: Any] {
        ["bitDepth": output.bitDepth, "fullRange": output.fullRange, "transfer": output.transfer, "encoding": output.encoding, "description": output.description]
    }
    static func mode(_ mode: DisplayMode) -> [String: Any] {
        ["modeID": mode.cgMode.ioDisplayModeID, "logicalWidth": mode.width, "logicalHeight": mode.height,
         "framebufferWidth": mode.pixelWidth, "framebufferHeight": mode.pixelHeight,
         "refreshHz": mode.refreshRate, "hiDPI": mode.isHiDPI, "flags": mode.cgMode.ioFlags]
    }
}
