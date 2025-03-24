// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "KwisperSwift",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "KwisperSwift", targets: ["KwisperSwift"])
    ],
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI.git", from: "0.2.4")
    ],
    targets: [
        .executableTarget(
            name: "KwisperSwift",
            dependencies: [
                .product(name: "OpenAI", package: "OpenAI")
            ]
        )
    ]
)