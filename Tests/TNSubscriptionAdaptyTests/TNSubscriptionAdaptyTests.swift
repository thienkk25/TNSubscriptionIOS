import XCTest
import Adapty
@testable import TNSubscriptionAdapty

/// Unit tests for the Adapty engine's own logic.
/// (Unit test cho phần logic riêng của engine Adapty.)
///
/// Adapty's models (`AdaptyProfile`, `AccessLevel`, `AdaptyPaywallProduct`) have no public
/// initialisers and the network calls need a real project key, so the mapping rules were
/// extracted into pure functions and are tested here directly.
/// (Các model của Adapty không có initializer công khai và các lời gọi mạng cần key dự án thật,
/// nên các quy tắc mapping được tách thành hàm thuần và kiểm thử trực tiếp ở đây.)

// MARK: - API Key

final class TNAdaptyKeyTests: XCTestCase {

    private let validKey = "public_live_" + String(repeating: "a", count: 29)

    func testAValidPublicKeyPasses() {
        XCTAssertEqual(validKey.count, TNAdaptyKeyProblem.minimumLength)
        XCTAssertNil(TNAdaptyKeyProblem.check(validKey))
    }

    func testSurroundingWhitespaceIsTolerated() {
        // A trailing newline from a pasted .xcconfig value is the commonest invisible mistake.
        XCTAssertNil(TNAdaptyKeyProblem.check("  \(validKey)\n"))
    }

    func testEmptyKeyIsRejected() {
        XCTAssertEqual(TNAdaptyKeyProblem.check(""), .empty)
        XCTAssertEqual(TNAdaptyKeyProblem.check("   "), .empty)
    }

    func testASecretKeyIsRejected() {
        XCTAssertEqual(TNAdaptyKeyProblem.check("secret_live_" + String(repeating: "a", count: 40)), .secretKey)
    }

    func testARevenueCatKeyIsRecognisedAsSuch() {
        // The usual slip when switching vendors, and it deserves its own message.
        XCTAssertEqual(TNAdaptyKeyProblem.check("appl_abcdefghijklmnopqrstuvwxyz"), .revenueCatKey)
        XCTAssertEqual(TNAdaptyKeyProblem.check("test_abcdefghijklmnopqrstuvwxyz"), .revenueCatKey)
        XCTAssertEqual(TNAdaptyKeyProblem.check("goog_abcdefghijklmnopqrstuvwxyz"), .revenueCatKey)
    }

    func testATruncatedKeyIsRejected() {
        XCTAssertEqual(TNAdaptyKeyProblem.check("public_live_short"), .tooShort)
    }

    func testAnUnknownPrefixIsRejected() {
        XCTAssertEqual(TNAdaptyKeyProblem.check(String(repeating: "x", count: 50)), .unrecognisedPrefix)
    }

    func testEveryProblemExplainsWhatToDo() {
        let problems: [TNAdaptyKeyProblem] = [.empty, .secretKey, .revenueCatKey, .unrecognisedPrefix, .tooShort]
        for problem in problems {
            XCTAssertFalse(problem.explanation.isEmpty)
        }
        XCTAssertTrue(TNAdaptyKeyProblem.secretKey.explanation.contains("rotate"),
                      "A leaked secret key needs rotating, not just replacing in code.")
    }
}

// MARK: - Mapping Rules

final class TNAdaptyMappingTests: XCTestCase {

    func testStoreStringsMap() {
        XCTAssertEqual(TNStore.from(adaptyStore: "app_store"), .appStore)
        XCTAssertEqual(TNStore.from(adaptyStore: "play_store"), .playStore)
        XCTAssertEqual(TNStore.from(adaptyStore: "stripe"), .web)
        XCTAssertEqual(TNStore.from(adaptyStore: "paddle"), .web)
        XCTAssertEqual(TNStore.from(adaptyStore: "adapty"), .promotional)
        XCTAssertEqual(TNStore.from(adaptyStore: "APP_STORE"), .appStore, "Matching must not depend on case.")
        XCTAssertEqual(TNStore.from(adaptyStore: "something_new"), .other)
    }

