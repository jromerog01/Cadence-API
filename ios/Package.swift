// swift-tools-version: 6.2

import PackageDescription

#if os(Linux)
let products: [Product] = [.library(name: "CadenceKit", targets: ["CadenceKit"])]
let targets: [Target] = [
    .target(name: "CadenceKit"),
    .testTarget(name: "CadenceKitTests", dependencies: ["CadenceKit"]),
]
#else
let products: [Product] = [.library(name: "Cadence", targets: ["Cadence"])]
let targets: [Target] = [
    .target(name: "CadenceKit"),
    .target(name: "Cadence", dependencies: ["CadenceKit"]),
    .testTarget(name: "CadenceKitTests", dependencies: ["CadenceKit"]),
]
#endif

let package = Package(
    name: "Cadence",
    platforms: [.iOS(.v26)],
    products: products,
    targets: targets
)
