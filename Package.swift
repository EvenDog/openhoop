// swift-tools-version: 6.0
// Swift packages separate the testable stitch engine from the native Mac application.
import PackageDescription

let package = Package(
    name: "Embroidery",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EmbroideryApp", targets: ["EmbroideryApp"])],
    targets: [
        .target(name: "GeometryBridge", exclude: ["VERSION.txt"], publicHeadersPath: "include", cxxSettings: [.headerSearchPath("vendor/include")]),
        .target(name: "EmbroideryCore", dependencies: ["GeometryBridge"]),
        .executableTarget(name: "EmbroideryApp", dependencies: ["EmbroideryCore"]),
        .testTarget(name: "EmbroideryCoreTests", dependencies: ["EmbroideryCore"]),
        .testTarget(name: "EmbroideryAppTests", dependencies: ["EmbroideryApp", "EmbroideryCore"])
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
