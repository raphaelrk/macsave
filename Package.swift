// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSave",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacSave",
            path: "Sources/MacSave",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
