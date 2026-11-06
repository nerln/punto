import Foundation
import CoreGraphics
import Darwin

struct SavedDisplay: Codable {
    let uuid: String
    let id: UInt32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refresh: Double
    let modeID: Int32
    let x: Int32
    let y: Int32
    let mirrorUUID: String?
    var output: NativeOutputMode? = nil
    var directMode: DirectDisplayMode? = nil
    static func capture() -> [SavedDisplay] {
        DisplayInventory.onlineIDs().compactMap { id in
            guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
            let bounds = CGDisplayBounds(id)
            let mirror = CGDisplayMirrorsDisplay(id)
            return SavedDisplay(uuid: DisplayInventory.uuid(id), id: id, width: mode.width, height: mode.height,
                pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight, refresh: mode.refreshRate,
                modeID: mode.ioDisplayModeID, x: Int32(bounds.minX), y: Int32(bounds.minY),
                mirrorUUID: mirror == kCGNullDirectDisplay ? nil : DisplayInventory.uuid(mirror),
                output: CGDisplayIsBuiltin(id) == 0 ? try? NativeLink.current(id) : nil,
                directMode: CGDisplayIsBuiltin(id) == 0 ? try? DirectModes.current(id) : nil)
        }
    }
    func matchingModes(on display: UInt32) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let all = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
        return all.filter { $0.width == width && $0.height == height && $0.pixelWidth == pixelWidth && $0.pixelHeight == pixelHeight && abs($0.refreshRate - refresh) < 0.15 }
            .sorted { ($0.ioDisplayModeID == modeID ? 0 : 1) < ($1.ioDisplayModeID == modeID ? 0 : 1) }
    }
}
struct RecoveryRecord: Codable {
    let displays: [SavedDisplay]
}

enum DisplayTransactions {
    static func check(_ result: CGError, _ operation: String) throws {
        guard result == .success else { throw DisplayFailure(B("%@: CoreGraphics %d.", B(operation), result.rawValue)) }
    }
    static func configure(_ action: (CGDisplayConfigRef) throws -> Void) throws {
        var optional: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&optional), "Inizio configurazione")
        guard let config = optional else { throw DisplayFailure("Configurazione video non disponibile.") }
        do { try action(config) } catch { CGCancelDisplayConfiguration(config); throw error }
        try check(CGCompleteDisplayConfiguration(config, .forSession), "Applicazione configurazione")
    }
    static func setMode(_ display: UInt32, _ mode: DisplayMode) throws {
        guard CGDisplayIsOnline(display) != 0 else { throw DisplayFailure("Il monitor è stato scollegato.") }
        guard CGDisplayIsAsleep(display) == 0 else { throw DisplayFailure("Riattiva il monitor prima di cambiare modalità.") }
        // Some drivers expose equivalent CGDisplayMode objects; try each matching candidate, not a deduplicated mode ID.
        let candidates = DisplayInventory.modes(display).filter { $0.width == mode.width && $0.height == mode.height && $0.pixelWidth == mode.pixelWidth && $0.pixelHeight == mode.pixelHeight && abs($0.refreshRate - mode.refreshRate) < 0.15 }
        var last: Error = DisplayFailure("Modalità non più disponibile. Aggiorna i monitor.")
        for candidate in candidates {
            do {
                try configure { try check(CGConfigureDisplayWithDisplayMode($0, display, candidate.cgMode, nil), "Cambio modalità") }
                return
            } catch { last = error }
        }
        throw last
    }
    @discardableResult static func restore(_ saved: [SavedDisplay]) -> String? {
        let byUUID = Dictionary(uniqueKeysWithValues: DisplayInventory.onlineIDs().map { (DisplayInventory.uuid($0), $0) })
        let connected = saved.compactMap { value in byUUID[value.uuid].map { (value, $0) } }
        var failures: [String] = []
        do {
            try configure { config in
                for (_, id) in connected where CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay {
                    try check(CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay), "Rimozione duplicazione")
                }
            }
        } catch { failures.append(error.localizedDescription) }
        for (value, id) in connected {
            if let mode = CGDisplayCopyDisplayMode(id), mode.width == value.width && mode.height == value.height && mode.pixelWidth == value.pixelWidth && mode.pixelHeight == value.pixelHeight && abs(mode.refreshRate - value.refresh) < 0.15 { continue }
            var restored = false
            for candidate in value.matchingModes(on: id) {
                do {
                    // Recovery accepts every saved timing, including modes deliberately excluded from the UI.
                    try configure { try check(CGConfigureDisplayWithDisplayMode($0, id, candidate, nil), "Ripristino modalità") }
                    restored = true; break
                } catch { continue }
            }
            if !restored, let original = value.directMode, let equivalent = try? DirectModes.all(id).first(where: { $0.sameGeometry(as: original) }) {
                do { try configure { try DirectModes.configure($0, display: id, mode: equivalent) }; restored = true }
                catch { failures.append(error.localizedDescription) }
            }
            if !restored { failures.append(B("Modalità precedente del monitor %u non disponibile.", id)) }
        }
        for (value, id) in connected {
            guard let previousOutput = value.output, CGDisplayIsBuiltin(id) == 0 else { continue }
            if (try? NativeLink.current(id)) == previousOutput { continue }
            do {
                try configure { try NativeLink.configure($0, display: id, mode: previousOutput) }
            } catch { failures.append(error.localizedDescription) }
        }
        do {
            try configure { config in
                for (value, id) in connected {
                    if let targetUUID = value.mirrorUUID, let master = byUUID[targetUUID] {
                        try check(CGConfigureDisplayMirrorOfDisplay(config, id, master), "Ripristino duplicazione")
                    } else {
                        try check(CGConfigureDisplayOrigin(config, id, value.x, value.y), "Ripristino posizione")
                    }
                }
            }
        } catch { failures.append(error.localizedDescription) }
        // The final arrangement transaction can renegotiate a link format. Verify the final state,
        // allowing bounded driver/cache propagation instead of racing a second recovery process.
        for (value, id) in connected {
            if let expected = value.output, CGDisplayIsBuiltin(id) == 0, !NativeLink.waitForCurrent(id, toEqual: expected) {
                failures.append(B("Il formato originale del segnale del monitor %u non è stato ripristinato.", id))
            }
        }
        return failures.isEmpty ? nil : failures.joined(separator: " ")
    }
}
struct DisplayFailure: LocalizedError {
    let text: String
    init(_ text: String) { self.text = B(text) }
    var errorDescription: String? { text }
}

