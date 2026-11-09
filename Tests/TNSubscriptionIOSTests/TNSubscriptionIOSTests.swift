import XCTest
import RevenueCat
@testable import TNSubscriptionIOS

final class TNSubscriptionIOSTests: XCTestCase {
    
    func testClientIdPersistenceAndMemoryCache() {
        let firstRead = TNSubscriptionIOS.clientId
        let secondRead = TNSubscriptionIOS.clientId
        XCTAssertFalse(firstRead.isEmpty)
        XCTAssertEqual(firstRead, secondRead)
        XCTAssertNotNil(UUID(uuidString: firstRead))
    }
    
    func testIdentityHeadersAndURLRequestExtension() {
        let headers = TNSubscriptionIOS.identityHeaders(userId: "user_123")
        XCTAssertEqual(headers["X-Client-Id"], TNSubscriptionIOS.clientId)
        XCTAssertEqual(headers["X-User-Id"], "user_123")
        
        var request = URLRequest(url: URL(string: "https://example.com/api/proxy/test")!)
        request.applyTNIdentityHeaders(userId: "user_456")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Client-Id"), TNSubscriptionIOS.clientId)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-User-Id"), "user_456")
    }
    
    @MainActor
    func testConfigureBypassModeUnlocksAllEntitlements() {
        let config = TNSubscriptionConfig(
            apiKey: "",
            entitlements: [
                TNEntitlement(id: "Premium", productIDs: ["com.test.weekly", "com.test.yearly"]),
                TNEntitlement(id: "Sale", productIDs: ["com.test.sale_yearly"])
            ],
            isIAPEnabled: false
        )
        
        TNSubscriptionIOS.configure(config: config)
        
        XCTAssertTrue(TNSubscriptionIOS.shared.isPremium)
        XCTAssertEqual(TNSubscriptionIOS.shared.entitlementState, .unlocked)
        XCTAssertTrue(TNSubscriptionIOS.shared.hasEntitlement("Premium"))
        XCTAssertTrue(TNSubscriptionIOS.shared.hasEntitlement("Sale"))
        XCTAssertFalse(TNSubscriptionIOS.shared.hasEntitlement("NonExistent"))
        XCTAssertEqual(TNSubscriptionIOS.shared.productIDs(for: "Sale"), ["com.test.sale_yearly"])
    }
    
    @MainActor
    func testConsumableManagerBalanceAndNegativeGuard() {
        let testCurrency = "test_coins_\(UUID().uuidString)"
        TNConsumableManager.configure(products: [
            TNConsumableProduct(id: "com.test.100coins", reward: 100, currency: testCurrency)
        ])
        
        let manager = TNConsumableManager.shared!
        XCTAssertEqual(manager.balance(for: testCurrency), 0)
        
        // Adding negative or zero should be ignored
        manager.addBalance(-50, for: testCurrency)
        XCTAssertEqual(manager.balance(for: testCurrency), 0)
        
        // Adding positive amount works
        manager.addBalance(100, for: testCurrency)
        XCTAssertEqual(manager.balance(for: testCurrency), 100)
        XCTAssertTrue(manager.canAfford(60, currency: testCurrency))
        XCTAssertFalse(manager.canAfford(-10, currency: testCurrency))
        
        // Deducting negative amount must be rejected (prevent exploit)
        XCTAssertFalse(manager.deductBalance(-50, for: testCurrency))
        XCTAssertEqual(manager.balance(for: testCurrency), 100)
        
        // Valid deduction works
        XCTAssertTrue(manager.deductBalance(40, for: testCurrency))
        XCTAssertEqual(manager.balance(for: testCurrency), 60)
        
        // Insufficient balance rejected
        XCTAssertFalse(manager.deductBalance(100, for: testCurrency))
        XCTAssertEqual(manager.balance(for: testCurrency), 60)
    }
    
    @MainActor
    func testInAppCurrencyManagerServerlessModeWithoutBackend() async throws {
        let currencyManager = TNInAppCurrencyManager.shared
        let testCode = "serverless_gems_\(UUID().uuidString)"
        
        XCTAssertEqual(currencyManager.balance(for: testCode), 0)
        XCTAssertFalse(currencyManager.deductLocalBalance(-10, for: testCode))
        XCTAssertFalse(currencyManager.deductLocalBalance(10, for: testCode))
        
        // Add local bonus currency in serverless mode
        currencyManager.addLocalBalance(150, for: testCode)
        XCTAssertEqual(currencyManager.balance(for: testCode), 150)
        
        // Spend via spendAsync() without any backend handler configured -> falls back to Keychain persistence
        let remaining = try await currencyManager.spendAsync(code: testCode, amount: 40)
        XCTAssertEqual(remaining, 110)
        XCTAssertEqual(currencyManager.balance(for: testCode), 110)
        
        // Reset adjustments
        currencyManager.resetLocalAdjustments(for: testCode)
        XCTAssertEqual(currencyManager.balance(for: testCode), 0)
    }
    
    func testDefaultPaywallViewPublicInitialization() {
        let config = DefaultPaywallConfig(
            appName: "TestApp",
            offeringIdentifier: "sale",
            entitlementId: "Sale",
            showRedeemCodeButton: true
        )
        let paywallView = TNDefaultPaywallView(config: config)
        XCTAssertEqual(paywallView.config.appName, "TestApp")
        XCTAssertEqual(paywallView.config.offeringIdentifier, "sale")
        XCTAssertEqual(paywallView.config.entitlementId, "Sale")
        XCTAssertTrue(paywallView.config.showRedeemCodeButton)
    }
    
    func testFormatSubscriptionPeriodAndIntroEligibilityDefault() {
        XCTAssertEqual(
            TNSubscriptionIOS.formatSubscriptionPeriod(RevenueCat.SubscriptionPeriod(value: 3, unit: .day), numberOfPeriods: 1),
            "3 Days"
        )
        XCTAssertEqual(
            TNSubscriptionIOS.formatSubscriptionPeriod(RevenueCat.SubscriptionPeriod(value: 1, unit: .week), numberOfPeriods: 1),
            "1 Week"
        )
        XCTAssertEqual(
            TNSubscriptionIOS.formatSubscriptionPeriod(RevenueCat.SubscriptionPeriod(value: 1, unit: .month), numberOfPeriods: 3),
            "3 Months"
        )
        XCTAssertFalse(TNSubscriptionIOS.shared?.isEligibleForIntroOffer(productID: "com.test.unknown") ?? false)
    }
}
