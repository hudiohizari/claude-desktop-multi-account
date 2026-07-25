// swift-tools-version: 5.9
import PackageDescription

// The app bundle itself is produced by ./build.sh, which needs no package manifest.
// This exists so `swift test` can exercise the same sources.
let package = Package(
    name: "ClaudeClones",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "ClaudeClonesCore",
            path: "ClaudeClones",
            exclude: ["main.swift"]        // top-level code cannot live in a library
        ),
        .testTarget(
            name: "ClaudeClonesTests",
            dependencies: ["ClaudeClonesCore"],
            path: "Tests/ClaudeClonesTests"
        ),
    ]
)
