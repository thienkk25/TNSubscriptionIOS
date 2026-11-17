import XCTest
import StoreKit
import StoreKitTest
@testable import TNSubscriptionCore

/// Products, offerings, package-type inference and the price maths behind the paywall badges.
/// (Sản phẩm, offering, suy luận loại gói, và phần tính giá đằng sau các nhãn trên paywall.)
@MainActor
final class TNProductsAndOfferingsTests: TNCoreIntegrationTestCase {

    // MARK: - Loading

    func testLoadProductsFetchesEveryConfiguredProduct() async {
        let core = await makeCore()

        for id in TestProduct.premiumProducts {
            XCTAssertNotNil(core.product(for: id), "\(id) was not returned by StoreKit.")
        }
    }

    func testLoadProductsIncludesProductsOnlyAnOfferingReferences() async {
        // A promo product can be on a paywall before it is wired into an entitlement. It still
        // has to be fetched, or that paywall renders empty.
        let core = await makeCore(
            entitlements: [TNEntitlement(id: "Premium", productIDs: [TestProduct.yearly])],
            offerings: [TNOffering(identifier: "default", productIDs: [TestProduct.yearly, TestProduct.weekly])]
        )

        XCTAssertNotNil(core.product(for: TestProduct.weekly))
    }

    func testMissingProductIsDroppedRatherThanFailingTheWholeLoad() async {
        let core = await makeCore(
            entitlements: [TNEntitlement(id: "Premium", productIDs: [TestProduct.yearly, "com.does.not.exist"])],
            offerings: [TNOffering(identifier: "default", productIDs: [TestProduct.yearly, "com.does.not.exist"])]
        )

        await core.loadOfferings(offeringIdentifier: "default")

        XCTAssertNotNil(core.product(for: TestProduct.yearly), "A single bad product ID must not take the real ones down with it.")
        XCTAssertNil(core.product(for: "com.does.not.exist"))
        XCTAssertEqual(core.availablePackages.map(\.productIdentifier), [TestProduct.yearly])
    }

    // MARK: - Offerings

    func testDefaultOfferingIsSortedLongestCommitmentFirst() async {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        XCTAssertEqual(core.availablePackages.map(\.productIdentifier), [
            TestProduct.lifetime,
            TestProduct.yearly,
            TestProduct.monthly,
            TestProduct.weekly,
        ])
    }

    func testPreserveOrderKeepsTheDeclaredOrder() async {
        let core = await makeCore(
            offerings: [TNOffering(
                identifier: "default",
                productIDs: [TestProduct.weekly, TestProduct.lifetime, TestProduct.yearly],
                preserveOrder: true
            )]
        )
        await core.loadOfferings(offeringIdentifier: "default")

        XCTAssertEqual(core.availablePackages.map(\.productIdentifier), [
            TestProduct.weekly, TestProduct.lifetime, TestProduct.yearly,
        ])
    }

    func testNamedOfferingIsSelectable() async {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "sale")

