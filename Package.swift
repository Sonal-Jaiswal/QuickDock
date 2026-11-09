// swift-tools-version:6.0
//
// QuickDock — Your Mac, one click away.
//
// The package has two targets:
//  • QuickDockCore — models, persistence and services. No UI. Fully unit-tested.
//  • QuickDock     — the AppKit/SwiftUI application (menu bar, launcher panel, settings).
//
// Build a runnable, signed .app bundle with `scripts/build-app.sh`.

import PackageDescription

let package = Package(
    name: "QuickDock",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "QuickDock", targets: ["QuickDock"]),
    ],
    targets: [
        .target(
            name: "QuickDockCore",
            path: "Sources/QuickDockCore"
        ),
        .executableTarget(
            name: "QuickDock",
            dependencies: ["QuickDockCore"],
            path: "Sources/QuickDock",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "QuickDockCoreTests",
            dependencies: ["QuickDockCore"],
            path: "Tests/QuickDockCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
