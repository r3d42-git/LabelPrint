// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LabelPrint",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LabelPrintTest", targets: ["LabelPrintTest"]),
        .executable(name: "LabelPrintCheck", targets: ["LabelPrintCheck"])
    ],
    targets: [
        .target(name: "LabelTestCore"),
        .executableTarget(name: "LabelPrintTest", dependencies: ["LabelTestCore"],
                          linkerSettings: [.linkedFramework("IOBluetooth"), .linkedFramework("CoreBluetooth")]),
        .executableTarget(name: "LabelPrintCheck", dependencies: ["LabelTestCore"]),
        .testTarget(name: "LabelTestCoreTests", dependencies: ["LabelTestCore"])
    ]
)
