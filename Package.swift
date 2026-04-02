// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TH-Programmer",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "mbelib",
            path: "Sources/mbelib",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
            ]
        ),
        .executableTarget(
            name: "TH-Programmer",
            dependencies: ["mbelib"],
            path: "Sources/TH-Programmer",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
            ]
        ),
        .testTarget(
            name: "TH-ProgrammerTests",
            dependencies: [.target(name: "TH-Programmer")],
            path: "Tests/TH-ProgrammerTests"
        )
    ]
)
