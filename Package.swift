// swift-tools-version: 6.0
// Swift packages separate the testable stitch engine from the native Mac application.
import PackageDescription

let package = Package(
    name: "Embroidery",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EmbroideryApp", targets: ["EmbroideryApp"])],
    // Sparkle checks for, downloads and installs new versions of the app (Updates.swift).
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "GeometryBridge", exclude: ["VERSION.txt"], publicHeadersPath: "include", cxxSettings: [.headerSearchPath("vendor/include")]),
        .target(name: "EmbroideryCore", dependencies: ["GeometryBridge"]),
        .executableTarget(name: "EmbroideryApp", dependencies: ["EmbroideryCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "EmbroideryCoreTests", dependencies: ["EmbroideryCore"]),
        .testTarget(name: "EmbroideryAppTests", dependencies: ["EmbroideryApp", "EmbroideryCore"])
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
