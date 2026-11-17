import XCTest
import StoreKit
import StoreKitTest
@testable import TNSubscriptionCore

/// Consumable purchases and the balance ledger.
/// (Mua consumable và sổ số dư.)
///
/// The thing worth testing hardest here is that a reward is credited **exactly once**:
/// crediting twice gives away currency, crediting zero times takes the user's money.
/// (Thứ đáng kiểm tra kỹ nhất ở đây là phần thưởng được cộng **đúng một lần**: cộng hai lần là
/// cho không tiền ảo, không cộng lần nào là lấy tiền của người dùng.)
@MainActor
final class TNConsumableIntegrationTests: TNCoreIntegrationTestCase {

    private let coinPack = TNConsumableProduct(id: TestProduct.coins, reward: 100, currency: "coins")

    @discardableResult
    private func makeConsumables() async -> TNConsumableManager {
        TNConsumableManager.configure(products: [coinPack])
        let manager = TNConsumableManager.shared!
        await manager.loadProductsAsync()
        return manager
    }

    // MARK: - Loading

    func testConsumableProductLoads() async {
        let manager = await makeConsumables()

        XCTAssertEqual(manager.storeProducts.map(\.id), [TestProduct.coins])
        XCTAssertNil(manager.loadError)
        XCTAssertNotNil(manager.storeProduct(for: TestProduct.coins))
    }

    func testBalanceStartsAtZero() async {
        let manager = await makeConsumables()

        XCTAssertEqual(manager.balance(for: "coins"), 0)
        XCTAssertFalse(manager.canAfford(1, currency: "coins"))
    }

    // MARK: - Purchase Credits

    func testPurchaseCreditsTheReward() async throws {
        let manager = await makeConsumables()

        let reward = try await manager.purchaseAsync(productId: TestProduct.coins)

        XCTAssertEqual(reward, 100)
        XCTAssertEqual(manager.balance(for: "coins"), 100)
    }

    func testTwoPurchasesCreditTwice() async throws {
        let manager = await makeConsumables()

        try await manager.purchaseAsync(productId: TestProduct.coins)
        try await manager.purchaseAsync(productId: TestProduct.coins)

        // The dedup list records every transaction the manager actually credited, so it says
        // precisely whether StoreKitTest handed us two distinct transactions or replayed one.
        let credited = UserDefaults.standard.stringArray(forKey: "tn_core_consumable_processed_tx_ids") ?? []

        XCTAssertEqual(
            credited.count, 2,
            """
            Expected two credited transactions, got \(credited). If StoreKitTest reused one \
            transaction identifier for both purchases, the dedup guard is behaving correctly \
            and this is a fixture limitation rather than a library bug.
            """
        )
        XCTAssertEqual(manager.balance(for: "coins"), 200, "Two distinct transactions must credit twice.")
    }

    func testRecoveryDoesNotDoubleCreditAnAlreadyCreditedTransaction() async throws {
        let manager = await makeConsumables()
        try await manager.purchaseAsync(productId: TestProduct.coins)
        XCTAssertEqual(manager.balance(for: "coins"), 100)

        // Reconfigure without wiping the dedup history or the balance: this is what a relaunch
        // looks like, and it re-runs the unfinished-transaction recovery.
        TNConsumableManager.resetInstanceForTesting()
        let relaunched = await makeConsumables()

        // Give the recovery task a moment to run.
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(
            relaunched.balance(for: "coins"), 100,
            "Recovery must not re-credit a transaction that was already paid out."
        )
    }

    func testPurchasingAnUnconfiguredProductThrows() async throws {
        let manager = await makeConsumables()

        do {
            try await manager.purchaseAsync(productId: "com.not.configured")
            XCTFail("An unconfigured product has no reward defined, so buying it must be refused.")
        } catch TNConsumableManager.ConsumableError.productNotConfigured {
            // Expected.
        }
    }

    func testPurchasingBeforeLoadingThrowsAClearError() async throws {
        TNConsumableManager.configure(products: [coinPack])
        let manager = TNConsumableManager.shared!

        do {
            try await manager.purchaseAsync(productId: TestProduct.coins)
            XCTFail("Nothing was loaded from the store, so there is nothing to buy.")
        } catch TNConsumableManager.ConsumableError.productNotLoaded {
            // Expected.
        }
    }

    // MARK: - Ledger

    func testDeductSucceedsOnlyWithEnoughBalance() async throws {
        let manager = await makeConsumables()
        try await manager.purchaseAsync(productId: TestProduct.coins)

        XCTAssertTrue(manager.deductBalance(40, for: "coins"))
        XCTAssertEqual(manager.balance(for: "coins"), 60)

        XCTAssertFalse(manager.deductBalance(100, for: "coins"), "Overspending must be refused.")
        XCTAssertEqual(manager.balance(for: "coins"), 60, "A refused spend must not move the balance.")
    }

