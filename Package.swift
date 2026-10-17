// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EnglishInput",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "EnglishInput", targets: ["EnglishInput"]),
        .executable(name: "english-input-cli", targets: ["EnglishInputCLI"]),
        .executable(name: "english-input-dict", targets: ["EnglishInputDict"]),
    ],
    targets: [
        .target(name: "EnglishInputCore"),
        .executableTarget(
            name: "EnglishInput",
            dependencies: ["EnglishInputCore"],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("InputMethodKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "EnglishInputCLI",
            dependencies: ["EnglishInputCore"]
        ),
        .executableTarget(
            name: "EnglishInputDict",
            dependencies: ["EnglishInputCore"]
        ),
        .testTarget(
            name: "EnglishInputCoreTests",
            dependencies: ["EnglishInputCore"]
        ),
    ]
)
