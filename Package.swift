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
        // Qonversion engine: StoreKit 2 + Qonversion (server-validated entitlements,
        // cross-platform profiles, analytics), with offerings declared in code because
        // Qonversion has deprecated its own.
        .library(
            name: "TNSubscriptionQonversion",
            targets: ["TNSubscriptionQonversion"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.0.0"),
        // Adapty 4.x declares swift-tools-version 6.2, so resolving this package now needs
        // Xcode 26+. That costs shipping apps nothing: App Store Connect has only accepted
        // Xcode 26 builds since 28 April 2026.
        .package(url: "https://github.com/adaptyteam/AdaptySDK-iOS.git", from: "4.4.0"),
        // swift-tools-version 5.9 and iOS 13+, so it adds no toolchain requirement.
        .package(url: "https://github.com/qonversion/qonversion-ios-sdk.git", from: "6.18.0"),
    ],
    targets: [
        // The configuration types every engine shares: TNSubscriptionConfig, TNEntitlement,
        // TNOffering, TNLogLevel, DefaultPaywallConfig, TNConsumableProduct. One copy, so the
        // three engines cannot drift apart — switching engine is only an `import` change.
        // No dependencies, and not a product: each engine re-exports it.
        .target(
            name: "TNSubscriptionShared"
        ),
        .target(
            name: "TNSubscriptionIOS",
            dependencies: [
                "TNSubscriptionShared",
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        // NOTE: only the shared module — this target must never link a vendor SDK.
        .target(
            name: "TNSubscriptionCore",
            dependencies: ["TNSubscriptionShared"],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        // NOTE: depends on Adapty only — never on RevenueCat, and never on the other two
        // targets, so an app links exactly one billing SDK.
        .target(
            name: "TNSubscriptionAdapty",
            dependencies: [
                "TNSubscriptionShared",
                .product(name: "Adapty", package: "AdaptySDK-iOS"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        // NOTE: `QonversionNoIdfa`, not `Qonversion`. The default product also links an IDFA
        // reader (AdSupport), which changes an app's App Store privacy answers; an app that wants
        // IDFA can add `QonversionIDFA` itself. Depends on no other engine.
        .target(
            name: "TNSubscriptionQonversion",
            dependencies: [
                "TNSubscriptionShared",
                .product(name: "QonversionNoIdfa", package: "qonversion-ios-sdk"),
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
        .testTarget(
            name: "TNSubscriptionQonversionTests",
            dependencies: ["TNSubscriptionQonversion"]
        ),
        // Logic that lives once, in the shared module — tested once, here.
        .testTarget(
            name: "TNSubscriptionSharedTests",
            dependencies: ["TNSubscriptionShared"]
        ),
    ]
)
