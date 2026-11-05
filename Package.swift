// swift-tools-version: 6.0
import PackageDescription

// Layers, each a module, so the compiler enforces the dependency rule:
//   AppUI ──▶ AppDomain ◀── AppData
// Only the executable (the composition root) sees all three.
let package = Package(
    name: "Barsong",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Barsong", targets: ["Barsong"]),
    ],
    targets: [
        .target(name: "AppDomain", path: "Sources/Domain"),
        .target(name: "AppData", dependencies: ["AppDomain"], path: "Sources/Data"),
        .target(name: "AppUI", dependencies: ["AppDomain"], path: "Sources/UI"),
        .executableTarget(
            name: "Barsong",
            dependencies: ["AppDomain", "AppData", "AppUI"],
            path: "Sources/App"
        ),
        .testTarget(name: "DomainTests", dependencies: ["AppDomain"], path: "Tests/DomainTests"),
        .testTarget(name: "DataTests", dependencies: ["AppData", "AppDomain"], path: "Tests/DataTests"),
    ],
    swiftLanguageModes: [.v5]
)
