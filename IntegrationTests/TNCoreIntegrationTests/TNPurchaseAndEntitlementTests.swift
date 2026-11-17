import XCTest
import StoreKit
import StoreKitTest
@testable import TNSubscriptionCore

/// The paths that decide whether a paying user gets what they paid for.
/// (Những luồng quyết định việc người đã trả tiền có nhận được đúng thứ họ mua hay không.)
@MainActor
final class TNPurchaseAndEntitlementTests: TNCoreIntegrationTestCase {

    // MARK: - Cold State

    func testNoPurchaseResolvesToLockedNotUnknown() async {
        let core = await makeCore()

        XCTAssertEqual(core.entitlementState, .locked, "After a completed check, the state must be a definite .locked.")
        XCTAssertFalse(core.isPremium)
        XCTAssertTrue(core.activeEntitlements.isEmpty)
        XCTAssertNil(core.entitlementError, "Nothing failed, so there is no error to report.")
    }

    func testCustomerInfoIsEmptyButPresentWithNoPurchases() async {
        let core = await makeCore()

        let info = core.customerInfo
        XCTAssertNotNil(info)
        XCTAssertFalse(info?.hasActiveEntitlement ?? true)
        XCTAssertTrue(info?.allPurchasedProductIdentifiers.isEmpty ?? false)
    }

    // MARK: - Purchase Unlocks

