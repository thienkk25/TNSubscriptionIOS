import XCTest
import Qonversion
@testable import TNSubscriptionQonversion

/// Unit tests for the Qonversion engine's own logic.
/// (Unit test cho phần logic riêng của engine Qonversion.)
///
/// Qonversion's entitlement objects are filled in by the SDK from server responses, so the mapping
/// rules were extracted into functions over Qonversion's enums, which tests can construct directly.
/// (Object entitlement của Qonversion do SDK điền từ phản hồi của server, nên quy tắc mapping được
/// tách thành hàm nhận enum của Qonversion — loại mà test tạo được trực tiếp.)

// MARK: - Mapping Rules

final class TNQonversionMappingTests: XCTestCase {

    func testStoreSourcesMap() {
        XCTAssertEqual(TNStore.from(qonversionSource: .appStore), .appStore)
        XCTAssertEqual(TNStore.from(qonversionSource: .playStore), .playStore)
        XCTAssertEqual(TNStore.from(qonversionSource: .stripe), .web)
        XCTAssertEqual(TNStore.from(qonversionSource: .paddle), .web)
        XCTAssertEqual(TNStore.from(qonversionSource: .manual), .promotional)
        XCTAssertEqual(TNStore.from(qonversionSource: .unknown), .other)
    }

    func testRenewIntent() {
        XCTAssertTrue(tnWillRenew(.willRenew))
        XCTAssertTrue(tnWillRenew(.billingIssue), "The store is retrying — the user has not turned renewal off.")
        XCTAssertTrue(tnWillRenew(.unknown), "Claiming a healthy subscription is about to lapse is the worse error.")
        XCTAssertFalse(tnWillRenew(.cancelled))
        XCTAssertFalse(tnWillRenew(.nonRenewable))
    }

    func testIssueClassification() {
        let past = Date().addingTimeInterval(-3600)
        let future = Date().addingTimeInterval(3600)

        XCTAssertNil(TNSubscriptionIssue.classify(renewState: .willRenew, isActive: true, expirationDate: future))
        XCTAssertEqual(TNSubscriptionIssue.classify(renewState: .billingIssue, isActive: true, expirationDate: future), .gracePeriod,
                       "A billing problem while access continues is a grace period.")
        XCTAssertEqual(TNSubscriptionIssue.classify(renewState: .billingIssue, isActive: false, expirationDate: past), .billingRetry)
        XCTAssertEqual(TNSubscriptionIssue.classify(renewState: .cancelled, isActive: false, expirationDate: past), .expired)
        XCTAssertNil(TNSubscriptionIssue.classify(renewState: .cancelled, isActive: true, expirationDate: future),
                     "Cancelled but not yet expired is not a problem — the user keeps access until the end of the period.")
    }

    func testPeriodType() {
        XCTAssertEqual(TNPeriodType.from(hasTrialStart: true, renewsCount: 0, grantType: .purchase), .trial)
        XCTAssertEqual(TNPeriodType.from(hasTrialStart: true, renewsCount: 2, grantType: .purchase), .normal,
                       "A trial that has renewed is now paying.")
        XCTAssertEqual(TNPeriodType.from(hasTrialStart: false, renewsCount: 0, grantType: .purchase), .normal)
        XCTAssertEqual(TNPeriodType.from(hasTrialStart: false, renewsCount: 0, grantType: .offerCode), .promotional)
    }

    func testOwnership() {
        XCTAssertEqual(TNOwnershipType.from(grantType: .purchase), .purchased)
        XCTAssertEqual(TNOwnershipType.from(grantType: .familySharing), .familyShared)
        XCTAssertEqual(TNOwnershipType.from(grantType: .manual), .unknown)
    }

    func testOfferingsAreHonouredHereUnlikeAdaptyAndRevenueCat() {
        // Qonversion deprecated its own offerings, so this engine reads TNOffering from the config.
        let config = TNSubscriptionConfig(
            apiKey: "key",
            entitlements: [TNEntitlement(id: "premium", productIDs: ["a"])],
            offerings: [TNOffering(identifier: "main", productIDs: ["a"])],
            observerMode: true,
            offlineStoreKitFallback: false
        )
        XCTAssertTrue(config.ignoredSettings(for: .qonversion).isEmpty,
                      "offerings, observerMode and offlineStoreKitFallback are all honoured by Qonversion.")
        XCTAssertFalse(config.ignoredSettings(for: .adapty).isEmpty, "Adapty ignores declared offerings.")
    }
}

