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
        // Adapty engine: StoreKit 2 + Adapty (access levels, placements, A/B-tested
        // paywalls, server-signed promotional offers, cross-platform profiles).
        .library(
            name: "TNSubscriptionAdapty",
            targets: ["TNSubscriptionAdapty"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.0.0"),
        // Adapty 4.x declares swift-tools-version 6.2, so resolving this package now needs
        // Xcode 26+. That costs shipping apps nothing: App Store Connect has only accepted
        // Xcode 26 builds since 28 April 2026.
        .package(url: "https://github.com/adaptyteam/AdaptySDK-iOS.git", from: "4.4.0"),
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
        // NOTE: depends on Adapty only — never on RevenueCat, and never on the other two
        // targets, so an app links exactly one billing SDK.
        .target(
            name: "TNSubscriptionAdapty",
            dependencies: [
                .product(name: "Adapty", package: "AdaptySDK-iOS"),
            ],
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
        .testTarget(
            name: "TNSubscriptionAdaptyTests",
            dependencies: ["TNSubscriptionAdapty"]
        ),
    ]
)
