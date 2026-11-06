// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Punto",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Punto", targets: ["Punto"])],
    targets: [
        .target(name: "VirtualDisplayBridge", path: "Sources/VirtualDisplayBridge", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fobjc-arc"])], linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("Foundation")]),
        .executableTarget(name: "Punto", dependencies: ["VirtualDisplayBridge"], resources: [.process("Resources")], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("CoreGraphics"), .linkedFramework("IOKit"), .linkedFramework("Metal"), .linkedFramework("MetalKit")]),
        .testTarget(name: "PuntoTests", dependencies: ["Punto"])
    ],
    swiftLanguageModes: [.v5]
)
