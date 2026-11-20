// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "mac-sleepless",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "mac-sleepless", targets: ["MacSleepless"])
    ],
    targets: [
        .executableTarget(
            name: "MacSleepless"
        )
    ]
)