// MARK: - Engine Without Qonversion

/// Behaviour that must hold with no reachable Qonversion project.
/// (Hành vi phải đúng khi không có dự án Qonversion nào kết nối được.)
@MainActor
final class TNQonversionEngineTests: XCTestCase {

    override func setUp() async throws {
        TNSubscriptionQonversion.logLevel = .none
        TNSubscriptionQonversion.resetForTesting()
    }

    override func tearDown() async throws {
        TNSubscriptionQonversion.resetForTesting()
    }

    func testAnotherVendorsKeyIsNotLaunchedAndDegradesToLocked() async throws {
        TNSubscriptionQonversion.configure(config: TNSubscriptionConfig(
            apiKey: "appl_this_is_a_revenuecat_key",
            entitlements: [TNEntitlement(id: "premium", productIDs: ["com.app.yearly"])]
        ))
        let engine = try XCTUnwrap(TNSubscriptionQonversion.shared)

        await engine.resolveEntitlement()

        XCTAssertFalse(engine.isQonversionLaunched, "A key from another vendor must never reach Qonversion.")
        XCTAssertEqual(engine.entitlementState, .locked)
        XCTAssertEqual(engine.customerInfo?.source, .storeKitFallback)
    }

    func testOfferingsAreRefusedReadablyWhenNotLaunched() async throws {
        TNSubscriptionQonversion.configure(config: TNSubscriptionConfig(
            apiKey: "",
            entitlements: [TNEntitlement(id: "premium", productIDs: ["com.app.yearly"])]
        ))
        let engine = try XCTUnwrap(TNSubscriptionQonversion.shared)

        await engine.loadOfferings()

        XCTAssertTrue(engine.availablePackages.isEmpty)
        XCTAssertNotNil(engine.offeringsError, "The paywall needs something to show instead of a blank list.")
    }

    func testIdentifyIsRefusedWhenNotLaunched() async throws {
        TNSubscriptionQonversion.configure(config: TNSubscriptionConfig(
            apiKey: "",
            entitlements: [TNEntitlement(id: "premium")]
        ))
        let engine = try XCTUnwrap(TNSubscriptionQonversion.shared)

        do {
            try await engine.identify("user-1")
            XCTFail("identify must not silently succeed without Qonversion.")
        } catch TNPurchaseError.notLaunched {
            // Expected.
        }
    }

    func testDisablingIAPUnlocksEverythingWithoutStartingQonversion() async throws {
        TNSubscriptionQonversion.configure(config: TNSubscriptionConfig(
            entitlements: [TNEntitlement(id: "premium"), TNEntitlement(id: "pro")],
            isIAPEnabled: false
        ))
        let engine = try XCTUnwrap(TNSubscriptionQonversion.shared)

        XCTAssertTrue(engine.isPremium)
        XCTAssertEqual(engine.activeEntitlements, ["premium", "pro"])
        XCTAssertFalse(engine.isQonversionLaunched)
    }

    func testWarmStartUnlocksFromAnUnexpiredCacheEntry() async throws {
        UserDefaults.standard.set(["premium": Date.distantFuture.timeIntervalSince1970], forKey: "tn_qonversion_cachedEntitlements")

        TNSubscriptionQonversion.configure(config: TNSubscriptionConfig(
            apiKey: "",
            entitlements: [TNEntitlement(id: "premium")]
        ))
        let engine = try XCTUnwrap(TNSubscriptionQonversion.shared)

        XCTAssertEqual(engine.entitlementState, .unlocked, "Read before any await — the window a paywall would flash in.")
    }

    func testWarmStartIgnoresAnExpiredCacheEntry() async throws {
        UserDefaults.standard.set(["premium": Date().addingTimeInterval(-60).timeIntervalSince1970], forKey: "tn_qonversion_cachedEntitlements")

        TNSubscriptionQonversion.configure(config: TNSubscriptionConfig(
            apiKey: "",
            entitlements: [TNEntitlement(id: "premium")]
        ))
        let engine = try XCTUnwrap(TNSubscriptionQonversion.shared)

        XCTAssertEqual(engine.entitlementState, .unknown)
        XCTAssertFalse(engine.isPremium)
    }
}
