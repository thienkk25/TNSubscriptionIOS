import XCTest
import StoreKit
import StoreKitTest
@testable import TNSubscriptionCore

// MARK: - Test Product IDs

/// The products declared in `Resources/TNCoreTests.storekit`.
/// (Các sản phẩm được khai báo trong `Resources/TNCoreTests.storekit`.)
enum TestProduct {
    /// $1.99 / week. (1,99 $ mỗi tuần.)
    static let weekly = "com.tnsubscription.core.tests.weekly"
    /// $4.99 / month, with a 3-day free trial. (4,99 $ mỗi tháng, kèm 3 ngày dùng thử miễn phí.)
    static let monthly = "com.tnsubscription.core.tests.monthly"
    /// $29.99 / year — the cheapest per month. (29,99 $ mỗi năm — rẻ nhất tính theo tháng.)
    static let yearly = "com.tnsubscription.core.tests.yearly"
    /// $49.99 non-consumable. (49,99 $ non-consumable.)
    static let lifetime = "com.tnsubscription.core.tests.lifetime"
    /// $0.99 consumable, worth 100 coins. (0,99 $ consumable, đổi 100 coins.)
    static let coins = "com.tnsubscription.core.tests.100coins"

    static let allSubscriptions = [weekly, monthly, yearly]
    static let premiumProducts: Set<String> = [weekly, monthly, yearly, lifetime]
}

// MARK: - Base Case

/// Shared setup for the StoreKit integration suites.
/// (Phần setup dùng chung cho các suite integration test StoreKit.)
///
/// Each test gets a fresh `SKTestSession` with no transactions and a freshly configured
/// manager, because both `SKTestSession` state and the manager singleton outlive a single
/// test otherwise.
/// (Mỗi test nhận một `SKTestSession` mới không có giao dịch nào và một manager vừa được cấu
/// hình lại, vì nếu không thì cả state của `SKTestSession` và singleton của manager đều sống
/// lâu hơn một test.)
@MainActor
class TNCoreIntegrationTestCase: XCTestCase {

    var session: SKTestSession!

    override func setUp() async throws {
        try await super.setUp()

        let url = try XCTUnwrap(
            Bundle(for: TNCoreIntegrationTestCase.self).url(forResource: "TNCoreTests", withExtension: "storekit"),
            "The .storekit file is not in the test bundle; check the resources rule in project.yml."
        )

        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        // Without this, every purchase blocks on a system dialog that no test can tap.
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.storefront = "USA"
        session.locale = Locale(identifier: "en_US")

        TNSubscriptionCore.logLevel = .none
        TNSubscriptionCore.resetForTesting()
        TNConsumableManager.resetForTesting(currencies: ["coins"])
    }

