// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TNSubscriptionIOS",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "TNSubscriptionIOS",
            targets: ["TNSubscriptionIOS"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "TNSubscriptionIOS",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ]
        ),
    ]
)
