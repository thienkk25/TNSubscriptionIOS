import XCTest
import UIKit
@testable import TNSubscriptionIOS

/// The engine contract — this file is IDENTICAL in all three engine test targets except for the
/// `import` line above. It uses only the shared configuration and the `TNSubscription` alias, so if
/// any engine's public surface drifts from the others, that engine's copy stops compiling.
/// (Contract của engine — file này GIỐNG HỆT nhau ở cả ba test target, chỉ khác dòng `import` ở
/// trên. Nó chỉ dùng cấu hình chung và alias `TNSubscription`, nên nếu API công khai của engine nào
/// lệch khỏi các engine khác, bản sao của engine đó sẽ không compile được.)
@MainActor
final class TNEngineContractTests: XCTestCase {

    override func setUp() async throws {
        TNSubscription.logLevel = .none
        TNSubscription.resetForTesting()
    }

    override func tearDown() async throws {
        TNSubscription.resetForTesting()
    }

    /// Every field of the shared config, set by label, compiles against this engine.
    /// (Mọi trường của config chung, gán theo nhãn, đều compile được với engine này.)
    func testTheFullSharedConfigIsAcceptedByThisEngine() {
        let config = TNSubscriptionConfig(
            apiKey: "",
            entitlements: [
                TNEntitlement(id: "Premium", productIDs: ["com.app.weekly", "com.app.yearly"]),
                TNEntitlement(id: "Sale", productIDs: ["com.app.sale"]),
            ],
            offerings: [TNOffering(identifier: "default", productIDs: ["com.app.weekly"])],
            currentOfferingIdentifier: "default",
            customerUserId: nil,
            isIAPEnabled: false,
            enableBackendIdentitySync: false,
            observerMode: false,
            attachAppAccountToken: false,
            offlineStoreKitFallback: true,
            logLevel: .none
        )

        XCTAssertEqual(config.allEntitlementIDs, ["Premium", "Sale"])
        XCTAssertEqual(config.allProductIDs, ["com.app.weekly", "com.app.yearly", "com.app.sale"])
    }

    /// The 1.2.0 call shapes — RevenueCat's and Core's — still compile against every engine.
    /// (Các kiểu gọi của 1.2.0 — của RevenueCat và Core — vẫn compile với mọi engine.)
    func testTheReleasedCallShapesStillCompile() {
        let revenueCatStyle = TNSubscriptionConfig(
            apiKey: "appl_x",
            entitlements: [TNEntitlement(id: "Premium", productIDs: ["a"])],
            isIAPEnabled: true,
            enableBackendIdentitySync: false,
            logLevel: .none
        )
        let coreStyle = TNSubscriptionConfig(
            entitlements: [TNEntitlement(id: "Premium", productIDs: ["a"])],
            offerings: [],
            currentOfferingIdentifier: nil,
            isIAPEnabled: true,
            attachAppAccountToken: false,
            logLevel: .none
        )
        let convenience = TNSubscriptionConfig(apiKey: "appl_x", productIDs: ["a", "b"])

        XCTAssertEqual(revenueCatStyle.apiKey, "appl_x")
        XCTAssertEqual(coreStyle.apiKey, "", "apiKey is optional: Core never needs one.")
        XCTAssertEqual(convenience.allEntitlementIDs, ["Premium"], "The convenience default stays 'Premium', as released.")
    }

    /// The same configure / query code runs on this engine.
    /// (Cùng một đoạn code configure / truy vấn chạy được trên engine này.)
    func testTheCommonEntryPointBehavesTheSame() {
        TNSubscription.configure(config: TNSubscriptionConfig(
            entitlements: [TNEntitlement(id: "Premium", productIDs: ["com.app.yearly"])],
            isIAPEnabled: false,
            logLevel: .none
        ))

        let engine = TNSubscription.shared!
        XCTAssertTrue(engine.isPremium)
        XCTAssertTrue(engine.hasEntitlement("Premium"))
        XCTAssertEqual(engine.entitlementState, .unlocked)
        XCTAssertEqual(engine.productIDs(for: "Premium"), ["com.app.yearly"])
    }