    func testPeriodTypeFromActiveOffers() {
        XCTAssertEqual(TNPeriodType.from(introductoryOfferType: nil, promotionalOfferType: nil), .normal)
        XCTAssertEqual(TNPeriodType.from(introductoryOfferType: "free_trial", promotionalOfferType: nil), .trial)
        XCTAssertEqual(TNPeriodType.from(introductoryOfferType: "pay_as_you_go", promotionalOfferType: nil), .intro)
        XCTAssertEqual(TNPeriodType.from(introductoryOfferType: "pay_up_front", promotionalOfferType: nil), .intro)
        XCTAssertEqual(TNPeriodType.from(introductoryOfferType: "free_trial", promotionalOfferType: "pay_as_you_go"), .promotional,
                       "A promotional offer is the more specific state and wins.")
    }

    func testIssueClassificationOrder() {
        let past = Date().addingTimeInterval(-3600)
        let future = Date().addingTimeInterval(3600)

        XCTAssertNil(TNSubscriptionIssue.classify(isRefund: false, isActive: true, isInGracePeriod: false, billingIssueDetectedAt: nil, expiresAt: future))
        XCTAssertEqual(TNSubscriptionIssue.classify(isRefund: true, isActive: true, isInGracePeriod: true, billingIssueDetectedAt: past, expiresAt: future), .revoked,
                       "A refund outranks every other state.")
        XCTAssertEqual(TNSubscriptionIssue.classify(isRefund: false, isActive: true, isInGracePeriod: true, billingIssueDetectedAt: past, expiresAt: future), .gracePeriod)
        XCTAssertEqual(TNSubscriptionIssue.classify(isRefund: false, isActive: true, isInGracePeriod: false, billingIssueDetectedAt: past, expiresAt: future), .gracePeriod,
                       "A billing problem while access continues is a grace period, whatever the flag says.")
        XCTAssertEqual(TNSubscriptionIssue.classify(isRefund: false, isActive: false, isInGracePeriod: false, billingIssueDetectedAt: past, expiresAt: past), .billingRetry)
        XCTAssertEqual(TNSubscriptionIssue.classify(isRefund: false, isActive: false, isInGracePeriod: false, billingIssueDetectedAt: nil, expiresAt: past), .expired)
    }

    func testIntroEligibilityDerivesFromTheOfferAdaptySelected() {
        XCTAssertEqual(TNSubscriptionAdapty.introEligibility(hasIntroOffer: false, selectedOfferType: nil), .noIntroOfferExists)
        XCTAssertEqual(TNSubscriptionAdapty.introEligibility(hasIntroOffer: true, selectedOfferType: .introductory), .eligible)
        XCTAssertEqual(TNSubscriptionAdapty.introEligibility(hasIntroOffer: true, selectedOfferType: nil), .ineligible,
                       "Adapty withholds the intro offer once it has been used.")
        XCTAssertEqual(TNSubscriptionAdapty.introEligibility(hasIntroOffer: true, selectedOfferType: .winBack), .ineligible,
                       "When a win-back offer takes precedence, a 'Start Free Trial' button would be a lie.")
    }

    func testOfferTypesMap() {
        XCTAssertEqual(TNOfferType(.introductory), .introductory)
        XCTAssertEqual(TNOfferType(.promotional), .promotional)
        XCTAssertEqual(TNOfferType(.winBack), .winBack)
        XCTAssertEqual(TNOfferType(AdaptySubscriptionOfferType(rawValue: "future_type")), .unknown)
    }

    func testPaymentModesMap() {
        XCTAssertEqual(TNOfferPaymentMode(.freeTrial), .freeTrial)
        XCTAssertEqual(TNOfferPaymentMode(.payUpFront), .payUpFront)
        XCTAssertEqual(TNOfferPaymentMode(.payAsYouGo), .payAsYouGo)
        XCTAssertEqual(TNOfferPaymentMode(.unknown), .unknown)
    }
}

// MARK: - Packages And Prices

final class TNAdaptyPackageTests: XCTestCase {

    func testPackageTypeInference() {
        XCTAssertEqual(TNPackageType.inferred(unitDays: 7, value: 1), .weekly)
        XCTAssertEqual(TNPackageType.inferred(unitDays: 1, value: 7), .weekly)
        XCTAssertEqual(TNPackageType.inferred(unitDays: 30, value: 1), .monthly)
        XCTAssertEqual(TNPackageType.inferred(unitDays: 30, value: 3), .threeMonth)
        XCTAssertEqual(TNPackageType.inferred(unitDays: 30, value: 6), .sixMonth)
        XCTAssertEqual(TNPackageType.inferred(unitDays: 365, value: 1), .annual)
        XCTAssertEqual(TNPackageType.inferred(unitDays: 30, value: 12), .annual)
        XCTAssertEqual(TNPackageType.inferred(unitDays: 1, value: 10), .custom)
    }

