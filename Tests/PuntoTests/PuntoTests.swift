import XCTest
import CoreGraphics
@testable import Punto

/// These tests only enumerate existing modes. They never switch a monitor or
/// instantiate a virtual display, including when run on the developer's Mac.
final class PuntoTests: XCTestCase {
    private func allModes() -> [DisplayMode] {
        DisplayInventory.onlineIDs().flatMap { DisplayInventory.modes($0) }
    }

    private func dell(modes: [DisplayMode]) throws -> DisplayInfo {
        guard let current = modes.first else { throw XCTSkip("No display-mode fixture") }
        return DisplayInfo(id: 0xABCD, uuid: "PRIVATE-UUID-MUST-NOT-BE-EXPORTED",
                           name: "Dell U2413 test", isBuiltin: false,
                           nativeWidth: 1920, nativeHeight: 1200,
                           nativeSource: "Fixture native timing", current: current,
                           modes: modes, sizeMM: CGSize(width: 518.4, height: 324),
                           isMirrored: false)
    }

    private func fixtures() throws -> (native: DisplayMode, hidpi: DisplayMode) {
        let values = allModes()
        guard let native = values.first(where: {
            $0.width == 1920 && $0.height == 1200 &&
            $0.pixelWidth == 1920 && $0.pixelHeight == 1200
        }), let hidpi = values.first(where: {
            $0.width == 960 && $0.height == 600 &&
            $0.pixelWidth == 1920 && $0.pixelHeight == 1200
        }) else { throw XCTSkip("The session does not expose the required read-only 1920×1200/960×600 fixtures") }
        return (native, hidpi)
    }

    func testNativeProfileUsesPanelPixelsWithoutExtraRenderArea() throws {
        let f = try fixtures()
        let display = try dell(modes: [f.native, f.hidpi])
        let profile = try XCTUnwrap(DisplayInventory.profiles(for: display).first { $0.id == "native" })
        XCTAssertEqual(profile.logicalWidth, 1920)
        XCTAssertEqual(profile.logicalHeight, 1200)
        XCTAssertEqual(profile.renderWidth, 1920)
        XCTAssertEqual(profile.renderHeight, 1200)
        XCTAssertEqual(profile.pixelMultiplier, 1)
        XCTAssertTrue(profile.isExact)
        XCTAssertFalse(profile.requiresVirtual)
        XCTAssertFalse(try XCTUnwrap(profile.mode).isHiDPI)
    }

    func testExactHiDPIKeepsBackingNativeAndHalvesWorkspace() throws {
        let f = try fixtures()
        let display = try dell(modes: [f.native, f.hidpi])
        let profile = try XCTUnwrap(DisplayInventory.profiles(for: display).first { $0.id == "hidpi-960-600" })
        XCTAssertEqual(profile.logicalWidth, 960)
        XCTAssertEqual(profile.logicalHeight, 600)
        XCTAssertEqual(profile.renderWidth, display.nativeWidth)
        XCTAssertEqual(profile.renderHeight, display.nativeHeight)
        XCTAssertEqual(profile.pixelMultiplier, 1)
        XCTAssertTrue(profile.isExact)
        XCTAssertFalse(profile.requiresVirtual)
        XCTAssertTrue(try XCTUnwrap(profile.mode).isHiDPI)
    }

    func testFullWorkspaceHiDPINeedsFourTimesTheRenderArea() throws {
        let f = try fixtures()
        let display = try dell(modes: [f.native, f.hidpi])
        let profile = try XCTUnwrap(DisplayInventory.profiles(for: display).first { $0.id == "hidpi-1920-1200" })
        XCTAssertEqual(profile.renderWidth, 3840)
        XCTAssertEqual(profile.renderHeight, 2400)
        XCTAssertEqual(profile.pixelMultiplier, 4)
        XCTAssertFalse(profile.isExact)
        XCTAssertTrue(profile.requiresVirtual)
        XCTAssertNil(profile.mode)
    }

    func testIntermediateHiDPIProfilesPreserveAspectAndExposeResampling() throws {
        let f = try fixtures()
        let profiles = DisplayInventory.profiles(for: try dell(modes: [f.native, f.hidpi]))
        for id in ["hidpi-1280-800", "hidpi-1536-960"] {
            let profile = try XCTUnwrap(profiles.first { $0.id == id })
            XCTAssertEqual(profile.logicalWidth * 1200, profile.logicalHeight * 1920)
            XCTAssertEqual(profile.renderWidth, profile.logicalWidth * 2)
            XCTAssertEqual(profile.renderHeight, profile.logicalHeight * 2)
            XCTAssertGreaterThan(profile.pixelMultiplier, 1)
            XCTAssertLessThan(profile.pixelMultiplier, 4)
            XCTAssertFalse(profile.isExact)
            XCTAssertTrue(profile.requiresVirtual)
        }
        XCTAssertEqual(Set(profiles.map(\.id)).count, profiles.count)
    }

