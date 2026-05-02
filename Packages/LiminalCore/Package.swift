// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiminalCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "LiminalCore", targets: ["LiminalCore"]),
        .library(name: "LiminalText", targets: ["LiminalText"]),
        .library(name: "LiminalSyntax", targets: ["LiminalSyntax"]),
        .library(name: "LiminalModel", targets: ["LiminalModel"]),
        .library(name: "LiminalSchema", targets: ["LiminalSchema"]),
        .library(name: "LiminalLowering", targets: ["LiminalLowering"]),
        .library(name: "LiminalSurfaces", targets: ["LiminalSurfaces"]),
        .library(name: "LiminalPrinting", targets: ["LiminalPrinting"]),
        .library(name: "LiminalWorkspace", targets: ["LiminalWorkspace"]),
        .library(name: "LiminalEditor", targets: ["LiminalEditor"]),
        .library(name: "LiminalRender", targets: ["LiminalRender"]),
        .executable(name: "liminal", targets: ["liminal-cli"])
    ],
    targets: [
        .target(name: "LiminalText"),
        .target(
            name: "LiminalSyntax",
            dependencies: ["LiminalText"]
        ),
        .target(
            name: "LiminalModel",
            dependencies: ["LiminalText"]
        ),
        .target(
            name: "LiminalSchema",
            dependencies: ["LiminalModel"]
        ),
        .target(
            name: "LiminalLowering",
            dependencies: ["LiminalModel", "LiminalSyntax"]
        ),
        .target(
            name: "LiminalSurfaces",
            dependencies: ["LiminalModel", "LiminalSyntax"]
        ),
        .target(
            name: "LiminalPrinting",
            dependencies: ["LiminalModel", "LiminalSurfaces"]
        ),
        .target(
            name: "LiminalWorkspace",
            dependencies: ["LiminalModel", "LiminalSchema", "LiminalText"]
        ),
        .target(
            name: "LiminalEditor",
            dependencies: ["LiminalLowering", "LiminalSyntax", "LiminalWorkspace"]
        ),
        .target(
            name: "LiminalRender",
            dependencies: ["LiminalModel"]
        ),
        .target(
            name: "LiminalCore",
            dependencies: [
                "LiminalText",
                "LiminalSyntax",
                "LiminalModel",
                "LiminalSchema",
                "LiminalLowering",
                "LiminalSurfaces",
                "LiminalPrinting",
                "LiminalWorkspace",
                "LiminalEditor",
                "LiminalRender"
            ]
        ),
        .executableTarget(
            name: "liminal-cli",
            dependencies: ["LiminalCore"]
        ),
        .testTarget(
            name: "LiminalTextTests",
            dependencies: ["LiminalText"]
        ),
        .testTarget(
            name: "LiminalModelTests",
            dependencies: ["LiminalModel"]
        ),
        .testTarget(
            name: "LiminalScaffoldTests",
            dependencies: ["LiminalCore"]
        )
    ]
)