/// A separate process owns the rollback deadline. EOF on its pipe also recovers from a parent crash.
/// After a virtual profile is confirmed it sleeps in readLine(), with no polling or redraw loop.
final class RecoveryGuard {
    private var process: Process?
    private var input: FileHandle?
    private var recordURL: URL?
    func start(saved: [SavedDisplay]) throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Punto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let url = base.appendingPathComponent("recovery.json")
        do {
            try JSONEncoder().encode(RecoveryRecord(displays: saved)).write(to: url, options: .atomic)
            let pipe = Pipe(), child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            child.arguments = ["--watchdog", url.path]
            child.standardInput = pipe
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            try child.run()
            process = child; input = pipe.fileHandleForWriting; recordURL = url
        } catch {
            try? FileManager.default.removeItem(at: base)
            throw error
        }
    }
    deinit { try? input?.close() }
    func recoverNow() { try? input?.close(); input = nil; process = nil }
    func send(_ command: String) { try? input?.write(contentsOf: Data((command + "\n").utf8)) }
    func arm() { send("arm") }
    func confirmVirtual() { send("confirm") }
    func disarm() {
        send("disarm"); try? input?.close(); input = nil; process = nil
        if let url = recordURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        recordURL = nil
    }
    static func run(path: String) {
        guard let data = FileManager.default.contents(atPath: path), let record = try? JSONDecoder().decode(RecoveryRecord.self, from: data) else { return }
        let lock = NSLock()
        var finished = false
        var timer: DispatchSourceTimer?
        func finish(restore: Bool) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            lock.unlock()
            if restore { _ = DisplayTransactions.restore(record.displays) }
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
            Darwin.exit(0)
        }
        func schedule(_ seconds: Int) {
            timer?.cancel()
            let next = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
            next.schedule(deadline: .now() + .seconds(seconds))
            next.setEventHandler { finish(restore: true) }
            timer = next; next.resume()
        }
        schedule(35)
        while let command = readLine() {
            switch command {
            case "arm": schedule(22)
            case "confirm": timer?.cancel(); timer = nil
            case "disarm": finish(restore: false)
            default: break
            }
        }
        finish(restore: true)
    }
}
