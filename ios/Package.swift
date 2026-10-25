// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Cadence",
    platforms: [.iOS(.v26)],
    products: [.library(name: "Cadence", targets: ["Cadence"])],
    dependencies: [.package(path: "CadenceKit")],
    targets: [.target(name: "Cadence", dependencies: ["CadenceKit"])]
)
