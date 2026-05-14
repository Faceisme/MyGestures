// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MyGestures",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "MyGestures", targets: ["MyGestures"])
    ],
    targets: [
        .executableTarget(
            name: "MyGestures",
            path: "Sources/MouseGestureLite"
        )
    ],
    swiftLanguageModes: [.v5]
)
