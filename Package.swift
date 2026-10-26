// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MTCircuit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MTCircuit", targets: ["MTCircuit"]),
        .library(name: "CircuitCore", targets: ["CircuitCore"]),
    ],
    targets: [
        // Platform-independent circuit model and simulation engine.
        .target(name: "CircuitCore"),
        // Native macOS app (SwiftUI + AppKit).
        .executableTarget(
            name: "MTCircuit",
            dependencies: ["CircuitCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "CircuitCoreTests", dependencies: ["CircuitCore"]),
    ]
)
