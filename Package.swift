// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TaskLock",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TaskLock", targets: ["TaskLock"]), .library(name: "TaskLockCore", targets: ["TaskLockCore"])],
    targets: [
        .target(name: "TaskLockCore"),
        .executableTarget(name: "TaskLock", dependencies: ["TaskLockCore"]),
        .testTarget(name: "TaskLockCoreTests", dependencies: ["TaskLockCore"])
    ],
    swiftLanguageModes: [.v5]
)