    /// The paywall and consumable configuration types are the shared ones.
    /// (Kiểu cấu hình paywall và consumable chính là kiểu dùng chung.)
    func testPaywallAndConsumableConfigAreShared() {
        let paywall = DefaultPaywallConfig(
            appName: "App",
            offeringIdentifier: "default",
            entitlementId: "Premium",
            showRedeemCodeButton: true,
            showSavingsBadge: false,
            showPricePerMonth: false,
            closeButtonTint: .white,
            headerTitle: "Go Pro",
            headerSubtitle: "Deeper match analysis, no ads.",
            unlockedHeaderTitle: "You're Pro",
            unlockedHeaderSubtitle: "Thanks for your support.",
            texts: [.redeemCode: "Nhập mã ưu đãi"]
        )
        let coins = TNConsumableProduct(id: "com.app.100coins", reward: 100, currency: "coins")

        XCTAssertFalse(paywall.showSavingsBadge)
        XCTAssertEqual(paywall.closeButtonTint, .white)
        XCTAssertNil(DefaultPaywallConfig().closeButtonTint, "By default the Close button is left to the system.")
        XCTAssertEqual(paywall.headerSubtitle, "Deeper match analysis, no ads.")
        let defaults = DefaultPaywallConfig()
        XCTAssertNil(defaults.headerTitle, "nil keeps the built-in copy, so apps that set nothing see no change.")
        XCTAssertNil(defaults.headerSubtitle)
        XCTAssertNil(defaults.unlockedHeaderTitle)
        XCTAssertNil(defaults.unlockedHeaderSubtitle)

        // texts: an override wins, everything else keeps its built-in text.
        XCTAssertEqual(paywall.text(.redeemCode), "Nhập mã ưu đãi")
        XCTAssertEqual(paywall.text(.restorePurchases), "Restore Purchases")
        XCTAssertEqual(defaults.text(.redeemCode), "Redeem Code")
        for key in TNPaywallText.allCases {
            XCTAssertFalse(key.defaultValue.isEmpty, "\(key) has no built-in text, so the paywall would show a blank.")
        }
        XCTAssertEqual(coins.reward, 100)

        // Compiled, never run: proves the README's presentation call exists on this engine with
        // exactly this signature. (Compile nhưng không chạy: chứng minh lời gọi trong README tồn tại
        // trên engine này với đúng chữ ký này.)
        if Bool.random() && false {
            TNSubscription.presentDefaultPaywall(from: UIViewController(), config: paywall)
            TNSubscription.presentPaywall(from: UIViewController()) { Text("Custom") }
        }
    }

    /// Every API that README lists under "the same in all three engines" exists on this engine with
    /// the same shape. Compiled, never run — README's table is only allowed to list what this test
    /// enforces.
    /// (Mọi API mà README liệt kê trong mục "giống nhau ở cả ba engine" đều tồn tại trên engine này
    /// với cùng hình dạng. Compile nhưng không chạy — bảng trong README chỉ được liệt kê những gì
    /// test này bắt buộc.)
    func testTheCommonAPISurfaceExists() async throws {
        guard Bool.random() && false else { return }

        let engine = TNSubscription.shared!
        let _: Bool = engine.isPremium
        let _: Set<String> = engine.activeEntitlements
        let _: Bool = engine.entitlementState == .unlocked
        let _: Bool = engine.hasEntitlement("Premium")
        let _: Set<String> = engine.productIDs(for: "Premium")
        let _: Bool = engine.isLoadingOfferings
        let _: Bool = engine.isPurchasing
        let _: String? = engine.offeringsError
        let _: String? = engine.entitlementError
        let _: String? = engine.currentPlanProductID
        let _: String? = engine.currentPlanDisplayName
        let _: String? = engine.currentProductID(for: "Premium")
        engine.checkSubscriptionStatus()
        engine.fetchOfferings(offeringIdentifier: nil)
        await engine.resolveEntitlement()
        await engine.loadOfferings(offeringIdentifier: nil)
        let _: Bool = try await engine.restorePurchasesAsync()
        engine.restorePurchases { (_: Result<Bool, Error>) in }
        engine.presentOfferCodeRedemption()

        let _: String = TNSubscription.clientId
        let _: String = TNSubscription.deviceId
        let _: [String: String] = TNSubscription.identityHeaders(userId: nil)
        let _: String = TNSubscription.displayName(forProductID: "com.app.yearly")
        TNSubscription.logLevel = .none
        TNSubscription.logHandler = nil

        let _ = TNDefaultPaywallView(config: DefaultPaywallConfig())

        TNConsumableManager.configure(products: [TNConsumableProduct(id: "c", reward: 1, currency: "coins")])
        let coins = TNConsumableManager.shared!
        coins.loadProducts()
        let _: Int = try await coins.purchaseAsync(productId: "c")
        let _: Int = coins.balance(for: "coins")
        let _: Bool = coins.canAfford(1, currency: "coins")
        coins.addBalance(1, for: "coins")
        let _: Bool = coins.deductBalance(1, for: "coins")
        coins.setBalance(0, for: "coins")
    }

    /// Settings this engine cannot honour are reported, never silently dropped.
    /// (Thiết lập engine này không áp dụng được sẽ được báo, không bao giờ bị bỏ qua âm thầm.)
    func testEverySettingIsHonouredBySomeEngine() {
        let everything = TNSubscriptionConfig(
            apiKey: "key",
            entitlements: [TNEntitlement(id: "Premium")],
            offerings: [TNOffering(identifier: "o", productIDs: ["a"])],
            customerUserId: "user",
            enableBackendIdentitySync: true,
            observerMode: true,
            attachAppAccountToken: true,
            offlineStoreKitFallback: false
        )
        let engines: [TNEngineKind] = [.revenueCat, .adapty, .qonversion, .storeKit]
        let warnings = engines.map { everything.ignoredSettings(for: $0) }

        // Each engine ignores something…
        XCTAssertTrue(warnings.allSatisfy { !$0.isEmpty })
        // …but a default config produces no warnings anywhere.
        let plain = TNSubscriptionConfig(entitlements: [TNEntitlement(id: "Premium")])
        XCTAssertTrue(engines.allSatisfy { plain.ignoredSettings(for: $0).isEmpty },
                      "A config that relies on nothing engine-specific must be silent on every engine.")
    }
}
