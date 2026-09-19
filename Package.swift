// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EyesUpGuardian",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "EyesUpGuardian", targets: ["EyesUpApp"]),
    ],
    targets: [
        .target(
            name: "EyesUpCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "EyesUpApp",
            dependencies: ["EyesUpCore"],
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "EyesUpCoreTests",
            dependencies: ["EyesUpCore"]
        ),
    ]
)