    func testNonPositiveAmountsAreRejected() async {
        let manager = await makeConsumables()
        manager.addBalance(50, for: "coins")

        XCTAssertFalse(manager.deductBalance(0, for: "coins"))
        XCTAssertFalse(manager.deductBalance(-10, for: "coins"))
        manager.addBalance(-10, for: "coins")

        XCTAssertEqual(manager.balance(for: "coins"), 50, "A negative 'credit' must not drain the balance.")
    }

    func testSetBalanceClampsToZero() async {
        let manager = await makeConsumables()

        manager.setBalance(-5, for: "coins")

        XCTAssertEqual(manager.balance(for: "coins"), 0)
    }

    func testBalanceSurvivesARelaunch() async throws {
        let manager = await makeConsumables()
        try await manager.purchaseAsync(productId: TestProduct.coins)

        TNConsumableManager.resetInstanceForTesting()
        let relaunched = await makeConsumables()

        XCTAssertEqual(relaunched.balance(for: "coins"), 100, "The balance is persisted in the Keychain.")
    }

    // MARK: - Server-Authoritative Spending

    func testSpendGoesThroughTheHandlerAndMirrorsACommit() async throws {
        let manager = await makeConsumables()
        try await manager.purchaseAsync(productId: TestProduct.coins)

        var seen: (String, Int, String?)?
        manager.configureSpendHandler { currency, amount, reference in
            seen = (currency, amount, reference)
            return true
        }

        let committed = try await manager.spendAsync(30, currency: "coins", reference: "sword-1")

        XCTAssertTrue(committed)
        XCTAssertEqual(seen?.0, "coins")
        XCTAssertEqual(seen?.1, 30)
        XCTAssertEqual(seen?.2, "sword-1")
        XCTAssertEqual(manager.balance(for: "coins"), 70)
    }

    func testARefusedServerSpendLeavesTheBalanceAlone() async throws {
        let manager = await makeConsumables()
        try await manager.purchaseAsync(productId: TestProduct.coins)

        manager.configureSpendHandler { _, _, _ in false }

        let committed = try await manager.spendAsync(30, currency: "coins")

        XCTAssertFalse(committed)
        XCTAssertEqual(manager.balance(for: "coins"), 100, "The server is authoritative; a refusal must not deduct.")
    }

    func testAThrowingHandlerPropagatesAndDoesNotDeduct() async throws {
        struct Boom: Error {}
        let manager = await makeConsumables()
        try await manager.purchaseAsync(productId: TestProduct.coins)

        manager.configureSpendHandler { _, _, _ in throw Boom() }

        do {
            _ = try await manager.spendAsync(30, currency: "coins")
            XCTFail("A network failure in the spend handler must surface, not be swallowed.")
        } catch is Boom {
            XCTAssertEqual(manager.balance(for: "coins"), 100)
        }
    }

    func testServerIsNotCalledWhenTheLocalBalanceAlreadyCannotCover() async throws {
        let manager = await makeConsumables()

        var handlerCalled = false
        manager.configureSpendHandler { _, _, _ in
            handlerCalled = true
            return true
        }

        let committed = try await manager.spendAsync(50, currency: "coins")

        XCTAssertFalse(committed)
        XCTAssertFalse(handlerCalled, "No point burning a round trip on a spend the device can already see is impossible.")
    }

    func testWithoutAHandlerSpendFallsBackToTheLocalLedger() async throws {
        let manager = await makeConsumables()
        try await manager.purchaseAsync(productId: TestProduct.coins)

        let committed = try await manager.spendAsync(25, currency: "coins")

        XCTAssertTrue(committed)
        XCTAssertEqual(manager.balance(for: "coins"), 75)
    }

    // MARK: - Interaction With The Subscription Manager

    func testTheSubscriptionManagerDoesNotSwallowConsumableTransactions() async throws {
        // Both managers listen to Transaction.updates. If the subscription manager finished a
        // consumable, the reward would be lost with no way to recover it — this is the
        // regression guard for that.
        let core = await makeCore()
        let manager = await makeConsumables()

        let reward = try await manager.purchaseAsync(productId: TestProduct.coins)

        XCTAssertEqual(reward, 100)
        XCTAssertEqual(manager.balance(for: "coins"), 100)
        XCTAssertFalse(core.isPremium, "A coin pack is not an entitlement.")
    }
}
