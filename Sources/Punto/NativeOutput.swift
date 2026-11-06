import Foundation
import CoreGraphics
import VirtualDisplayBridge

/// A native scanout format advertised by WindowServer for the current timing.
/// These values describe the link, not the application's framebuffer or font renderer.
struct NativeOutputMode: Codable, Equatable {
    var bitDepth: UInt32
    var fullRange: UInt32
    var transfer: UInt32
    var encoding: UInt32
    init(bitDepth: UInt32, fullRange: UInt32, transfer: UInt32, encoding: UInt32) {
        self.bitDepth = bitDepth; self.fullRange = fullRange; self.transfer = transfer; self.encoding = encoding
    }
    init(_ value: PNOutputMode) {
        self.init(bitDepth: value.bitDepth, fullRange: value.fullRange, transfer: value.transfer, encoding: value.encoding)
    }
    var bridgeValue: PNOutputMode { PNOutputMode(bitDepth: bitDepth, fullRange: fullRange, transfer: transfer, encoding: encoding) }
    var isFullRangeRGB: Bool { encoding == 0 && fullRange == 1 && transfer == 0 }
    var description: String {
        let format = [0: "RGB", 1: "YCbCr 4:4:4", 2: "YCbCr 4:2:2", 3: "YCbCr 4:2:0"][Int(encoding)] ?? B("Formato %u", encoding)
        let range = fullRange == 1 ? B("intervallo completo") : B("intervallo limitato")
        let curve = transfer == 0 ? "SDR" : (transfer == 2 ? "HDR10" : B("curva %u", transfer))
        return "\(format) · \(bitDepth) bit · \(range) · \(curve)"
    }
}

enum NativeLink {
    static var available: Bool { PNOutputAPIAvailable() }
    static func outputs(_ id: CGDirectDisplayID) throws -> (modes: [NativeOutputMode], selected: NativeOutputMode) {
        let capacity: Int32 = 256
        var values = [PNOutputMode](repeating: PNOutputMode(), count: Int(capacity))
        var count: Int32 = 0, selected: Int32 = -1
        let result = values.withUnsafeMutableBufferPointer { PNCopyAvailableOutputModes(id, $0.baseAddress, capacity, &count, &selected) }
        guard result == 0, count > 0, count <= capacity, selected >= 0, selected < count else {
            throw DisplayFailure(B("Formato del segnale nativo non disponibile (CoreGraphics %d).", result))
        }
        let modes = values.prefix(Int(count)).map(NativeOutputMode.init)
        return (modes, modes[Int(selected)])
    }
    static func current(_ id: CGDirectDisplayID) throws -> NativeOutputMode { try outputs(id).selected }
    static func waitForCurrent(_ id: CGDirectDisplayID, toEqual expected: NativeOutputMode) -> Bool {
        for attempt in 0..<8 {
            if (try? current(id)) == expected { return true }
            if attempt < 7 { Thread.sleep(forTimeInterval: 0.08) }
        }
        return false
    }
    static func preferredRGB(from modes: [NativeOutputMode], current: NativeOutputMode) -> NativeOutputMode? {
        let candidates = modes.filter { $0.isFullRangeRGB }
        // Keep the current bit depth when possible, avoiding an unsolicited color-depth tradeoff.
        return candidates.first { $0.bitDepth == current.bitDepth } ?? candidates.max { $0.bitDepth < $1.bitDepth }
    }
    static func configure(_ config: CGDisplayConfigRef, display: CGDirectDisplayID, mode: NativeOutputMode) throws {
        let result = PNConfigureOutputMode(config, display, mode.bridgeValue)
        guard result == 0 else { throw DisplayFailure(B("Selezione RGB rifiutata dal driver (CoreGraphics %d).", result)) }
    }
}
