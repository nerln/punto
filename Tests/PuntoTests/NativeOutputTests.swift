import XCTest
import CoreGraphics
import VirtualDisplayBridge
@testable import Punto

/// Policy and recovery tests use fixed protocol values. The optional hardware
/// test reads the current link only; no test changes an output or display mode.
final class NativeOutputTests: XCTestCase {
    private func rgb(_ depth: UInt32, range: UInt32 = 1, transfer: UInt32 = 0) -> NativeOutputMode {
        NativeOutputMode(bitDepth: depth, fullRange: range, transfer: transfer, encoding: 0)
    }

    func testRGBSelectionPreservesCurrentTenBitDepth() {
        let current = NativeOutputMode(bitDepth: 10, fullRange: 0, transfer: 0, encoding: 1)
        let expected = rgb(10)
        let modes = [rgb(12), rgb(8), current, expected]

        XCTAssertEqual(NativeLink.preferredRGB(from: modes, current: current), expected)
    }

    func testRGBSelectionUsesHighestAdvertisedSDRDepthWhenCurrentDepthIsUnavailable() {
        let current = NativeOutputMode(bitDepth: 6, fullRange: 0, transfer: 0, encoding: 1)
        let expected = rgb(12)
        let modes = [rgb(16, transfer: 2), rgb(14, range: 0), rgb(8), expected, rgb(10)]

        XCTAssertEqual(NativeLink.preferredRGB(from: modes, current: current), expected)
    }

    func testHDRLimitedRangeAndYCbCrCannotBecomeRGBFallbacks() {
        let current = NativeOutputMode(bitDepth: 10, fullRange: 0, transfer: 0, encoding: 1)
        let incompatible = [
            rgb(10, transfer: 2),
            rgb(10, range: 0),
            NativeOutputMode(bitDepth: 10, fullRange: 1, transfer: 0, encoding: 1),
            NativeOutputMode(bitDepth: 12, fullRange: 1, transfer: 0, encoding: 2),
            NativeOutputMode(bitDepth: 12, fullRange: 1, transfer: 0, encoding: 3),
            NativeOutputMode(bitDepth: 16, fullRange: 1, transfer: 0, encoding: 99)
        ]

        XCTAssertTrue(incompatible.allSatisfy { !$0.isFullRangeRGB })
        XCTAssertNil(NativeLink.preferredRGB(from: incompatible, current: current))
        XCTAssertNil(NativeLink.preferredRGB(from: [], current: current))
    }

    func testAlreadyFullRangeRGBDoesNotRequestHigherBitDepth() {
        let current = rgb(8)
        XCTAssertEqual(NativeLink.preferredRGB(from: [rgb(12), current, rgb(10)], current: current), current)
    }

    func testOutputProtocolFieldsSurviveJSONAndBridgeRoundTrips() throws {
        // Preserve the four raw words, including a non-RGB, non-SDR snapshot:
        // recovery must not normalize it to the application's preferred RGB.
        let original = NativeOutputMode(bitDepth: 10, fullRange: 0, transfer: 2, encoding: 3)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(NativeOutputMode.self, from: data)

        XCTAssertEqual(restored, original)
        XCTAssertEqual(NativeOutputMode(restored.bridgeValue), original)
        XCTAssertEqual(MemoryLayout<PNOutputMode>.size, 16)
        XCTAssertEqual(restored.bridgeValue.bitDepth, 10)
        XCTAssertEqual(restored.bridgeValue.fullRange, 0)
        XCTAssertEqual(restored.bridgeValue.transfer, 2)
        XCTAssertEqual(restored.bridgeValue.encoding, 3)
    }

    func testRecoveryDecodesOlderSnapshotWithoutOutputField() throws {
        let legacy = Data("""
        {
          "uuid": "saved-external-display", "id": 3,
          "width": 1920, "height": 1200,
          "pixelWidth": 1920, "pixelHeight": 1200,
          "refresh": 60, "modeID": 27,
          "x": -1920, "y": 80, "mirrorUUID": null
        }
        """.utf8)

        let saved = try JSONDecoder().decode(SavedDisplay.self, from: legacy)
        XCTAssertNil(saved.output)
        XCTAssertEqual(saved.uuid, "saved-external-display")
        XCTAssertEqual(saved.width, 1920)
        XCTAssertEqual(saved.pixelHeight, 1200)
        XCTAssertEqual(saved.x, -1920)
        XCTAssertNil(saved.mirrorUUID)
    }

    func testRecoveryRetainsOriginalLinkAlongsideModeAndArrangement() throws {
        let original = NativeOutputMode(bitDepth: 10, fullRange: 0, transfer: 0, encoding: 1)
        let saved = SavedDisplay(uuid: "saved-external-display", id: 3,
                                 width: 1920, height: 1200, pixelWidth: 1920, pixelHeight: 1200,
                                 refresh: 60, modeID: 27, x: -1920, y: 80,
                                 mirrorUUID: "saved-mirror-master", output: original)

        let data = try JSONEncoder().encode(RecoveryRecord(displays: [saved]))
        let record = try JSONDecoder().decode(RecoveryRecord.self, from: data)
        let restored = try XCTUnwrap(record.displays.first)

        XCTAssertEqual(restored.output, original)
        XCTAssertEqual(restored.uuid, saved.uuid)
        XCTAssertEqual(restored.modeID, saved.modeID)
        XCTAssertEqual(restored.pixelWidth, saved.pixelWidth)
        XCTAssertEqual(restored.refresh, saved.refresh)
        XCTAssertEqual(restored.x, saved.x)
        XCTAssertEqual(restored.y, saved.y)
        XCTAssertEqual(restored.mirrorUUID, saved.mirrorUUID)
    }

    func testDescriptionsDistinguishConnectionEncodings() {
        let expectedNames: [UInt32: String] = [0: "RGB", 1: "YCbCr 4:4:4", 2: "YCbCr 4:2:2", 3: "YCbCr 4:2:0"]
        for (encoding, name) in expectedNames {
            let mode = NativeOutputMode(bitDepth: 10, fullRange: 0, transfer: 0, encoding: encoding)
            XCTAssertTrue(mode.description.hasPrefix(name), "Encoding \(encoding) must not describe another chroma format")
        }
        let unknown = NativeOutputMode(bitDepth: 10, fullRange: 1, transfer: 0, encoding: 99)
        XCTAssertFalse(unknown.isFullRangeRGB)
        XCTAssertTrue(unknown.description.contains("99"))
    }

    func testCurrentOutputReadMatchesAnAdvertisedModeWhenHardwareSupportsIt() throws {
        guard NativeLink.available else { throw XCTSkip("Native output API unavailable") }
        guard let display = DisplayInventory.onlineIDs().first(where: {
            CGDisplayIsBuiltin($0) == 0 && CGDisplayIsAsleep($0) == 0 && CGDisplayMirrorsDisplay($0) == 0
        }) else { throw XCTSkip("No awake unmirrored external display") }
        let outputs: (modes: [NativeOutputMode], selected: NativeOutputMode)
        do { outputs = try NativeLink.outputs(display) }
        catch { throw XCTSkip("The connected driver does not expose readable native output modes: \(error)") }

        XCTAssertFalse(outputs.modes.isEmpty)
        XCTAssertTrue(outputs.modes.contains(outputs.selected))
        XCTAssertGreaterThan(outputs.selected.bitDepth, 0)
        // Exercise the independent C getter without entering any transaction.
        var current = PNOutputMode()
        XCTAssertEqual(PNCopyCurrentOutputMode(display, &current), 0)
        XCTAssertTrue(outputs.modes.contains(NativeOutputMode(current)))
    }
}
