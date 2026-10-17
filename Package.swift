// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fluent",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Fluent", targets: ["Fluent"]),
        .executable(name: "fluent-cli", targets: ["FluentCLI"]),
        .executable(name: "fluent-dict", targets: ["FluentDict"]),
        .executable(name: "FluentSettings", targets: ["FluentSettings"]),
    ],
    targets: [
        .target(name: "FluentCore"),
        .executableTarget(
            name: "Fluent",
            dependencies: ["FluentCore"],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("InputMethodKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "FluentSettings",
            dependencies: ["FluentCore"],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("WebKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "FluentCLI",
            dependencies: ["FluentCore"]
        ),
        .executableTarget(
            name: "FluentDict",
            dependencies: ["FluentCore"]
        ),
        .testTarget(
            name: "FluentCoreTests",
            dependencies: ["FluentCore"]
        ),
    ]
)
