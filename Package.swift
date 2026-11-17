// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TNSubscriptionIOS",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        // Full engine: StoreKit 2 + RevenueCat (server-side receipt validation,
        // dashboard offerings, cross-platform entitlements, virtual currencies).
        .library(
            name: "TNSubscriptionIOS",
            targets: ["TNSubscriptionIOS"]
        ),
        // Core engine: Apple StoreKit 2 ONLY. Zero third-party dependencies,
        // no network calls to any vendor, no API key.
        .library(
            name: "TNSubscriptionCore",
            targets: ["TNSubscriptionCore"]
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
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        // NOTE: no `dependencies:` on purpose — this target must never link RevenueCat.
        .target(
            name: "TNSubscriptionCore",
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "TNSubscriptionIOSTests",
            dependencies: ["TNSubscriptionIOS"]
        ),
        // Pure value logic only. StoreKit refuses to serve products to a SwiftPM test
        // runner (it has no app bundle), so the purchase and entitlement paths live in
        // IntegrationTests/ instead, hosted by a real app target.
        .testTarget(
            name: "TNSubscriptionCoreTests",
            dependencies: ["TNSubscriptionCore"]
        ),
    ]
)
