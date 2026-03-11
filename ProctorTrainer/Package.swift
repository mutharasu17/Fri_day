// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProctorTrainer",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/pvieito/PythonKit", from: "0.3.1"),
    ],
    targets: [
        .executableTarget(
            name: "ProctorTrainer",
            dependencies: [
                "PythonKit"
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreML"),
                .linkedFramework("Vision"),
                .linkedFramework("Speech")
            ]
        ),
    ]
)
