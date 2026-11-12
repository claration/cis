// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "DMG",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "DMG",
            targets: ["DMG"]
        ),
    ],
    targets: [
        .target(
            name: "DMG",
            path: "Sources/DMG",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath(".")
            ]
        ),
    ]
)
