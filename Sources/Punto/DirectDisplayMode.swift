import CoreGraphics
import VirtualDisplayBridge

struct DirectDisplayMode: Codable, Equatable {
    let modeIndex: Int32
    let flags: UInt32
    let width: UInt32
    let height: UInt32
    let pixelWidth: UInt32
    let pixelHeight: UInt32
    let refreshRate: Double
    let density: Float
    init(_ mode: PNDirectMode) {
        modeIndex = mode.modeIndex; flags = mode.flags; width = mode.width; height = mode.height
        pixelWidth = mode.pixelWidth; pixelHeight = mode.pixelHeight; refreshRate = mode.refreshRate; density = mode.density
    }
    var bridgeValue: PNDirectMode {
        PNDirectMode(modeIndex: modeIndex, flags: flags, width: width, height: height,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight, refreshRate: refreshRate, density: density)
    }
    func sameGeometry(as mode: DirectDisplayMode) -> Bool {
        width == mode.width && height == mode.height && pixelWidth == mode.pixelWidth && pixelHeight == mode.pixelHeight && abs(refreshRate - mode.refreshRate) < 0.15 && abs(density - mode.density) < 0.01
    }
    func isNativeSizeHiDPI(width: Int, height: Int) -> Bool {
        self.width == width && self.height == height && pixelWidth == width * 2 && pixelHeight == height * 2 && abs(density - 2) < 0.01 && flags & 1 != 0
    }
}

enum DirectModes {
    static func all(_ display: CGDirectDisplayID) throws -> [DirectDisplayMode] {
        var count: Int32 = 0
        var result = PNCopyDirectModes(display, nil, 0, &count)
        guard result == 0, count > 0, count <= 4096 else { throw DisplayFailure(B("Tabella delle modalità native non disponibile (%d).", result)) }
        var modes = [PNDirectMode](repeating: PNDirectMode(), count: Int(count))
        let capacity = count
        result = modes.withUnsafeMutableBufferPointer { PNCopyDirectModes(display, $0.baseAddress, capacity, &count) }
        guard result == 0, count <= capacity else { throw DisplayFailure(B("La tabella delle modalità native è cambiata (%d).", result)) }
        return modes.prefix(Int(count)).map(DirectDisplayMode.init)
    }
    static func current(_ display: CGDirectDisplayID) throws -> DirectDisplayMode {
        var mode = PNDirectMode()
        let result = PNCopyCurrentDirectMode(display, &mode)
        guard result == 0 else { throw DisplayFailure(B("Lettura della modalità nativa fallita (%d).", result)) }
        return DirectDisplayMode(mode)
    }
    static func sameSizeHiDPI(for display: DisplayInfo) throws -> DirectDisplayMode? {
        let rate = display.current.refreshRate
        return try all(display.id).filter { $0.isNativeSizeHiDPI(width: display.nativeWidth, height: display.nativeHeight) && abs($0.refreshRate - rate) < 0.15 }
            .min { abs($0.refreshRate - rate) < abs($1.refreshRate - rate) }
    }
    static func configure(_ config: CGDisplayConfigRef, display: CGDirectDisplayID, mode: DirectDisplayMode) throws {
        let result = PNConfigureDirectMode(config, display, mode.bridgeValue)
        guard result == 0 else { throw DisplayFailure(B("Modalità HiDPI diretta rifiutata (CoreGraphics %d).", result)) }
    }
}
