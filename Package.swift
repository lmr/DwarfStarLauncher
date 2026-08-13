// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DwarfStarLauncher",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "HuggingFaceDownloader",
            dependencies: [],
            path: "Sources/HuggingFaceDownloader"
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                "HuggingFaceDownloader"
            ],
            path: "Sources/App",
            resources: [
                .copy("../../Resources")
            ]
        ),
        .testTarget(
            name: "HuggingFaceDownloaderTests",
            dependencies: ["HuggingFaceDownloader"],
            path: "Tests/HuggingFaceDownloaderTests"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["App"],
            path: "Tests/AppTests"
        )
    ]
)