 // swift-tools-version: 6.3
 
import PackageDescription

let package = Package(
    name: "ToubarReplace",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ToubarReplace",
            targets: ["ToubarReplace"]
        )
    ],
    targets: [
        .target(
            name: "TouchBarPrivateAPI",
            path: "Sources/TouchBarPrivateAPI",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "ToubarReplace",
            dependencies: ["TouchBarPrivateAPI"],
            resources: [
                .process("Resources")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
