import Foundation
import CoreGraphics
import IOKit

/// Driver-reported active physical timing, kept separate from the CG backing buffer.
struct PanelTiming {
    let width: Int
    let height: Int
    let refreshRate: Double
    static func read(display: CGDirectDisplayID) -> PanelTiming? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebuffer"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var matches: [PanelTiming] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? { IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
            guard let attributes = property("DisplayAttributes") as? [String: Any],
                  let product = attributes["ProductAttributes"] as? [String: Any],
                  (product["ProductID"] as? NSNumber)?.uint32Value == CGDisplayModelNumber(display),
                  (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value == CGDisplayVendorNumber(display),
                  let timingID = property("DPTimingModeId") as? NSNumber,
                  let timings = property("TimingElements") as? [[String: Any]],
                  let current = timings.first(where: { ($0["ID"] as? NSNumber) == timingID }),
                  let horizontal = current["HorizontalAttributes"] as? [String: Any],
                  let vertical = current["VerticalAttributes"] as? [String: Any],
                  let w = horizontal["Active"] as? Int, let h = vertical["Active"] as? Int else { continue }
            let hz = (vertical["SyncRate"] as? Double).map { $0 / 65536 } ?? 0
            matches.append(PanelTiming(width: w, height: h, refreshRate: hz))
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
