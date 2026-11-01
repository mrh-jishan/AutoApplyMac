// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoApplyMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AutoApplyMac", targets: ["AutoApplyMac"])
    ],
    targets: [
        .executableTarget(
            name: "AutoApplyMac",
            dependencies: [],
            path: "Sources/AutoApplyMac",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