    func testSavingsMathsOnTheWeeklyCaseThatOverflowedDecimal() {
        // $2/week ≈ $8.57/month vs $30/year = $2.50/month. In TNSubscriptionCore this exact case
        // overflowed Decimal into nan and showed "SAVE 0%"; it must read 70 here.
        let weeklyPerMonth = Decimal(2) * Decimal(30) / Decimal(7)
        let yearlyPerMonth = Decimal(30) / Decimal(12)

        XCTAssertEqual(TNPackage.savingsPercentage(perMonth: yearlyPerMonth, comparedTo: weeklyPerMonth), 70)
    }

    func testSavingsIsNilWhenNotCheaper() {
        XCTAssertNil(TNPackage.savingsPercentage(perMonth: 5, comparedTo: 2))
        XCTAssertNil(TNPackage.savingsPercentage(perMonth: 5, comparedTo: 5))
        XCTAssertNil(TNPackage.savingsPercentage(perMonth: 1, comparedTo: 0))
    }

    func testSavingsRejectsNaNInsteadOfReportingZero() {
        XCTAssertNil(TNPackage.savingsPercentage(perMonth: .nan, comparedTo: 10),
                     "A nan must surface as 'no badge', never as 'SAVE 0%'.")
    }

    func testPeriodFormatting() {
        XCTAssertEqual(TNPeriodFormatter.string(unit: .day, count: 3), "3 Days")
        XCTAssertEqual(TNPeriodFormatter.string(unit: .week, count: 1), "1 Week")
        XCTAssertEqual(TNPeriodFormatter.string(unit: .month, count: 1), "1 Month")
        XCTAssertEqual(TNPeriodFormatter.string(unit: .year, count: 2), "2 Years")
        XCTAssertEqual(TNPeriodFormatter.string(unit: .month, count: 0), "1 Month", "A zero count is clamped, never rendered.")
    }
}

// MARK: - Config And Logging

final class TNAdaptyConfigTests: XCTestCase {

    func testConvenienceInitDefaultsToAdaptysLowercasePremium() {
        let config = TNSubscriptionConfig(apiKey: "k", productIDs: ["a", "b"])
        XCTAssertEqual(config.allEntitlementIDs, ["premium"], "Adapty's default access level is lowercase 'premium'.")
        XCTAssertEqual(config.allProductIDs, ["a", "b"])
        XCTAssertTrue(config.offlineStoreKitFallback, "The fallback is on by default so nobody is locked out offline.")
    }

    func testLogLevelMapsToAdaptyAndBack() {
        for level in [TNLogLevel.verbose, .debug, .info, .warn, .error] {
            XCTAssertEqual(TNLogLevel(adaptyLevel: level.adaptyLevel), level)
        }
        XCTAssertEqual(TNLogLevel.none.adaptyLevel, .error, "Adapty has no 'off'; .none is silenced by the bridge instead.")
    }

    func testNoneSilencesForwardedAdaptyLogsToo() {
        let previousLevel = TNLog.level
        let previousHandler = TNLog.handler
        defer {
            TNLog.level = previousLevel
            TNLog.handler = previousHandler
        }

        var received: [String] = []
        TNLog.handler = { received.append($1) }
        TNLog.level = .none

        TNLog.log(TNLogLevel(adaptyLevel: .error), "[Adapty] boom")

        XCTAssertTrue(received.isEmpty, ".none must silence the Adapty SDK's output as well as ours.")
    }

    func testPurchaseErrorsHaveUserFacingMessages() {
        for error in [TNPurchaseError.userCancelled, .purchasePending, .notActivated] {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }
}

// MARK: - Engine Without Adapty

/// Behaviour that must hold with no reachable Adapty project.
/// (Hành vi phải đúng khi không có dự án Adapty nào kết nối được.)
@MainActor
final class TNAdaptyEngineTests: XCTestCase {

    override func setUp() async throws {
        TNSubscriptionAdapty.logLevel = .none
        TNSubscriptionAdapty.resetForTesting()
    }

    override func tearDown() async throws {
        TNSubscriptionAdapty.resetForTesting()
    }

