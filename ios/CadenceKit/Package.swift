// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CadenceKit",
    platforms: [.iOS(.v26)],
    products: [.library(name: "CadenceKit", targets: ["CadenceKit"])],
    targets: [
        .target(name: "CadenceKit"),
        .testTarget(name: "CadenceKitTests", dependencies: ["CadenceKit"], resources: [.copy("Fixtures")]),
    ]
)
