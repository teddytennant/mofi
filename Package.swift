// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mofi",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CLua",
            path: "Sources/CLua",
            cSettings: [.define("LUA_USE_MACOSX"), .unsafeFlags(["-w"])]
        ),
        .executableTarget(
            name: "mofi",
            dependencies: ["CLua"],
            path: "Sources/mofi"
        ),
    ]
)