    func testPurchasingASubscriptionUnlocksItsEntitlement() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.monthly, with: core)

        XCTAssertTrue(core.isPremium)
        XCTAssertEqual(core.entitlementState, .unlocked)
        XCTAssertEqual(core.activeEntitlements, ["Premium"])
        XCTAssertEqual(core.currentPlanProductID, TestProduct.monthly)
    }

    func testOneProductCanGrantSeveralEntitlements() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.yearly, with: core)

        XCTAssertEqual(core.activeEntitlements, ["Premium", "Sale"], "The yearly plan is listed under both entitlements.")
        XCTAssertTrue(core.hasEntitlement("Sale"))
        XCTAssertEqual(core.currentProductID(for: "Sale"), TestProduct.yearly)
    }

    func testPurchaseIsVisibleInTheCustomerInfoSnapshot() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.yearly, with: core)

        let info = try XCTUnwrap(core.customerInfo)
        XCTAssertTrue(info.hasActiveEntitlement)
        XCTAssertTrue(info.activeSubscriptions.contains(TestProduct.yearly))
        XCTAssertTrue(info.allPurchasedProductIdentifiers.contains(TestProduct.yearly))
        XCTAssertNotNil(info.latestExpirationDate)
        XCTAssertNotNil(info.originalPurchaseDate)
    }

    func testSubscriptionEntitlementReportsExpiryAndRenewalIntent() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.yearly, with: core)

        let entitlement = try XCTUnwrap(core.entitlementInfo(for: "Premium"))
        XCTAssertTrue(entitlement.isActive)
        XCTAssertEqual(entitlement.productIdentifier, TestProduct.yearly)
        XCTAssertNotNil(entitlement.expirationDate, "An auto-renewable subscription always has an expiry.")
        XCTAssertTrue(entitlement.willRenew, "A fresh subscription renews unless the user turns it off.")
        XCTAssertNil(entitlement.issue, "A fresh subscription has no billing problem.")
        XCTAssertTrue(entitlement.isSandbox, "Every StoreKitTest transaction is a sandbox one.")
    }

    func testLifetimePurchaseHasNoExpiry() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.lifetime, with: core)

        let entitlement = try XCTUnwrap(core.entitlementInfo(for: "Premium"))
        XCTAssertTrue(entitlement.isActive)
        XCTAssertNil(entitlement.expirationDate, "A non-consumable never expires.")
        XCTAssertFalse(entitlement.willRenew, "There is nothing to renew.")
        XCTAssertNil(entitlement.daysRemaining)

        let info = try XCTUnwrap(core.customerInfo)
        XCTAssertTrue(info.nonSubscriptionProductIdentifiers.contains(TestProduct.lifetime))
    }

    func testLifetimeBeatsASubscriptionForTheSameEntitlement() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.weekly, with: core)
        XCTAssertNotNil(core.entitlementInfo(for: "Premium")?.expirationDate)

        try await purchase(TestProduct.lifetime, with: core)

        let entitlement = try XCTUnwrap(core.entitlementInfo(for: "Premium"))
        XCTAssertNil(
            entitlement.expirationDate,
            "Owning both, the engine must report the lifetime grant: it is the one that never lapses."
        )
    }

    func testDaysRemainingTracksTheExpiryDate() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.yearly, with: core)

        let days = try XCTUnwrap(core.entitlementInfo(for: "Premium")?.daysRemaining)
        XCTAssertGreaterThan(days, 0)
    }

    // MARK: - Introductory Offers

    func testFreeTrialIsOfferedBeforeItHasBeenUsed() async throws {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        let monthly = try XCTUnwrap(core.availablePackages.first { $0.productIdentifier == TestProduct.monthly })
        XCTAssertTrue(core.isEligibleForIntroOffer(package: monthly))

        let offer = try XCTUnwrap(core.introOffer(for: monthly))
        XCTAssertEqual(offer.paymentMode, .freeTrial)
        XCTAssertEqual(offer.type, .introductory)
        XCTAssertEqual(core.introOfferSummary(for: monthly), "3 Days Free Trial")
    }

    func testPlansWithoutAnIntroOfferReportSoRatherThanIneligible() async throws {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        XCTAssertEqual(core.introEligibility[TestProduct.yearly], .noIntroOfferExists)
        let yearly = try XCTUnwrap(core.availablePackages.first { $0.productIdentifier == TestProduct.yearly })
        XCTAssertNil(core.introOffer(for: yearly))
    }

    func testTrialBecomesIneligibleAcrossTheWholeGroupOnceUsed() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.monthly, with: core)

        await core.loadOfferings(offeringIdentifier: "default")
        await core.checkIntroEligibility()

        let monthly = try XCTUnwrap(core.availablePackages.first { $0.productIdentifier == TestProduct.monthly })
        XCTAssertFalse(
            core.isEligibleForIntroOffer(package: monthly),
            "Apple scopes intro eligibility to the subscription group, so a used trial must not be offered again."
        )
        XCTAssertNil(core.introOffer(for: monthly), "A 'Start Free Trial' button built on this must disappear.")
    }

    func testPurchasingWithAFreeTrialIsReportedAsTheTrialPeriod() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.monthly, with: core)

        let entitlement = try XCTUnwrap(core.entitlementInfo(for: "Premium"))
        XCTAssertEqual(
            entitlement.periodType, .trial,
            "A free-trial purchase must read as .trial, not .intro — that is what tells a paywall it is not yet paid."
        )
    }

    // MARK: - Promotional Offers

    func testPromotionalOffersAreReadFromTheProduct() async throws {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        let weekly = try XCTUnwrap(core.availablePackages.first { $0.productIdentifier == TestProduct.weekly })
        let offers = core.promotionalOffers(for: weekly)

        XCTAssertEqual(offers.count, 1)
        XCTAssertEqual(offers.first?.offerIdentifier, "winback_50")
        XCTAssertEqual(offers.first?.type, .promotional)
        XCTAssertEqual(offers.first?.paymentMode, .payAsYouGo)
    }

    func testPromotionalPurchaseFailsLoudlyWithNoSignerInstalled() async throws {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        let weekly = try XCTUnwrap(core.availablePackages.first { $0.productIdentifier == TestProduct.weekly })
        let offer = try XCTUnwrap(core.promotionalOffers(for: weekly).first)

        do {
            try await core.purchaseAsync(package: weekly, promotionalOffer: offer)
            XCTFail("A promotional offer cannot be redeemed without a server signature; this must throw.")
        } catch TNPurchaseError.promotionalOfferSignerMissing {
            // The documented outcome.
        } catch {
            XCTFail("Expected .promotionalOfferSignerMissing, got \(error).")
        }
    }

    func testIntroOfferCannotBeRedeemedThroughThePromotionalPath() async throws {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        let monthly = try XCTUnwrap(core.availablePackages.first { $0.productIdentifier == TestProduct.monthly })
        let intro = try XCTUnwrap(core.introOffer(for: monthly))

        do {
            try await core.purchaseAsync(package: monthly, promotionalOffer: intro)
            XCTFail("Apple applies introductory offers itself; routing one through the promotional path must be refused.")
        } catch TNPurchaseError.offerNotApplicable(let type) {
            XCTAssertEqual(type, .introductory)
        } catch {
            XCTFail("Expected .offerNotApplicable, got \(error).")
        }
    }

    // MARK: - Losing Access

    func testExpiredSubscriptionLocksAgain() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.monthly, with: core)
        XCTAssertTrue(core.isPremium)

        // Expiring alone is not enough: auto-renew is on by default, so StoreKit immediately
        // issues a renewal and the user stays entitled — correctly. Cancelling first is what
        // actually makes a subscription lapse.
        try lapse(TestProduct.monthly)

        await waitUntilResolved(core, "the lapsed subscription to lock the app again") {
            !core.isPremium
        }
        XCTAssertEqual(core.entitlementState, .locked)
        XCTAssertTrue(core.activeEntitlements.isEmpty)
    }

    func testRefundedPurchaseLosesTheEntitlement() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.lifetime, with: core)
        XCTAssertTrue(core.isPremium)

        let transaction = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == TestProduct.lifetime }
        )
        try session.refundTransaction(identifier: UInt(transaction.identifier))

        await waitUntilResolved(core, "the refund to revoke access") { !core.isPremium }
        XCTAssertFalse(core.isPremium, "A refunded purchase must revoke access.")
    }

    // MARK: - Restore

    func testRestoreFindsAnExistingPurchase() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.yearly, with: core)

        let restored = try await core.restorePurchasesAsync()

        XCTAssertTrue(restored)
        XCTAssertTrue(core.isPremium)
    }

    func testRestoreReportsHonestlyWhenThereIsNothingToRestore() async throws {
        let core = await makeCore()

        let restored = try await core.restorePurchasesAsync()

        XCTAssertFalse(restored, "Claiming a successful restore with no purchase would just confuse the user.")
        XCTAssertFalse(core.isPremium)
    }

    // MARK: - External Transactions

    func testAPurchaseMadeOutsideTheAppUnlocksViaTransactionUpdates() async throws {
        let core = await makeCore()
        XCTAssertFalse(core.isPremium)

        // Simulates a renewal, another device, or an Ask-to-Buy approval landing.
        // The `identifier:` overload is the current Swift API but is iOS 17+, and this package
        // supports iOS 16, so the deprecated call stays as the fallback.
        if #available(iOS 17.0, *) {
            _ = try await session.buyProduct(identifier: TestProduct.yearly)
        } else {
            try session.buyProduct(productIdentifier: TestProduct.yearly)
        }

        await waitUntil("Transaction.updates to unlock the entitlement") { core.isPremium }
        XCTAssertTrue(core.hasEntitlement("Premium"))
    }

    // MARK: - Warm Start

    func testSecondLaunchUnlocksSynchronouslyFromCache() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.yearly, with: core)
        XCTAssertTrue(core.isPremium)

        // Simulate relaunching the app with the cache intact, and read the state *before*
        // awaiting anything — that is the window in which a paywall would otherwise flash.
        TNSubscriptionCore.resetForTesting(preserveCache: true)
        TNSubscriptionCore.configure(config: TNSubscriptionConfig(
            entitlements: [TNEntitlement(id: "Premium", productIDs: TestProduct.premiumProducts)]
        ))
        let relaunched = TNSubscriptionCore.shared!

        XCTAssertEqual(relaunched.entitlementState, .unlocked, "A paying user must not see .unknown on a warm start.")
        XCTAssertTrue(relaunched.isPremium)
        XCTAssertTrue(relaunched.activeEntitlements.contains("Premium"))
    }

    /// Regression guard: a lifetime grant has no expiry date, and storing that as `NSNull`
    /// made UserDefaults reject the entire cache write, so lifetime customers got no warm
    /// start at all. The subscription version of this test passed throughout, because a
    /// subscription always has a real timestamp.
    /// (Chặn hồi quy: quyền lợi vĩnh viễn không có ngày hết hạn, và lưu nó bằng `NSNull` khiến
    /// UserDefaults từ chối toàn bộ lần ghi cache, nên người mua vĩnh viễn không hề được warm
    /// start. Bản test với subscription vẫn pass suốt, vì subscription luôn có timestamp thật.)
    func testLifetimePurchaseIsAlsoCachedForTheWarmStart() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.lifetime, with: core)
        XCTAssertTrue(core.isPremium)

        let cache = UserDefaults.standard.dictionary(forKey: "tn_core_cachedEntitlements")
        XCTAssertNotNil(cache, "A lifetime purchase must be cached, or every cold launch flickers the paywall at a paying customer.")
        XCTAssertNotNil(cache?["Premium"] as? Double, "The cached value must be a property-list type.")

        TNSubscriptionCore.resetForTesting(preserveCache: true)
        TNSubscriptionCore.configure(config: TNSubscriptionConfig(
            entitlements: [TNEntitlement(id: "Premium", productIDs: TestProduct.premiumProducts)]
        ))

        XCTAssertEqual(TNSubscriptionCore.shared.entitlementState, .unlocked)
        XCTAssertTrue(TNSubscriptionCore.shared.isPremium)
    }

    func testWarmStartRefusesAnExpiredCacheEntry() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.monthly, with: core)

        // Backdate the cached expiry to the past: exactly the stale data that must not
        // revive a lapsed subscription.
        UserDefaults.standard.set(
            ["Premium": Date().addingTimeInterval(-3600).timeIntervalSince1970],
            forKey: "tn_core_cachedEntitlements"
        )

        TNSubscriptionCore.resetForTesting(preserveCache: true)
        TNSubscriptionCore.configure(config: TNSubscriptionConfig(
            entitlements: [TNEntitlement(id: "Premium", productIDs: TestProduct.premiumProducts)]
        ))
        let relaunched = TNSubscriptionCore.shared!

        XCTAssertEqual(relaunched.entitlementState, .unknown, "An expired cache entry must not unlock anything.")
        XCTAssertFalse(relaunched.isPremium)
    }

    func testCacheIsClearedWhenTheEntitlementGoesAway() async throws {
        let core = await makeCore()
        try await purchase(TestProduct.monthly, with: core)
        XCTAssertNotNil(UserDefaults.standard.dictionary(forKey: "tn_core_cachedEntitlements"))

        try lapse(TestProduct.monthly)

        await waitUntilResolved(core, "the entitlement to go away") { !core.isPremium }

        XCTAssertNil(
            UserDefaults.standard.dictionary(forKey: "tn_core_cachedEntitlements"),
            "A stale cache would warm-start the next launch into a false unlock."
        )
    }

    // MARK: - Background Snapshot

    func testSnapshotIsReadableOffTheMainActorAndTracksState() async throws {
        let core = await makeCore()
        XCTAssertFalse(TNSubscriptionCore.cachedIsPremium)

        try await purchase(TestProduct.yearly, with: core)

        let premiumOffMain = await Task.detached { TNSubscriptionCore.cachedIsPremium }.value
        let entitlementsOffMain = await Task.detached { TNSubscriptionCore.cachedActiveEntitlements }.value

        XCTAssertTrue(premiumOffMain)
        XCTAssertEqual(entitlementsOffMain, ["Premium", "Sale"])
    }
}
