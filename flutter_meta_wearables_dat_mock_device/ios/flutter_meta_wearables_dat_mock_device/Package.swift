// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_meta_wearables_dat_mock_device",
    platforms: [.iOS("17.0")],
    products: [
        .library(name: "flutter-meta-wearables-dat-mock-device", targets: ["flutter_meta_wearables_dat_mock_device"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(name: "flutter_meta_wearables_dat", path: "../flutter_meta_wearables_dat")
    ],
    targets: [
        .binaryTarget(
            name: "MWDATMockDevice",
            path: "Frameworks/MWDATMockDevice.xcframework"
        ),
        .target(
            name: "flutter_meta_wearables_dat_mock_device",
            dependencies: [
                "MWDATMockDevice",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "MWDATCore", package: "flutter_meta_wearables_dat")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedLibrary("c++")
            ]
        )
    ]
)