        XCTAssertEqual(core.currentOfferingIdentifier, "sale")
        XCTAssertEqual(core.availablePackages.map(\.productIdentifier), [TestProduct.yearly])
    }

    func testUnknownOfferingFallsBackInsteadOfShowingAnEmptyPaywall() async {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "does_not_exist")

        XCTAssertFalse(core.availablePackages.isEmpty, "An unknown offering must fall back, not dead-end the user.")
        XCTAssertEqual(core.currentOfferingIdentifier, "default")
    }

    func testUpdateOfferingsAtRuntimeLoadsNewProducts() async {
        let core = await makeCore(
            offerings: [TNOffering(identifier: "default", productIDs: [TestProduct.yearly])]
        )
        await core.loadOfferings()
        XCTAssertEqual(core.availablePackages.count, 1)

        await core.updateOfferings(
            [TNOffering(identifier: "bf", productIDs: [TestProduct.weekly, TestProduct.monthly])],
            current: "bf"
        )

        XCTAssertEqual(core.currentOfferingIdentifier, "bf")
        XCTAssertEqual(Set(core.availablePackages.map(\.productIdentifier)), [TestProduct.weekly, TestProduct.monthly])
    }

    func testOfferingMetadataIsExposed() async {
        let core = await makeCore(
            offerings: [TNOffering(
                identifier: "default",
                productIDs: [TestProduct.yearly],
                metadata: ["headline": "Black Friday"]
            )]
        )
        await core.loadOfferings()

        XCTAssertEqual(core.currentOfferingMetadata["headline"], "Black Friday")
    }

    // MARK: - Package Type Inference

    func testPackageTypesAreInferredFromTheRealSubscriptionPeriods() async {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        let types = Dictionary(
            uniqueKeysWithValues: core.availablePackages.map { ($0.productIdentifier, $0.packageType) }
        )

        XCTAssertEqual(types[TestProduct.weekly], .weekly)
        XCTAssertEqual(types[TestProduct.monthly], .monthly)
        XCTAssertEqual(types[TestProduct.yearly], .annual)
        XCTAssertEqual(types[TestProduct.lifetime], .lifetime, "A non-consumable must come through as .lifetime, not .unknown.")
    }

    func testOnlySubscriptionsReportIsSubscription() async {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        let lifetime = core.availablePackages.first { $0.productIdentifier == TestProduct.lifetime }
        let yearly = core.availablePackages.first { $0.productIdentifier == TestProduct.yearly }

        XCTAssertEqual(lifetime?.isSubscription, false)
        XCTAssertEqual(yearly?.isSubscription, true)
    }

    // MARK: - Price Maths

    /// Pins the fixture's prices, so a change to the .storekit file fails here with a clear
    /// message instead of surfacing as a confusing per-month or savings mismatch.
    /// (Chốt giá trong fixture, để khi file .storekit đổi thì test này fail với thông báo rõ
    /// ràng, chứ không biểu hiện thành lệch per-month hay lệch % tiết kiệm khó hiểu.)
    ///
    /// Whole-dollar prices are deliberate: the simulator runtime reports `product.price` as
    /// the truncated integer of a fractional `displayPrice` ("1.99" arrives as `1.0`) while
    /// still formatting `displayPrice` as "$1.99". Whole dollars avoid that discrepancy.
    /// (Giá tròn đô là có chủ đích: simulator runtime trả `product.price` là phần nguyên đã
    /// bị cắt của `displayPrice` dạng thập phân — "1.99" thành `1.0` — nhưng vẫn format
    /// `displayPrice` ra "$1.99". Dùng số tròn để tránh sai lệch đó.)
    func testFixturePricesAreWhatTheSuiteAssumes() async {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        func price(_ id: String) -> Decimal? {
            core.availablePackages.first { $0.productIdentifier == id }?.product.price
        }

        XCTAssertEqual(price(TestProduct.weekly), 2)
        XCTAssertEqual(price(TestProduct.monthly), 5)
        XCTAssertEqual(price(TestProduct.yearly), 30)
        XCTAssertEqual(price(TestProduct.lifetime), 50)
    }

    func testPricePerMonthNormalisesAcrossPeriods() async {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        func perMonth(_ id: String) -> Double? {
            guard let value = core.availablePackages.first(where: { $0.productIdentifier == id })?.pricePerMonth
            else { return nil }
            return Double(truncating: value as NSDecimalNumber)
        }

        // $30 / 12 months = $2.50 — the cheapest, which is what earns the badge.
        XCTAssertEqual(try XCTUnwrap(perMonth(TestProduct.yearly)), 2.5, accuracy: 0.01)

        // $5 for one month is already per-month.
        XCTAssertEqual(try XCTUnwrap(perMonth(TestProduct.monthly)), 5.0, accuracy: 0.01)

        // $2 / week ≈ $8.57 a month — the most expensive, despite the smallest sticker price.
        XCTAssertEqual(try XCTUnwrap(perMonth(TestProduct.weekly)), 8.571, accuracy: 0.05)

        XCTAssertNil(perMonth(TestProduct.lifetime), "A lifetime purchase has no period, so no per-month price.")
    }

    func testRecommendedPackageIsTheCheapestPerMonthNotJustTheAnnualOne() async {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        XCTAssertEqual(core.recommendedPackage?.productIdentifier, TestProduct.yearly)
    }

    func testSavingsPercentageIsComputedFromPerMonthPrices() async {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        let yearly = try? XCTUnwrap(core.availablePackages.first { $0.productIdentifier == TestProduct.yearly })
        let weekly = try? XCTUnwrap(core.availablePackages.first { $0.productIdentifier == TestProduct.weekly })

        // (8.571 - 2.5) / 8.571 ≈ 70.8% → 70 after flooring.
        let savings = yearly?.savingsPercentage(comparedTo: weekly!)
        XCTAssertEqual(savings, 70)
    }

    func testSavingsIsNilWhenThePackageIsNotActuallyCheaper() async {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        let yearly = try? XCTUnwrap(core.availablePackages.first { $0.productIdentifier == TestProduct.yearly })
        let weekly = try? XCTUnwrap(core.availablePackages.first { $0.productIdentifier == TestProduct.weekly })

        XCTAssertNil(weekly?.savingsPercentage(comparedTo: yearly!), "Claiming a saving on the more expensive plan would be a lie.")
        XCTAssertNil(yearly?.savingsPercentage(comparedTo: yearly!), "A plan does not save against itself.")
    }

    func testLocalizedPricesComeFromTheStoreNotFromUs() async {
        let core = await makeCore()
        await core.loadOfferings(offeringIdentifier: "default")

        let yearly = core.availablePackages.first { $0.productIdentifier == TestProduct.yearly }
        XCTAssertEqual(yearly?.localizedPriceString, "$30.00")
        XCTAssertEqual(yearly?.localizedTitle, "Yearly")
    }

    // MARK: - IAP Disabled

    func testDisablingIAPUnlocksEverythingAndSkipsStoreKit() async {
        let core = await makeCore(isIAPEnabled: false)

        XCTAssertTrue(core.isPremium)
        XCTAssertEqual(core.entitlementState, .unlocked)
        XCTAssertEqual(core.activeEntitlements, ["Premium", "Sale"])

        await core.loadOfferings()
        XCTAssertTrue(core.availablePackages.isEmpty)
        XCTAssertNotNil(core.offeringsError, "A disabled-IAP build should say why there are no plans.")
    }
}
