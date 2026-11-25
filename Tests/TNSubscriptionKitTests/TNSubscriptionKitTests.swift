import XCTest
import StoreKit
@testable import TNSubscriptionKit

/// Tests for the code Core, Adapty and Qonversion share — run once, here, instead of once per engine.
/// (Test cho phần code mà Core, Adapty và Qonversion dùng chung — chạy một lần ở đây thay vì mỗi
/// engine một lần.)

// MARK: - Package Type

final class TNPackageTypeTests: XCTestCase {

    func testSortOrderPutsLongestCommitmentFirst() {
        let shuffled: [TNPackageType] = [.weekly, .lifetime, .monthly, .annual, .sixMonth]
        let sorted = shuffled.sorted { $0.sortOrder < $1.sortOrder }

        XCTAssertEqual(sorted, [.lifetime, .annual, .sixMonth, .monthly, .weekly])
    }

    func testEveryTypeHasADistinctSortOrder() {
        let orders = TNPackageType.allCases.map(\.sortOrder)
        XCTAssertEqual(Set(orders).count, orders.count, "Two package types share a sort order, so paywall ordering would be nondeterministic.")
    }

    func testOnlyCustomAndUnknownLackADisplayName() {
        for type in TNPackageType.allCases {
            switch type {
            case .custom, .unknown:
                XCTAssertNil(type.localizedName, "\(type) should fall back to the store's own product name.")
            default:
                XCTAssertNotNil(type.localizedName, "\(type) needs a display name for the paywall.")
            }
        }
    }
}

// MARK: - Entitlement Snapshot

final class TNEntitlementSnapshotTests: XCTestCase {

    func testSnapshotRoundTrips() {
        TNEntitlementSnapshot.shared.update(isPremium: true, active: ["Premium", "Sale"])

        XCTAssertTrue(TNEntitlementSnapshot.shared.isPremium)
        XCTAssertEqual(TNEntitlementSnapshot.shared.activeEntitlements, ["Premium", "Sale"])

        TNEntitlementSnapshot.shared.update(isPremium: false, active: [])

        XCTAssertFalse(TNEntitlementSnapshot.shared.isPremium)
        XCTAssertTrue(TNEntitlementSnapshot.shared.activeEntitlements.isEmpty)
    }

    func testConcurrentAccessDoesNotRace() {
        // The whole point of the snapshot is being readable off the main actor.
        // Run under the thread sanitiser to make this test meaningful.
        let iterations = 500
        let done = expectation(description: "concurrent access")
        done.expectedFulfillmentCount = iterations * 2

        for i in 0..<iterations {
            DispatchQueue.global().async {
                TNEntitlementSnapshot.shared.update(isPremium: i.isMultiple(of: 2), active: ["E\(i)"])
                done.fulfill()
            }
            DispatchQueue.global().async {
                _ = TNEntitlementSnapshot.shared.isPremium
                _ = TNEntitlementSnapshot.shared.activeEntitlements
                done.fulfill()
            }
        }

        wait(for: [done], timeout: 10)
    }
}

// MARK: - Identity

final class TNIdentityTests: XCTestCase {

    func testClientIdIsStableAcrossReads() {
        let first = TNIdentity.clientId
        let second = TNIdentity.clientId

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    func testClientIdIsAUUIDSoItCanBeUsedAsAnAppAccountToken() {
        // Apple rejects an appAccountToken that is not a UUID, which would fail the
        // purchase rather than just dropping the token.
        XCTAssertNotNil(UUID(uuidString: TNIdentity.clientId))
        XCTAssertNotNil(TNIdentity.appAccountToken)
    }

    func testIdentityHeadersIncludeUserIdOnlyWhenGiven() {
        let without = TNIdentity.identityHeaders()
        XCTAssertNotNil(without["X-Client-Id"])
        XCTAssertNotNil(without["X-Device-Id"])
        XCTAssertNil(without["X-User-Id"])

        let with = TNIdentity.identityHeaders(userId: "user-7")
        XCTAssertEqual(with["X-User-Id"], "user-7")

        let empty = TNIdentity.identityHeaders(userId: "")
        XCTAssertNil(empty["X-User-Id"], "An empty user ID should be omitted, not sent as a blank header.")
    }

    func testApplyingIdentityHeadersDoesNotMutateTheOriginal() {
        let original = URLRequest(url: URL(string: "https://example.com")!)
        let decorated = original.applyingTNIdentityHeaders()

        XCTAssertNil(original.value(forHTTPHeaderField: "X-Client-Id"))
        XCTAssertEqual(decorated.value(forHTTPHeaderField: "X-Client-Id"), TNIdentity.clientId)
    }
}

// MARK: - Log Level

final class TNLogLevelTests: XCTestCase {

    func testLevelsAreOrderedBySeverity() {
        XCTAssertTrue(TNLogLevel.verbose < .debug)
        XCTAssertTrue(TNLogLevel.debug < .info)
        XCTAssertTrue(TNLogLevel.info < .warn)
        XCTAssertTrue(TNLogLevel.warn < .error)
        XCTAssertTrue(TNLogLevel.error < .none)
    }