    func testExistingDirectHiDPIModeIsPreferredOverVirtualDisplay() throws {
        let f = try fixtures()
        guard let extra = allModes().first(where: {
            $0.width == 1024 && $0.height == 640 &&
            $0.pixelWidth == 2048 && $0.pixelHeight == 1280
        }) else { throw XCTSkip("No direct 1024×640 HiDPI fixture in this session") }
        let display = try dell(modes: [f.native, f.hidpi, extra, extra])
        let profiles = DisplayInventory.profiles(for: display)
        let matches = profiles.filter { $0.id == "hidpi-1024-640" }
        XCTAssertEqual(matches.count, 1)
        let profile = try XCTUnwrap(matches.first)
        XCTAssertFalse(profile.requiresVirtual)
        XCTAssertEqual(profile.mode?.id, extra.id)
        XCTAssertFalse(profile.isExact)
    }

    func testHiDPIBackingIsNotMistakenForNativeLogicalMode() throws {
        let f = try fixtures()
        let display = try dell(modes: [f.hidpi])
        XCTAssertNil(display.nativeMode)
        XCTAssertFalse(DisplayInventory.profiles(for: display).contains { $0.id == "native" })
    }

    func testDiagnosticsPreserveLogicalAndBackingDimensionsWithoutPrivateIdentity() throws {
        let f = try fixtures()
        let display = try dell(modes: [f.hidpi, f.native])
        let data = try Diagnostics.data(displays: [display], metal: "Test GPU", virtualAvailable: true)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["metalDevice"] as? String, "Test GPU")
        XCTAssertEqual(json["virtualAPIAvailable"] as? Bool, true)
        let displays = try XCTUnwrap(json["displays"] as? [[String: Any]])
        XCTAssertEqual(displays.count, 1)
        let current = try XCTUnwrap(displays.first?["current"] as? [String: Any])
        XCTAssertEqual(current["logicalWidth"] as? Int, 960)
        XCTAssertEqual(current["logicalHeight"] as? Int, 600)
        XCTAssertEqual(current["framebufferWidth"] as? Int, 1920)
        XCTAssertEqual(current["framebufferHeight"] as? Int, 1200)
        XCTAssertEqual(current["hiDPI"] as? Bool, true)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains(display.uuid))
        func assertNoPrivateKeys(_ object: Any) {
            if let dictionary = object as? [String: Any] {
                for (key, value) in dictionary {
                    XCTAssertFalse(key.lowercased().contains("uuid"))
                    XCTAssertFalse(key.lowercased().contains("serial"))
                    assertNoPrivateKeys(value)
                }
            } else if let array = object as? [Any] {
                array.forEach(assertNoPrivateKeys)
            }
        }
        assertNoPrivateKeys(json)
    }

    func testRecoveryFindsEquivalentModeWhenNumericModeIDChanges() throws {
        guard let id = DisplayInventory.onlineIDs().first,
              let cg = CGDisplayCopyDisplayMode(id) else { throw XCTSkip("No online display") }
        let saved = SavedDisplay(uuid: DisplayInventory.uuid(id), id: id,
                                 width: cg.width, height: cg.height,
                                 pixelWidth: cg.pixelWidth, pixelHeight: cg.pixelHeight,
                                 refresh: cg.refreshRate, modeID: Int32.min,
                                 x: 0, y: 0, mirrorUUID: nil)
        let candidates = saved.matchingModes(on: id)
        XCTAssertFalse(candidates.isEmpty)
        for mode in candidates {
            XCTAssertEqual(mode.width, cg.width)
            XCTAssertEqual(mode.height, cg.height)
            XCTAssertEqual(mode.pixelWidth, cg.pixelWidth)
            XCTAssertEqual(mode.pixelHeight, cg.pixelHeight)
            XCTAssertLessThan(abs(mode.refreshRate - cg.refreshRate), 0.15)
        }
    }

    func testRecoveryDistinguishesHiDPIFromSameSizeLowResolutionMode() throws {
        guard let id = DisplayInventory.onlineIDs().first(where: { display in
            DisplayInventory.modes(display).contains {
                $0.width == 960 && $0.height == 600 &&
                $0.pixelWidth == 1920 && $0.pixelHeight == 1200
            }
        }), let hiDPI = DisplayInventory.modes(id).first(where: {
            $0.width == 960 && $0.height == 600 && $0.isHiDPI
        }) else { throw XCTSkip("No read-only HiDPI fixture") }
        let saved = SavedDisplay(uuid: DisplayInventory.uuid(id), id: id,
                                 width: hiDPI.width, height: hiDPI.height,
                                 pixelWidth: hiDPI.pixelWidth, pixelHeight: hiDPI.pixelHeight,
                                 refresh: hiDPI.refreshRate, modeID: hiDPI.cgMode.ioDisplayModeID,
                                 x: 0, y: 0, mirrorUUID: nil)
        let candidates = saved.matchingModes(on: id)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy {
            $0.pixelWidth == hiDPI.pixelWidth && $0.pixelHeight == hiDPI.pixelHeight
        })
        XCTAssertTrue(candidates.allSatisfy { $0.pixelWidth > $0.width })
    }
}