    override func tearDown() async throws {
        TNSubscriptionCore.resetForTesting()
        TNConsumableManager.resetForTesting(currencies: ["coins"])
        session?.clearTransactions()
        session = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Configures the engine and waits for products and entitlements to settle.
    /// (Cấu hình engine rồi chờ sản phẩm và quyền lợi ổn định.)
    ///
    /// `configure` kicks off its own async bootstrap, so a test that read state immediately
    /// after it would race. Awaiting both explicitly makes every assertion deterministic.
    /// (`configure` tự chạy bootstrap bất đồng bộ, nên test đọc state ngay sau đó sẽ bị race.
    /// Chủ động `await` cả hai giúp mọi assertion trở nên tất định.)
    @discardableResult
    func makeCore(
        entitlements: [TNEntitlement] = [
            TNEntitlement(id: "Premium", productIDs: TestProduct.premiumProducts),
            // The yearly plan grants two entitlements, which is what exercises the
            // multi-entitlement path. (Gói năm cấp hai quyền lợi, đây là thứ kiểm tra
            // luồng nhiều entitlement.)
            TNEntitlement(id: "Sale", productIDs: [TestProduct.yearly]),
        ],
        offerings: [TNOffering] = [
            TNOffering(identifier: "default", productIDs: [
                TestProduct.weekly, TestProduct.monthly, TestProduct.yearly, TestProduct.lifetime,
            ]),
            TNOffering(identifier: "sale", productIDs: [TestProduct.yearly]),
        ],
        current: String? = "default",
        isIAPEnabled: Bool = true
    ) async -> TNSubscriptionCore {
        TNSubscriptionCore.configure(config: TNSubscriptionConfig(
            entitlements: entitlements,
            offerings: offerings,
            currentOfferingIdentifier: current,
            isIAPEnabled: isIAPEnabled
        ))

        let core = TNSubscriptionCore.shared!
        if isIAPEnabled {
            await core.loadProducts()
            await core.resolveEntitlement()
        }
        return core
    }

    /// Buys a product through the engine's own purchase path and returns the package used.
    /// (Mua một sản phẩm qua đúng luồng mua của engine và trả về package đã dùng.)
    @discardableResult
    func purchase(_ productID: String, with core: TNSubscriptionCore) async throws -> TNPackage {
        await core.loadOfferings(offeringIdentifier: "default")
        let package = try XCTUnwrap(
            core.availablePackages.first { $0.productIdentifier == productID },
            "\(productID) is not in the loaded offering: \(core.availablePackages.map(\.productIdentifier))."
        )
        try await core.purchaseAsync(package: package)
        return package
    }

    /// Makes a subscription genuinely lapse: cancel auto-renew, then expire it.
    /// (Làm một subscription thật sự hết hạn: tắt tự gia hạn, rồi cho hết hạn.)
    ///
    /// `expireSubscription` on its own does not lapse anything, because auto-renew is on by
    /// default and StoreKit immediately issues the next renewal. That is correct App Store
    /// behaviour, and it is also why a naive "expire and assert locked" test fails.
    /// (Chỉ gọi `expireSubscription` thì không hết hạn được, vì tự gia hạn đang bật theo mặc
    /// định và StoreKit lập tức tạo kỳ gia hạn mới. Đó là hành vi đúng của App Store, và cũng
    /// là lý do một test kiểu "expire rồi assert locked" sẽ fail.)
    func lapse(_ productID: String) throws {
        let transaction = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == productID },
            "No transaction for \(productID) to cancel."
        )
        try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
        try session.expireSubscription(productIdentifier: productID)
    }

    /// Re-resolves entitlements until `condition` holds.
    /// (Kiểm tra lại quyền lợi tới khi `condition` đúng.)
    ///
    /// StoreKit applies an expiry or a revocation asynchronously, so the first
    /// `resolveEntitlement()` after one can still read the old state. Asserting immediately
    /// makes such a test pass or fail depending on timing — which it did, alternating between
    /// runs. Polling with a fresh resolve each time removes the race.
    /// (StoreKit áp dụng việc hết hạn hoặc thu hồi một cách bất đồng bộ, nên lần
    /// `resolveEntitlement()` đầu tiên sau đó vẫn có thể đọc được trạng thái cũ. Assert ngay
    /// lập tức khiến test pass/fail tuỳ thời điểm — và nó đã fail xen kẽ giữa các lần chạy.
    /// Poll kèm resolve mới mỗi lần sẽ loại bỏ race này.)
    func waitUntilResolved(
        _ core: TNSubscriptionCore,
        timeout: TimeInterval = 5,
        _ message: String,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await core.resolveEntitlement()
            if condition() { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Timed out after \(timeout)s waiting for: \(message)")
    }

    /// Polls until `condition` holds, for the paths driven by `Transaction.updates`.
    /// (Chờ tới khi `condition` đúng, dùng cho các luồng do `Transaction.updates` điều khiển.)
    ///
    /// A fixed sleep would either be flaky or slow; polling is neither.
    /// (Một `sleep` cố định thì hoặc flaky hoặc chậm; polling thì không bị cả hai.)
    func waitUntil(
        timeout: TimeInterval = 5,
        _ message: String,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out after \(timeout)s waiting for: \(message)")
    }
}
