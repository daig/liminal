// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "LiminalCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "LiminalCore", targets: ["LiminalCore"]),
        .library(name: "LiminalSyntax", targets: ["LiminalSyntax"]),
        .library(name: "LiminalSemantics", targets: ["LiminalSemantics"]),
        .library(name: "LiminalWorkspace", targets: ["LiminalWorkspace"]),
        .library(name: "LiminalEditor", targets: ["LiminalEditor"]),
        .library(name: "LiminalRendering", targets: ["LiminalRendering"]),
        .executable(name: "liminal", targets: ["liminal-cli"])
    ],
    dependencies: [
        .package(path: "../../../cambium")
    ],
    targets: [
        .target(
            name: "LiminalSyntax",
            dependencies: [
                .product(name: "Cambium", package: "cambium")
            ]
        ),
        .target(
            name: "LiminalSemantics",
            dependencies: [
                "LiminalSyntax",
                .product(name: "Cambium", package: "cambium")
            ]
        ),
        .target(
            name: "LiminalWorkspace",
            dependencies: [
                "LiminalSemantics",
                "LiminalSyntax",
                .product(name: "CambiumCore", package: "cambium")
            ]
        ),
        .target(
            name: "LiminalEditor",
            dependencies: [
                "LiminalSemantics",
                "LiminalSyntax",
                "LiminalWorkspace",
                .product(name: "Cambium", package: "cambium")
            ]
        ),
        .target(
            name: "LiminalRendering",
            dependencies: ["LiminalSemantics"]
        ),
        .target(
            name: "LiminalCore",
            dependencies: [
                "LiminalSyntax",
                "LiminalSemantics",
                "LiminalWorkspace",
                "LiminalEditor",
                "LiminalRendering"
            ]
        ),
        .executableTarget(
            name: "liminal-cli",
            dependencies: ["LiminalCore"]
        ),
        .testTarget(
            name: "LiminalSyntaxTests",
            dependencies: [
                "LiminalSyntax",
                .product(name: "CambiumCore", package: "cambium")
            ]
        ),
        .testTarget(
            name: "LiminalSemanticsTests",
            dependencies: ["LiminalSemantics"]
        ),
        .testTarget(
            name: "LiminalWorkspaceTests",
            dependencies: ["LiminalWorkspace"]
        ),
        .testTarget(
            name: "LiminalScaffoldTests",
            dependencies: ["LiminalCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
