// swift-tools-version: 6.0
//
// Onetime Secret Swift SDK
// https://github.com/onetimesecret/onetimesecret-ios

import PackageDescription

let package = Package(
    name: "onetimesecret-ios",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "OnetimeSecret", targets: ["OnetimeSecret"]),
    ],
    targets: [
        .target(
            name: "OnetimeSecret",
            path: "Sources/OnetimeSecret",
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "OnetimeSecretTests",
            dependencies: ["OnetimeSecret"],
            path: "Tests/OnetimeSecretTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
