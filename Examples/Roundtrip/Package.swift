// swift-tools-version: 6.0
//
// Runnable example for the Onetime Secret Swift SDK. A separate package so
// that the library has no executable product; it depends on the SDK through
// the relative path to the repository root.

import PackageDescription

let package = Package(
    name: "Roundtrip",
    platforms: [
        .macOS(.v12),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "Roundtrip",
            dependencies: [
                .product(name: "OnetimeSecret", package: "onetimesecret-ios"),
            ],
            path: "Sources"
        ),
    ],
    swiftLanguageModes: [.v6]
)