    func testHandlerReceivesOnlyMessagesAtOrAboveTheThreshold() {
        let previousLevel = TNLog.level
        let previousHandler = TNLog.handler
        defer {
            TNLog.level = previousLevel
            TNLog.handler = previousHandler
        }

        var captured: [(TNLogLevel, String)] = []
        TNLog.handler = { captured.append(($0, $1)) }
        TNLog.level = .warn

        TNLog.verbose("v")
        TNLog.debug("d")
        TNLog.info("i")
        TNLog.warn("w")
        TNLog.error("e")

        XCTAssertEqual(captured.map(\.1), ["w", "e"])
    }

    func testNoneSilencesEverything() {
        let previousLevel = TNLog.level
        let previousHandler = TNLog.handler
        defer {
            TNLog.level = previousLevel
            TNLog.handler = previousHandler
        }

        var count = 0
        TNLog.handler = { _, _ in count += 1 }
        TNLog.level = .none

        TNLog.error("this must not be emitted")

        XCTAssertEqual(count, 0)
    }

    func testFilteredMessagesAreNeverEvaluated() {
        let previousLevel = TNLog.level
        let previousHandler = TNLog.handler
        defer {
            TNLog.level = previousLevel
            TNLog.handler = previousHandler
        }

        TNLog.handler = { _, _ in }
        TNLog.level = .error

        // String interpolation in a dropped log line must cost nothing: at .verbose this
        // package logs per transaction, and that adds up.
        var evaluated = false
        func expensive() -> String {
            evaluated = true
            return "expensive"
        }
        TNLog.debug(expensive())

        XCTAssertFalse(evaluated)
    }
}

// MARK: - Packages And Prices

final class TNPriceMathTests: XCTestCase {

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
        // $2/week ≈ $8.57/month vs $30/year = $2.50/month. In TNSubscriptionCore 1.1 this exact case
        // overflowed Decimal into nan and showed "SAVE 0%"; it must read 70.
        let weeklyPerMonth = Decimal(2) * Decimal(30) / Decimal(7)
        let yearlyPerMonth = Decimal(30) / Decimal(12)

        XCTAssertEqual(TNPriceMath.savingsPercentage(perMonth: yearlyPerMonth, comparedTo: weeklyPerMonth), 70)
    }

    func testSavingsIsNilWhenNotCheaper() {
        XCTAssertNil(TNPriceMath.savingsPercentage(perMonth: 5, comparedTo: 2))
        XCTAssertNil(TNPriceMath.savingsPercentage(perMonth: 5, comparedTo: 5))
        XCTAssertNil(TNPriceMath.savingsPercentage(perMonth: 1, comparedTo: 0))
    }

    func testSavingsRejectsNaNInsteadOfReportingZero() {
        XCTAssertNil(TNPriceMath.savingsPercentage(perMonth: .nan, comparedTo: 10),
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

// MARK: - Recommended Plan

final class TNRecommendedPlanTests: XCTestCase {

    func testPicksTheCheapestPerMonth() {
        let prices: [String: Decimal] = ["weekly": 8, "yearly": 2.5, "monthly": 5]
        let picked = TNPriceMath.recommended(["weekly", "yearly", "monthly"]) { prices[$0] }
        XCTAssertEqual(picked, "yearly")
    }

    func testFallsBackToTheFirstWhenNothingHasAPeriod() {
        let picked = TNPriceMath.recommended(["lifetime", "other"]) { _ in nil }
        XCTAssertEqual(picked, "lifetime", "A paywall of lifetime-only plans still pre-selects one.")
    }

    func testIgnoresPlansWithoutAPeriod() {
        let prices: [String: Decimal] = ["monthly": 5]
        XCTAssertEqual(TNPriceMath.recommended(["lifetime", "monthly"]) { prices[$0] }, "monthly")
    }
}

// MARK: - Warm-Start Cache

final class TNEntitlementCacheTests: XCTestCase {

    private let key = "tn_kit_test_cachedEntitlements"

    override func tearDown() {
        TNEntitlementCache.clear(key: key)
    }

    func testOnlyUnexpiredEntriesAreTrusted() {
        TNEntitlementCache.store([
            "live": Date().addingTimeInterval(3600),
            "lapsed": Date().addingTimeInterval(-60),
        ], key: key)
        XCTAssertEqual(TNEntitlementCache.unexpired(key: key), ["live"],
                       "Stale data must never revive a lapsed subscription.")
    }

    func testLifetimeIsStoredAsADoubleNotNull() throws {
        // NSNull is not a property-list type; one of them makes UserDefaults drop the whole write.
        TNEntitlementCache.store(["lifetime": nil], key: key)
        let raw = try XCTUnwrap(UserDefaults.standard.dictionary(forKey: key))
        XCTAssertTrue(raw["lifetime"] is Double)
        XCTAssertEqual(TNEntitlementCache.unexpired(key: key), ["lifetime"])
    }

    func testStoringNothingClearsTheCache() {
        TNEntitlementCache.store(["live": Date().addingTimeInterval(3600)], key: key)
        TNEntitlementCache.store([:], key: key)
        XCTAssertNil(UserDefaults.standard.dictionary(forKey: key))
    }
}
