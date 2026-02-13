// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_meta_wearables_dat",
    platforms: [.iOS("14.0")],
    products: [
        .library(name: "flutter_meta_wearables_dat", targets: ["flutter_meta_wearables_dat"])
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "MWDATCore",
            path: "Frameworks/MWDATCore.xcframework"
        ),
        .binaryTarget(
            name: "MWDATCamera",
            path: "Frameworks/MWDATCamera.xcframework"
        ),
        .binaryTarget(
            name: "MWDATMockDevice",
            path: "Frameworks/MWDATMockDevice.xcframework"
        ),
        .target(
            name: "flutter_meta_wearables_dat",
            dependencies: [
                "MWDATCore",
                "MWDATCamera",
                "MWDATMockDevice"
            ],
            path: "Classes",
            resources: []
        )
    ]
)

