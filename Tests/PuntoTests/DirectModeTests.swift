import XCTest
import CoreGraphics
import VirtualDisplayBridge
@testable import Punto

final class DirectModeTests: XCTestCase {
    func testHiDPIGeometryIsNotInferredFromLogicalSizeAlone() {
        let hi = DirectDisplayMode(PNDirectMode(modeIndex: 36, flags: 0x200001, width: 1920, height: 1200, pixelWidth: 3840, pixelHeight: 2400, refreshRate: 60, density: 2))
        let low = DirectDisplayMode(PNDirectMode(modeIndex: 27, flags: 0x2000007, width: 1920, height: 1200, pixelWidth: 1920, pixelHeight: 1200, refreshRate: 60, density: 1))
        XCTAssertTrue(hi.isNativeSizeHiDPI(width: 1920, height: 1200))
        XCTAssertFalse(low.isNativeSizeHiDPI(width: 1920, height: 1200))
        XCTAssertFalse(hi.sameGeometry(as: low))
    }
    func testEquivalentRecoveryModeCanHaveDifferentIndex() {
        let a = DirectDisplayMode(PNDirectMode(modeIndex: 36, flags: 1, width: 1920, height: 1200, pixelWidth: 3840, pixelHeight: 2400, refreshRate: 60, density: 2))
        let b = DirectDisplayMode(PNDirectMode(modeIndex: 90, flags: 1, width: 1920, height: 1200, pixelWidth: 3840, pixelHeight: 2400, refreshRate: 60, density: 2))
        XCTAssertTrue(a.sameGeometry(as: b))
        XCTAssertEqual(DirectDisplayMode(a.bridgeValue), a)
        XCTAssertEqual(try JSONDecoder().decode(DirectDisplayMode.self, from: JSONEncoder().encode(a)), a)
    }
    func testHiddenNativeSizeModeIsReadWithoutSwitchingDisplay() throws {
        guard let display = DisplayInventory.read().first(where: { !$0.isBuiltin && $0.nativeWidth == 1920 && $0.nativeHeight == 1200 }) else { throw XCTSkip("Dell-style fixture not connected") }
        let mode = try XCTUnwrap(DirectModes.sameSizeHiDPI(for: display))
        XCTAssertEqual(mode.pixelWidth, 3840)
        XCTAssertEqual(mode.pixelHeight, 2400)
        XCTAssertEqual(mode.density, 2)
        XCTAssertEqual(mode.refreshRate, display.current.refreshRate, accuracy: 0.15)
        let current = try DirectModes.current(display.id)
        XCTAssertEqual(current.width, UInt32(display.current.width))
        XCTAssertEqual(current.pixelWidth, UInt32(display.current.pixelWidth))
    }
    func testNativePhysicalTimingIsIndependentOfCGBacking() throws {
        guard let display = DisplayInventory.read().first(where: { !$0.isBuiltin }), let timing = PanelTiming.read(display: display.id) else { throw XCTSkip("Physical timing not exposed") }
        XCTAssertEqual(timing.width, display.nativeWidth)
        XCTAssertEqual(timing.height, display.nativeHeight)
        XCTAssertEqual(timing.refreshRate, display.current.refreshRate, accuracy: 0.2)
    }
}
