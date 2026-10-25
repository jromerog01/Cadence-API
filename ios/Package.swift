// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Cadence",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Cadence", targets: ["Cadence"]),
        .library(name: "CadenceShare", targets: ["CadenceShare"]),
    ],
    dependencies: [.package(path: "CadenceKit")],
    targets: [
        .target(name: "Cadence", dependencies: ["CadenceKit"],
                linkerSettings: [.unsafeFlags(["-Xlinker", "-headerpad", "-Xlinker", "0x1000", "-Xlinker", "-adhoc_codesign"])]),
        .target(name: "CadenceShare", dependencies: ["CadenceKit"],
                linkerSettings: [.unsafeFlags(["-Xlinker", "-headerpad", "-Xlinker", "0x1000", "-Xlinker", "-adhoc_codesign"])]),
    ]
)
