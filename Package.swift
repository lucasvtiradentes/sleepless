// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "sleepless",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "sleepless", targets: ["Sleepless"])
    ],
    targets: [
        .executableTarget(
            name: "Sleepless"
        )
    ]
)
