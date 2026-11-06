import AppKit
import Combine
import CoreGraphics
import Metal
import VirtualDisplayBridge

@MainActor final class DisplayStore: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var selectedDisplayID: UInt32? { didSet { if oldValue != selectedDisplayID { selectedProfileID = profiles.first?.id; refreshNativeOutput() } } }
    @Published var selectedProfileID: String?
    @Published var pending = false
    @Published var secondsRemaining = 0
    @Published var message: String?
    @Published var error: String?
    @Published var isWorking = false
    @Published var activeVirtualID: UInt32?
    @Published var activeProfileID: String?
    @Published var directHiDPIDescription: String?
    @Published var canApplyDirectHiDPI = false
    private var requestedDirectMode: DirectDisplayMode?
    @Published var nativeOutputDescription = B("Lettura del segnale…")
    @Published var nativeRGBDescription: String?
    @Published var canApplyNativeRGB = false
    @Published var canRestoreNativeOutput = false
    private var nativeOriginals: [String: NativeOutputMode] = (try? JSONDecoder().decode([String: NativeOutputMode].self, from: UserDefaults.standard.data(forKey: "Punto.NativeOriginals") ?? Data())) ?? [:]
    private var requestedNativeOutput: NativeOutputMode?
    private var nativeOutputTrial = false
    let metalDeviceName = MTLCreateSystemDefaultDevice()?.name ?? B("Metal non disponibile")
    var virtualAvailable: Bool { PVVirtualDisplayAvailable() }
    var selectedDisplay: DisplayInfo? { displays.first { $0.id == selectedDisplayID } }
    var profiles: [ScalingProfile] { selectedDisplay.map { DisplayInventory.profiles(for: $0) } ?? [] }
    var selectedProfile: ScalingProfile? { profiles.first { $0.id == selectedProfileID } }
    private var baseline: [SavedDisplay] = []
    private var trialDisplayID: UInt32?
    private var virtualTargetID: UInt32?
    private var originalInventory: [UInt32: DisplayInfo] = [:]
    private var guardProcess: RecoveryGuard?
    private var timer: Timer?
    private var deadline: Date?
    private var generation = UUID()
    private var refreshWork: DispatchWorkItem?
    private var applyingTask: Task<Void, Never>?
    private let callback: CGDisplayReconfigurationCallBack = { _, flags, context in
        guard !flags.contains(.beginConfigurationFlag), let context else { return }
        let store = Unmanaged<DisplayStore>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in store.scheduleRefresh() }
    }
    init() {
        refresh()
        CGDisplayRegisterReconfigurationCallback(callback, Unmanaged.passUnretained(self).toOpaque())
    }
    deinit { CGDisplayRemoveReconfigurationCallback(callback, Unmanaged.passUnretained(self).toOpaque()) }
    func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func refresh() {
        let online = DisplayInventory.onlineIDs()
        if !isWorking, let source = activeVirtualID, let target = virtualTargetID,
           (!online.contains(source) || CGDisplayMirrorsDisplay(target) != source) {
            _ = restoreSession()
            error = B("Sorgente HiDPI o duplicazione non più disponibile. Sessione terminata.")
        }
        var values = DisplayInventory.read(excluding: activeVirtualID)
        // A mirrored follower can lack a mode/NSScreen; retain the known physical panel identity and modes.
        if let target = virtualTargetID, online.contains(target), let known = originalInventory[target] {
            let mode = activeVirtualID.flatMap { CGDisplayCopyDisplayMode($0) }.map { DisplayMode(cgMode: $0) } ?? known.current
            values.removeAll { $0.id == target }
            values.insert(DisplayInfo(id: known.id, uuid: known.uuid, name: known.name, isBuiltin: known.isBuiltin,
                nativeWidth: known.nativeWidth, nativeHeight: known.nativeHeight, nativeSource: known.nativeSource,
                current: mode, modes: known.modes, sizeMM: known.sizeMM, isMirrored: true), at: 0)
        }
        displays = values
        if selectedDisplayID == nil || !values.contains(where: { $0.id == selectedDisplayID }) { selectedDisplayID = values.first?.id }
        if selectedProfileID == nil { selectedProfileID = profiles.first?.id }
        refreshNativeOutput()
        if let target = trialDisplayID ?? virtualTargetID, !online.contains(target), !isWorking {
            revert()
            error = B("Monitor scollegato. La sessione di scaling è stata chiusa.")
        }
    }
    private func refreshNativeOutput() {
        guard let display = selectedDisplay else {
            nativeOutputDescription = B("Nessun monitor selezionato"); nativeRGBDescription = nil; canApplyNativeRGB = false; canRestoreNativeOutput = false; return
        }
        do {
            let mode = try DirectModes.sameSizeHiDPI(for: display)
            directHiDPIDescription = mode.map { B("%u × %u punti → %u × %u pixel · %@ Hz", $0.width, $0.height, $0.pixelWidth, $0.pixelHeight, DisplayMode.hz($0.refreshRate)) }
            canApplyDirectHiDPI = !display.isBuiltin && !display.isMirrored && mode != nil && !display.current.isHiDPI
        } catch { directHiDPIDescription = nil; canApplyDirectHiDPI = false }
        do {
            let outputs = try NativeLink.outputs(display.id)
            nativeOutputDescription = outputs.selected.description
            let rgb = NativeLink.preferredRGB(from: outputs.modes, current: outputs.selected)
            nativeRGBDescription = rgb?.description
            canApplyNativeRGB = !display.isBuiltin && !display.isMirrored && rgb != nil && rgb != outputs.selected
            canRestoreNativeOutput = !display.isBuiltin && !display.isMirrored && nativeOriginals[display.uuid].map { $0 != outputs.selected && outputs.modes.contains($0) } == true
        } catch {
            nativeOutputDescription = error.localizedDescription; nativeRGBDescription = nil; canApplyNativeRGB = false; canRestoreNativeOutput = false
        }
    }
    func applyDirectHiDPI() {
        guard !isWorking, !pending, let display = selectedDisplay, !display.isBuiltin, !display.isMirrored else { return }
        do {
            guard let mode = try DirectModes.sameSizeHiDPI(for: display) else { throw DisplayFailure(B("Il driver non offre HiDPI 2× alle dimensioni native con questa frequenza.")) }
            requestedDirectMode = mode
            let profile = ScalingProfile(id: "native-direct-hidpi", title: B("HiDPI diretto a dimensioni native"), subtitle: B("Rendering 2× gestito da macOS, senza display virtuale"), logicalWidth: Int(mode.width), logicalHeight: Int(mode.height), renderWidth: Int(mode.pixelWidth), renderHeight: Int(mode.pixelHeight), requiresVirtual: false, badge: B("DIRETTO"), mode: nil, nativePixels: display.nativeWidth * display.nativeHeight)
            start(profile: profile, display: display)
        } catch { self.error = error.localizedDescription }
    }
    func applyNativeRGB() {
        guard !isWorking, !pending, let display = selectedDisplay, !display.isBuiltin else { return }
        do {
            guard !display.isMirrored, activeVirtualID == nil else { throw DisplayFailure(B("Termina la duplicazione prima della prova RGB nativa.")) }
            guard let native = display.nativeMode, display.current.width == display.nativeWidth,
                  display.current.height == display.nativeHeight, !display.current.isHiDPI else {
                throw DisplayFailure(B("Seleziona prima Nativo 1:1. La prova RGB mantiene la risoluzione corrente."))
            }
            let outputs = try NativeLink.outputs(display.id)
            guard let rgb = NativeLink.preferredRGB(from: outputs.modes, current: outputs.selected), rgb != outputs.selected else {
                message = B("Il monitor usa già RGB completo, oppure non offre un formato RGB alternativo."); return
            }
            if nativeOriginals[display.uuid] == nil {
                nativeOriginals[display.uuid] = outputs.selected
                if let data = try? JSONEncoder().encode(nativeOriginals) { UserDefaults.standard.set(data, forKey: "Punto.NativeOriginals") }
            }
            requestedNativeOutput = rgb
            let profile = ScalingProfile(id: "native-rgb", title: B("RGB completo nativo"), subtitle: B("Segnale RGB alla risoluzione nativa"), logicalWidth: native.width, logicalHeight: native.height,
                renderWidth: native.pixelWidth, renderHeight: native.pixelHeight, requiresVirtual: false, badge: B("NATIVO"), mode: native, nativePixels: display.nativeWidth * display.nativeHeight)
            start(profile: profile, display: display)
        } catch { self.error = error.localizedDescription }
    }
    func restoreNativeOutput() {
        guard !pending, !isWorking, let display = selectedDisplay, !display.isBuiltin,
              !display.isMirrored, let original = nativeOriginals[display.uuid] else { return }
        do {
            let outputs = try NativeLink.outputs(display.id)
            guard outputs.modes.contains(original) else { throw DisplayFailure(B("Il formato precedente non è disponibile con il collegamento attuale.")) }
            requestedNativeOutput = original
            let current = display.current
            let profile = ScalingProfile(id: "native-output-restore", title: B("Ripristino segnale"), subtitle: B("Formato originale del collegamento"), logicalWidth: current.width, logicalHeight: current.height,
                renderWidth: current.pixelWidth, renderHeight: current.pixelHeight, requiresVirtual: false, badge: B("SEGNALE"), mode: current, nativePixels: display.nativeWidth * display.nativeHeight)
            start(profile: profile, display: display)
        } catch { self.error = error.localizedDescription }
    }
    /// Used only by an explicit command-line launch to leave a requested HiDPI profile active.
    func activateHiDPI(logicalWidth: Int) {
        guard let display = displays.first(where: { !$0.isBuiltin }),
              let profile = DisplayInventory.profiles(for: display).first(where: { $0.logicalWidth == logicalWidth && $0.renderWidth == logicalWidth * 2 }) else {
            error = B("Profilo HiDPI richiesto non disponibile."); return
        }
        selectedDisplayID = display.id; selectedProfileID = profile.id
        applySelected()
        Task { @MainActor [weak self] in
            for _ in 0..<80 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard let self else { return }
                if self.pending { self.confirm(); return }
                if !self.isWorking { return }
            }
        }
    }
    func applySelected() {
        guard let profile = selectedProfile, let display = selectedDisplay else { return }
        start(profile: profile, display: display)
    }
    func applyMode(_ mode: DisplayMode) {
        guard let display = selectedDisplay else { return }
        let profile = ScalingProfile(id: "mode-\(mode.id)", title: mode.label, subtitle: B("Modalità esposta dal driver"), logicalWidth: mode.width, logicalHeight: mode.height, renderWidth: mode.pixelWidth, renderHeight: mode.pixelHeight, requiresVirtual: false, badge: B("DIRETTO"), mode: mode, nativePixels: display.nativeWidth * display.nativeHeight)
        start(profile: profile, display: display)
    }
    private func start(profile: ScalingProfile, display: DisplayInfo) {
        guard !isWorking, !pending else { return }
        guard !display.isBuiltin else { error = B("Punto modifica solo i monitor esterni."); return }
        guard !display.isMirrored || virtualTargetID == display.id else { error = B("Disattiva prima la duplicazione già attiva in Impostazioni di Sistema."); return }
        error = nil; message = nil; isWorking = true; nativeOutputTrial = false
        let token = UUID(); generation = token
        let nativeOutputRequest = requestedNativeOutput
        let directModeRequest = requestedDirectMode
        applyingTask = Task { [weak self] in
            guard let self else { return }
            do {
                if !self.baseline.isEmpty {
                    guard self.restoreSession() else { throw DisplayFailure(B("Impossibile iniziare una nuova prova: ripristino precedente incompleto.")) }
                    try await self.pause(350, token: token)
                }
                self.baseline = SavedDisplay.capture()
                guard self.baseline.contains(where: { $0.uuid == display.uuid }), DisplayInventory.uuid(display.id) == display.uuid else {
                    throw DisplayFailure(B("Impossibile salvare la configurazione del monitor. Nessuna modifica applicata."))
                }
                self.originalInventory = Dictionary(uniqueKeysWithValues: self.displays.map { ($0.id, $0) })
                self.trialDisplayID = display.id
                let watchdog = RecoveryGuard()
                try watchdog.start(saved: self.baseline)
                self.guardProcess = watchdog
                guard CGDisplayIsOnline(display.id) != 0, DisplayInventory.uuid(display.id) == display.uuid, CGDisplayIsAsleep(display.id) == 0 else { throw DisplayFailure(B("Il monitor non è collegato o è in standby.")) }
                if profile.id == "native-direct-hidpi", let requestedMode = directModeRequest {
                    try DisplayTransactions.configure { config in
                        try DirectModes.configure(config, display: display.id, mode: requestedMode)
                    }
                    try await self.pause(650, token: token)
                    guard DisplayInventory.uuid(display.id) == display.uuid, CGDisplayMirrorsDisplay(display.id) == 0,
                          try DirectModes.current(display.id).sameGeometry(as: requestedMode),
                          let actual = CGDisplayCopyDisplayMode(display.id), self.matches(actual, profile) else {
                        throw DisplayFailure(B("Il driver non ha attivato HiDPI diretto alle dimensioni richieste. Ripristino automatico."))
                    }
                    if let timing = PanelTiming.read(display: display.id) {
                        guard timing.width == display.nativeWidth, timing.height == display.nativeHeight else {
                            throw DisplayFailure(B("Il timing fisico non corrisponde al pannello nativo. Ripristino automatico."))
                        }
                    }
                    guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id }), abs(screen.backingScaleFactor - 2) < 0.01 else {
                        throw DisplayFailure(B("Le applicazioni non vedono il fattore HiDPI 2× richiesto. Ripristino automatico."))
                    }
                } else if (profile.id == "native-rgb" || profile.id == "native-output-restore"), let requestedOutput = nativeOutputRequest {
                    guard self.baseline.first(where: { $0.uuid == display.uuid })?.output != nil else {
                        throw DisplayFailure(B("Impossibile salvare il formato precedente del segnale. Nessuna modifica applicata."))
                    }
                    let before = display.current
                    try DisplayTransactions.configure { try NativeLink.configure($0, display: display.id, mode: requestedOutput) }
                    try await self.pause(600, token: token)
                    guard DisplayInventory.uuid(display.id) == display.uuid, try NativeLink.current(display.id) == requestedOutput else { throw DisplayFailure(B("Il driver non ha selezionato il formato RGB richiesto.")) }
                    guard let actual = CGDisplayCopyDisplayMode(display.id), actual.width == before.width, actual.height == before.height,
                          actual.pixelWidth == before.pixelWidth, actual.pixelHeight == before.pixelHeight, abs(actual.refreshRate - before.refreshRate) < 0.15 else {
                        throw DisplayFailure(B("Il driver ha cambiato risoluzione o frequenza durante la prova RGB. Ripristino automatico."))
                    }
                    self.nativeOutputTrial = true
                } else if profile.requiresVirtual {
                    try await self.applyVirtual(profile, display: display, token: token)
                } else if let mode = profile.mode {
                    try DisplayTransactions.setMode(display.id, mode)
                    try await self.pause(350, token: token)
                    guard let actual = CGDisplayCopyDisplayMode(display.id), self.matches(actual, profile) else { throw DisplayFailure(B("Il driver non ha applicato la modalità richiesta.")) }
                } else { throw DisplayFailure(B("Modalità non disponibile.")) }
                self.activeProfileID = profile.id
                self.pending = true; self.deadline = Date().addingTimeInterval(20); self.secondsRemaining = 20
                watchdog.arm()
                self.timer?.invalidate()
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.tick() }
                }
                self.message = self.nativeOutputTrial ? B("Formato del segnale applicato a risoluzione e dimensioni invariate. Confronta il testo e conferma entro 20 secondi.") : B("Prova attiva. Conferma entro 20 secondi per mantenere la modalità.")
                self.isWorking = false
                self.refresh()
            } catch {
                if self.generation == token {
                    self.restoreSession()
                    self.isWorking = false
                    self.error = error.localizedDescription
                    self.refresh()
                }
            }
        }
    }
    private func pause(_ milliseconds: UInt64, token: UUID) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
    }
    private func matches(_ mode: CGDisplayMode, _ profile: ScalingProfile) -> Bool {
        mode.width == profile.logicalWidth && mode.height == profile.logicalHeight && mode.pixelWidth == profile.renderWidth && mode.pixelHeight == profile.renderHeight
    }
    private func applyVirtual(_ profile: ScalingProfile, display: DisplayInfo, token: UUID) async throws {
        guard virtualAvailable else { throw DisplayFailure(B("Questo macOS non espone la sorgente virtuale HiDPI. Usa una modalità diretta.")) }
        if let native = display.nativeMode { try DisplayTransactions.setMode(display.id, native) }
        var bridgeError: UnsafePointer<CChar>?
        let rate = display.nativeMode?.refreshRate ?? 60
        let id = PVCreateVirtualDisplay(UInt32(profile.logicalWidth), UInt32(profile.logicalHeight), rate > 0 ? min(rate, 120) : 60, display.sizeMM.width, display.sizeMM.height, &bridgeError)
        guard id != 0 else { throw DisplayFailure(bridgeError.map { B(String(cString: $0)) } ?? B("Creazione della sorgente virtuale fallita.")) }
        activeVirtualID = id; virtualTargetID = display.id
        try await pause(350, token: token)
        guard PVApplyVirtualSettings(&bridgeError) else { throw DisplayFailure(bridgeError.map { B(String(cString: $0)) } ?? B("Impostazioni HiDPI rifiutate.")) }
        var requested: DisplayMode?
        for _ in 0..<16 {
            try await pause(150, token: token)
            requested = DisplayInventory.modes(id).first { self.matches($0.cgMode, profile) }
            if requested != nil { break }
        }
        guard let mode = requested else { throw DisplayFailure(B("macOS non ha pubblicato la modalità HiDPI richiesta. Nessuna modifica mantenuta.")) }
        try DisplayTransactions.setMode(id, mode)
        try await pause(250, token: token)
        guard let source = CGDisplayCopyDisplayMode(id), matches(source, profile) else { throw DisplayFailure(B("La sorgente virtuale non ha attivato il rendering 2× richiesto.")) }
        guard CGDisplayIsOnline(display.id) != 0, DisplayInventory.uuid(display.id) == display.uuid, CGDisplayIsAsleep(display.id) == 0 else { throw DisplayFailure(B("Il monitor non è più disponibile.")) }
        let original = baseline.first { $0.id == display.id }
        try DisplayTransactions.configure { config in
            if let original { try DisplayTransactions.check(CGConfigureDisplayOrigin(config, id, original.x, original.y), B("Posizione sorgente")) }
            try DisplayTransactions.check(CGConfigureDisplayMirrorOfDisplay(config, display.id, id), B("Duplicazione sul monitor esterno"))
        }
        try await pause(500, token: token)
        guard CGDisplayMirrorsDisplay(display.id) == id else { throw DisplayFailure(B("Il driver non ha duplicato la sorgente HiDPI sul monitor.")) }
        // Mirroring may renegotiate the source mode. Verify again; do not mistake a 1× mirror for HiDPI.
        guard let actual = CGDisplayCopyDisplayMode(id) ?? CGDisplayCopyDisplayMode(display.id), matches(actual, profile) else { throw DisplayFailure(B("La duplicazione ha modificato la risoluzione HiDPI. Ripristino automatico.")) }
    }
    private func tick() {
        guard pending, let deadline else { return }
        secondsRemaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        if secondsRemaining == 0 { revert(); message = B("Tempo scaduto: configurazione precedente ripristinata.") }
    }
    func confirm() {
        guard pending, !isWorking else { return }
        timer?.invalidate(); timer = nil; pending = false; deadline = nil; trialDisplayID = nil
        if activeVirtualID != nil { guardProcess?.confirmVirtual() }
        else { guardProcess?.disarm(); guardProcess = nil; baseline = [] }
        message = activeProfileID == "native-direct-hidpi" ? B("HiDPI diretto 2× attivo, dimensioni del desktop 100%. Nessun display virtuale: puoi chiudere Punto.") : nativeOutputTrial ? B("Formato del segnale confermato. Risoluzione e dimensioni invariate; puoi chiudere Punto. La qualità del testo va verificata sul monitor.") : activeVirtualID != nil ? B("HiDPI attivo. Tieni Punto aperto per mantenere la sorgente virtuale.") : B("Modalità diretta confermata. Puoi chiudere Punto.")
        refresh()
    }
    func revert() {
        generation = UUID(); applyingTask?.cancel(); applyingTask = nil
        let restored = restoreSession(); isWorking = false; refresh()
        if restored { message = B("Configurazione precedente ripristinata.") }
    }
    @discardableResult private func restoreSession() -> Bool {
        timer?.invalidate(); timer = nil; pending = false; deadline = nil
        if activeVirtualID != nil {
            if let target = virtualTargetID, CGDisplayIsOnline(target) != 0 {
                try? DisplayTransactions.configure { try DisplayTransactions.check(CGConfigureDisplayMirrorOfDisplay($0, target, kCGNullDirectDisplay), B("Rimozione duplicazione")) }
            }
            PVDestroyVirtualDisplay()
        }
        activeVirtualID = nil; virtualTargetID = nil; trialDisplayID = nil; activeProfileID = nil
        if !baseline.isEmpty, let failure = DisplayTransactions.restore(baseline) {
            error = B("Ripristino incompleto: %@ Il processo di recupero ritenterà.", failure)
            guardProcess?.recoverNow(); guardProcess = nil
            return false
        }
        guardProcess?.disarm(); guardProcess = nil
        baseline = []; originalInventory = [:]; requestedNativeOutput = nil; requestedDirectMode = nil; nativeOutputTrial = false
        return true
    }
    func restoreNative() {
        guard !isWorking, !pending, let display = selectedDisplay, let native = DisplayInventory.profiles(for: display).first(where: { $0.id == "native" }) else { return }
        selectedProfileID = native.id
        start(profile: native, display: display)
    }
    func shutdown() {
        generation = UUID(); applyingTask?.cancel()
        if pending || activeVirtualID != nil { restoreSession() }
    }
    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Punto-diagnostica.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Diagnostics.data(displays: displays, metal: metalDeviceName, virtualAvailable: virtualAvailable).write(to: url, options: .atomic); message = B("Diagnostica esportata.") }
        catch { self.error = error.localizedDescription }
    }
}
