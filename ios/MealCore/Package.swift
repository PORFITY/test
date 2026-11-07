// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MealCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "MealCore", targets: ["MealCore"])],
    targets: [
        .target(name: "MealCore", resources: [.process("Resources")]),
        .testTarget(name: "MealCoreTests", dependencies: ["MealCore"]),
    ]
)
