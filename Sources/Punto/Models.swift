import AppKit
import CoreGraphics
import IOKit.graphics

struct DisplayMode: Identifiable {
    let cgMode: CGDisplayMode
    var id: String { "\(cgMode.ioDisplayModeID)-\(width)-\(height)-\(pixelWidth)-\(pixelHeight)-\(refreshRate)" }
    var width: Int { cgMode.width }
    var height: Int { cgMode.height }
    var pixelWidth: Int { cgMode.pixelWidth }
    var pixelHeight: Int { cgMode.pixelHeight }
    var refreshRate: Double { cgMode.refreshRate }
    var isHiDPI: Bool { pixelWidth > width && pixelHeight > height }
    var label: String { "\(width) × \(height) · \(isHiDPI ? "HiDPI" : "1×") · \(Self.hz(refreshRate)) Hz" }
    static func hz(_ value: Double) -> String { value > 0 ? String(format: value.rounded() == value ? "%.0f" : "%.2f", value) : B("variabile") }
}

struct DisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let isBuiltin: Bool
    let nativeWidth: Int
    let nativeHeight: Int
    let nativeSource: String
    let current: DisplayMode
    let modes: [DisplayMode]
    let sizeMM: CGSize
    let isMirrored: Bool
    var ppi: Double { sizeMM.width > 0 ? Double(nativeWidth) / sizeMM.width * 25.4 : 0 }
    var nativeMode: DisplayMode? {
        modes.filter { $0.width == nativeWidth && $0.height == nativeHeight && !$0.isHiDPI }
            .max { $0.refreshRate < $1.refreshRate }
    }
}

struct ScalingProfile: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let logicalWidth: Int
    let logicalHeight: Int
    let renderWidth: Int
    let renderHeight: Int
    let requiresVirtual: Bool
    let badge: String
    let mode: DisplayMode?
    let nativePixels: Int
    var pixelMultiplier: Double { Double(renderWidth * renderHeight) / Double(max(1, nativePixels)) }
    var isExact: Bool { renderWidth * renderHeight == nativePixels }
}

enum DisplayInventory {
    static func onlineIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
    static func uuid(_ id: CGDirectDisplayID) -> String {
        guard let value = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "id:\(id)" }
        return CFUUIDCreateString(nil, value) as String
    }
    static func modes(_ id: CGDirectDisplayID) -> [DisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        return ((CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? [])
            .filter { $0.isUsableForDesktopGUI() && $0.width >= 800 && $0.height >= 500 }
            .map { DisplayMode(cgMode: $0) }
    }
    static func read(excluding: CGDirectDisplayID? = nil) -> [DisplayInfo] {
        onlineIDs().filter { $0 != excluding }.compactMap { id in
            guard let cg = CGDisplayCopyDisplayMode(id) else { return nil }
            let all = modes(id)
            // The native flag describes the panel's preferred timing; the largest render buffer can be a supersampled mode.
            let native = all.filter { $0.cgMode.ioFlags & UInt32(kDisplayModeNativeFlag) != 0 }
                .max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
            let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
            return DisplayInfo(id: id, uuid: uuid(id), name: screen?.localizedName ?? B("Monitor %u", id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                nativeWidth: native?.pixelWidth ?? cg.pixelWidth, nativeHeight: native?.pixelHeight ?? cg.pixelHeight,
                nativeSource: native != nil ? B("Timing nativo dichiarato dal driver") : B("Stima dalla modalità corrente; timing nativo non disponibile"),
                current: DisplayMode(cgMode: cg), modes: all, sizeMM: CGDisplayScreenSize(id),
                isMirrored: CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay || CGDisplayIsInMirrorSet(id) != 0)
        }.sorted { a, b in a.isBuiltin == b.isBuiltin ? a.name < b.name : !a.isBuiltin }
    }
    static func profiles(for d: DisplayInfo) -> [ScalingProfile] {
        let pixels = d.nativeWidth * d.nativeHeight
        var result: [ScalingProfile] = []
        if let mode = d.nativeMode {
            result.append(ScalingProfile(id: "native", title: B("Nativo 1:1"), subtitle: B("Ogni pixel del desktop su un pixel del pannello."), logicalWidth: mode.width, logicalHeight: mode.height, renderWidth: mode.pixelWidth, renderHeight: mode.pixelHeight, requiresVirtual: false, badge: B("MINIMO CARICO"), mode: mode, nativePixels: pixels))
        }
        // Expose useful, aspect-correct HiDPI sizes. Prefer direct modes over a virtual source whenever possible.
        var sizes = [(d.nativeWidth / 2, d.nativeHeight / 2)]
        for scale in [1.5, 1.25, 1.0] {
            let divisor = gcd(d.nativeWidth, d.nativeHeight)
            let aspectW = d.nativeWidth / divisor, aspectH = d.nativeHeight / divisor
            let units = Int((Double(divisor) / scale).rounded())
            sizes.append((aspectW * units, aspectH * units))
        }
        sizes += d.modes.filter { $0.isHiDPI && aspectMatches($0.width, $0.height, d.nativeWidth, d.nativeHeight) }.map { ($0.width, $0.height) }
        var seen = Set<String>()
        for (w, h) in sizes.sorted(by: { $0.0 < $1.0 }) where w >= 800 && h >= 500 {
            let key = "hidpi-\(w)-\(h)"
            guard seen.insert(key).inserted else { continue }
            let direct = d.modes.filter { $0.width == w && $0.height == h && $0.pixelWidth == w * 2 && $0.pixelHeight == h * 2 }.max { $0.refreshRate < $1.refreshRate }
            let exact = w * 2 == d.nativeWidth && h * 2 == d.nativeHeight
            result.append(ScalingProfile(id: key, title: exact ? B("HiDPI 2× esatto") : "HiDPI \(w) × \(h)", subtitle: exact ? B("Testo grande, nessun ricampionamento del buffer.") : B("Rendering 2×, poi riduzione sul pannello."), logicalWidth: w, logicalHeight: h, renderWidth: w * 2, renderHeight: h * 2, requiresVirtual: direct == nil, badge: exact ? B("SENZA RESAMPLING") : (direct != nil ? B("DIRETTO") : B("VIRTUALE")), mode: direct, nativePixels: pixels))
        }
        return result
    }
    static func aspectMatches(_ w: Int, _ h: Int, _ nw: Int, _ nh: Int) -> Bool {
        abs(Double(w) / Double(max(1,h)) - Double(nw) / Double(max(1,nh))) < 0.008
    }
    static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}
