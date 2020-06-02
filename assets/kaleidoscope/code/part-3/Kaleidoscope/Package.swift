// swift-tools-version:5.2

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
        .systemLibrary(
            name: "CLLVM",
            pkgConfig: "cllvm"
        ),
        .target(
            name: "KaleidoscopeLib",
            dependencies: ["CLLVM"]
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
