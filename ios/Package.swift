// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_meta_wearables_dat",
    platforms: [.iOS("17.0")],
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
        .target(
            name: "flutter_meta_wearables_dat",
            dependencies: [
                "MWDATCore",
                "MWDATCamera"
            ],
            path: "Classes",
            resources: []
        )
    ]
)
