// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "Kaleidoscope",

    products: [
        .executable(
            name: "Kaleidoscope",
            targets: ["Kaleidoscope"]
        ),
    ],

    dependencies: [ ],

    targets: [
        .target(
            name: "KaleidoscopeLib",
            dependencies: []
        ),
        .target(
            name: "Kaleidoscope",
            dependencies: ["KaleidoscopeLib"]
        ),
        .testTarget(
            name: "KaleidoscopeLibTests",
            dependencies: ["KaleidoscopeLib"]
        ),
    ]
)