    /// The single most important guard in this target: Adapty validates its key with an
    /// `assert`, so passing it a bad key crashes a Debug build. Reaching the assertions below
    /// at all proves the bad key never got that far.
    /// (Phép bảo vệ quan trọng nhất của target này: Adapty kiểm tra key bằng `assert`, nên truyền
    /// key sai vào sẽ làm crash bản build Debug. Chạy tới được các assertion bên dưới đã chứng minh
    /// key sai không hề đi tới đó.)
    func testABadKeyDoesNotCrashAndDegradesToLocked() async throws {
        TNSubscriptionAdapty.configure(config: TNSubscriptionConfig(
            apiKey: "appl_this_is_a_revenuecat_key",
            entitlements: [TNEntitlement(id: "premium", productIDs: ["com.app.yearly"])],
            defaultPlacementId: "main"
        ))
        let engine = try XCTUnwrap(TNSubscriptionAdapty.shared)

        await engine.resolveEntitlement()

        XCTAssertFalse(engine.isAdaptyActivated)
        XCTAssertEqual(engine.entitlementState, .locked, "With no purchases and no Adapty, the answer is a definite .locked.")
        XCTAssertEqual(engine.customerInfo?.source, .storeKitFallback)
    }

    func testPlacementsAreRefusedWithAReadableErrorWhenNotActivated() async throws {
        TNSubscriptionAdapty.configure(config: TNSubscriptionConfig(
            apiKey: "",
            entitlements: [TNEntitlement(id: "premium")],
            defaultPlacementId: "main"
        ))
        let engine = try XCTUnwrap(TNSubscriptionAdapty.shared)

        await engine.loadOfferings()

        XCTAssertTrue(engine.availablePackages.isEmpty)
        XCTAssertNotNil(engine.offeringsError, "The paywall needs something to show instead of a blank list.")
    }

    func testIdentifyIsRefusedWhenNotActivated() async throws {
        TNSubscriptionAdapty.configure(config: TNSubscriptionConfig(
            apiKey: "secret_live_" + String(repeating: "a", count: 40),
            entitlements: [TNEntitlement(id: "premium")]
        ))
        let engine = try XCTUnwrap(TNSubscriptionAdapty.shared)

        do {
            try await engine.identify("user-1")
            XCTFail("identify must not silently succeed without Adapty.")
        } catch TNPurchaseError.notActivated {
            // Expected.
        }
    }

    func testDisablingIAPUnlocksEverythingWithoutTouchingAdapty() async throws {
        TNSubscriptionAdapty.configure(config: TNSubscriptionConfig(
            apiKey: "",
            entitlements: [TNEntitlement(id: "premium"), TNEntitlement(id: "pro")],
            isIAPEnabled: false
        ))
        let engine = try XCTUnwrap(TNSubscriptionAdapty.shared)

        XCTAssertTrue(engine.isPremium)
        XCTAssertEqual(engine.entitlementState, .unlocked)
        XCTAssertEqual(engine.activeEntitlements, ["premium", "pro"])
        XCTAssertFalse(engine.isAdaptyActivated)
        XCTAssertTrue(TNSubscriptionAdapty.cachedIsPremium)
    }

    func testWarmStartUnlocksFromAnUnexpiredCacheEntry() async throws {
        UserDefaults.standard.set(
            ["premium": Date.distantFuture.timeIntervalSince1970],
            forKey: "tn_adapty_cachedEntitlements"
        )

        TNSubscriptionAdapty.configure(config: TNSubscriptionConfig(
            apiKey: "",
            entitlements: [TNEntitlement(id: "premium")]
        ))
        let engine = try XCTUnwrap(TNSubscriptionAdapty.shared)

        // Read synchronously — before any await — which is the window a paywall would flash in.
        XCTAssertEqual(engine.entitlementState, .unlocked)
        XCTAssertTrue(engine.isPremium)
    }

    func testWarmStartIgnoresAnExpiredCacheEntry() async throws {
        UserDefaults.standard.set(
            ["premium": Date().addingTimeInterval(-60).timeIntervalSince1970],
            forKey: "tn_adapty_cachedEntitlements"
        )

        TNSubscriptionAdapty.configure(config: TNSubscriptionConfig(
            apiKey: "",
            entitlements: [TNEntitlement(id: "premium")]
        ))
        let engine = try XCTUnwrap(TNSubscriptionAdapty.shared)

        XCTAssertEqual(engine.entitlementState, .unknown)
        XCTAssertFalse(engine.isPremium)
    }
}
