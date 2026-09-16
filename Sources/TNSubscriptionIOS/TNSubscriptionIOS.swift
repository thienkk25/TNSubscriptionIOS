import Foundation
import StoreKit
import RevenueCat
@_exported import SwiftUI
import Combine

// MARK: - TNSubscriptionIOS Configuration

/// Configuration for the TNSubscriptionIOS core engine.
/// Host apps must call `TNSubscriptionIOS.configure(...)` before using any functionality.
public struct TNSubscriptionConfig {
    public let apiKey: String
    public let entitlementId: String
    public let productIDs: Set<String>
    public let isIAPEnabled: Bool
    
    /// - Parameters:
    ///   - apiKey: Your RevenueCat API key.
    ///   - entitlementId: The entitlement identifier configured in RevenueCat (e.g. "Premium").
    ///   - productIDs: The set of StoreKit Product IDs to validate locally (e.g. "com.app.weekly").
    ///   - isIAPEnabled: Set to `false` during development to bypass paywall. Default is `true`.
    public init(
        apiKey: String,
        entitlementId: String = "Premium",
        productIDs: Set<String>,
        isIAPEnabled: Bool = true
    ) {
        self.apiKey = apiKey
        self.entitlementId = entitlementId
        self.productIDs = productIDs
        self.isIAPEnabled = isIAPEnabled
    }
}

// MARK: - TNSubscriptionIOS (Public API)

/// The main entry point for TNSubscriptionIOS.
///
/// Usage:
/// ```swift
/// // 1. Configure once at app launch
/// TNSubscriptionIOS.configure(config: TNSubscriptionConfig(
///     apiKey: "appl_xxxxx",
///     productIDs: ["com.app.weekly", "com.app.yearly"]
/// ))
///
/// // 2. Check premium status
/// if TNSubscriptionIOS.shared.isPremium { ... }
///
/// // 3. Present default paywall
/// TNSubscriptionIOS.presentDefaultPaywall(from: vc, config: ...)
///
/// // 4. Or present custom paywall
/// TNSubscriptionIOS.presentPaywall(from: vc) { MyCustomPaywallView() }
/// ```
public final class TNSubscriptionIOS: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    /// The shared instance. Only available after `configure(...)` is called.
    public private(set) static var shared: TNSubscriptionIOS!
    
    // MARK: - Published State
    
    public enum EntitlementState {
        case unknown
        case locked
        case unlocked
    }
    
    @Published public var entitlementState: EntitlementState = .unknown
    @Published public var customerInfo: CustomerInfo?
    @Published public var isPremium: Bool = false
    @Published public var availablePackages: [Package] = []
    @Published public var isLoadingOfferings = false
    @Published public var isPurchasing = false
    @Published public var offeringsError: String?
    
    // MARK: - Internal Config
    
    private let config: TNSubscriptionConfig
    private let productIDCacheKey = "tn_cachedPremiumProductID"
    private var updatesTask: Task<Void, Never>? = nil
    
    // MARK: - Configure
    
    /// Configures the TNSubscriptionIOS SDK. Must be called once before any other usage,
    /// typically in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// - Parameter config: The subscription configuration.
    public static func configure(config: TNSubscriptionConfig) {
        // Configure RevenueCat
        Purchases.configure(withAPIKey: config.apiKey)
        
        // Create shared instance
        let instance = TNSubscriptionIOS(config: config)
        shared = instance
    }
    
    private init(config: TNSubscriptionConfig) {
        self.config = config
        
        super.init()
        
        if !config.isIAPEnabled {
            self.entitlementState = .unlocked
            self.isPremium = true
            return
        }
        
        Purchases.shared.delegate = self
        
        // Sync client_id as a custom attribute to RevenueCat
        Self.syncClientIdToRevenueCat()
        
        // 1. Immediate Synchronous Check (Cache) to prevent UI flicker
        if let cached = Purchases.shared.cachedCustomerInfo {
            self.customerInfo = cached
            let isActive = cached.entitlements[config.entitlementId]?.isActive == true
            
            // Only trust the cache if it's active. If it's inactive, we must wait for
            // StoreKit 2 to confirm (stay .unknown) to prevent false paywall flickers.
            if isActive {
                self.entitlementState = .unlocked
                self.isPremium = true
            } else {
                self.entitlementState = .unknown
                self.isPremium = false
            }
        } else {
            self.entitlementState = .unknown
            self.isPremium = false
        }
        
        // 2. Listen for external StoreKit 2 transactions (e.g., App Store renewals)
        updatesTask = Task {
            for await _ in Transaction.updates {
                await resolveEntitlement()
            }
        }
        
        // 3. Resolve Entitlement asynchronously
        Task {
            await resolveEntitlement()
        }
    }
    
    deinit {
        updatesTask?.cancel()
    }
    
    // MARK: - Shared Client ID (TN Studio Proxy & RevenueCat)
    
    private static let clientIdKeychainAccount = "client_id"
    private static let clientIdUserDefaultsKey = "persistent_client_id"
    
    /// A persistent client ID shared between RevenueCat and TN Studio proxy.
    /// Survives app reinstalls via Keychain. Falls back to UserDefaults.
    ///
    /// Use this value for the `X-Client-Id` HTTP header in your API calls:
    /// ```
    /// request.setValue(TNSubscriptionIOS.clientId, forHTTPHeaderField: "X-Client-Id")
    /// ```
    public static var clientId: String {
        // 1. Try Keychain first (survives reinstall)
        if let keychainId = loadFromKeychain(account: clientIdKeychainAccount), !keychainId.isEmpty {
            return keychainId
        }
        
        // 2. Fallback: check UserDefaults
        if let defaultsId = UserDefaults.standard.string(forKey: clientIdUserDefaultsKey), !defaultsId.isEmpty {
            // Migrate to Keychain for durability
            saveToKeychain(account: clientIdKeychainAccount, value: defaultsId)
            return defaultsId
        }
        
        // 3. Generate new UUID and persist everywhere
        let newId = UUID().uuidString
        saveToKeychain(account: clientIdKeychainAccount, value: newId)
        UserDefaults.standard.set(newId, forKey: clientIdUserDefaultsKey)
        return newId
    }
    
    // MARK: - Keychain Helpers
    
    private static func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    private static func saveToKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    /// Syncs the persistent client_id to RevenueCat as a custom subscriber attribute.
    private static func syncClientIdToRevenueCat() {
        let id = clientId
        Purchases.shared.attribution.setAttributes(["client_id": id])
        #if DEBUG
        print("[TNSubscriptionIOS] Synced client_id attribute: \(id)")
        #endif
    }
    
    // MARK: - Entitlement Resolution
    
    /// Main source of truth resolver
    @MainActor
    public func resolveEntitlement() async {
        if !config.isIAPEnabled {
            updateState(isPremium: true, state: .unlocked)
            return
        }
        
        // Priority 1: StoreKit 2 Local Entitlements (Works Offline, highly reliable)
        if await syncWithStoreKit() {
            if self.entitlementState != .unlocked {
                updateState(isPremium: true, state: .unlocked)
            }
            // Fire and forget RC sync for backend parity
            Task { await syncWithRevenueCat() }
            return
        }
        
        // Priority 2: RevenueCat Network/Cache Check
        let rcHasPremium = await syncWithRevenueCat()
        let newState: EntitlementState = rcHasPremium ? .unlocked : .locked
        if self.entitlementState != newState {
            updateState(isPremium: rcHasPremium, state: newState)
        }
    }
    
    /// Checks StoreKit 2 local state directly
    private func syncWithStoreKit() async -> Bool {
        let cachedValidProductID = UserDefaults.standard.string(forKey: productIDCacheKey)
        
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            
            if transaction.revocationDate == nil {
                // Priority 1: Check against configured Premium Product IDs
                if config.productIDs.contains(transaction.productID) {
                    return true
                }
                
                // Priority 2: Fallback to dynamically cached Product ID from RevenueCat
                if let cachedID = cachedValidProductID, !cachedID.isEmpty {
                    if transaction.productID == cachedID {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    /// Syncs and checks RevenueCat state
    @MainActor
    @discardableResult
    private func syncWithRevenueCat() async -> Bool {
        do {
            let info = try await Purchases.shared.customerInfo()
            updateState(info: info)
            if let entitlement = info.entitlements[config.entitlementId], entitlement.isActive {
                UserDefaults.standard.set(entitlement.productIdentifier, forKey: productIDCacheKey)
                return true
            }
            return false
        } catch {
            if let cached = Purchases.shared.cachedCustomerInfo {
                updateState(info: cached)
                if let entitlement = cached.entitlements[config.entitlementId], entitlement.isActive {
                    UserDefaults.standard.set(entitlement.productIdentifier, forKey: productIDCacheKey)
                    return true
                }
            }
            return false
        }
    }
    
    // MARK: - Offerings & Purchase
    
    /// The product ID of the user's current active plan, if any.
    public var currentPlanProductID: String? {
        customerInfo?.entitlements[config.entitlementId]?.productIdentifier
    }
    
    /// A human-readable display name for the user's current plan.
    public var currentPlanDisplayName: String? {
        guard let productID = currentPlanProductID else { return nil }
        return Self.displayName(forProductID: productID)
    }
    
    /// Returns a human-readable name for a given product ID.
    public static func displayName(forProductID productID: String) -> String {
        if productID.contains("week") { return NSLocalizedString("Weekly", comment: "") }
        if productID.contains("month") { return NSLocalizedString("Monthly", comment: "") }
        if productID.contains("year") || productID.contains("annual") { return NSLocalizedString("Yearly", comment: "") }
        if productID.contains("life") { return NSLocalizedString("Lifetime", comment: "") }
        return NSLocalizedString("Premium", comment: "")
    }
    
    /// Sort order for package types (used by default paywall).
    public static func packageSortOrder(_ package: Package) -> Int {
        switch package.packageType {
        case .lifetime: return 0
        case .annual: return 1
        case .sixMonth: return 2
        case .threeMonth: return 3
        case .twoMonth: return 4
        case .monthly: return 5
        case .weekly: return 6
        case .custom: return 7
        case .unknown: return 8
        @unknown default: return 9
        }
    }
    
    /// Whether a package should be marked as "recommended" (defaults to annual plans).
    nonisolated public static func isRecommendedPackage(_ package: Package) -> Bool {
        package.packageType == .annual || package.storeProduct.productIdentifier.contains("yearly")
    }
    
    /// Fetches available offerings from RevenueCat (fire-and-forget).
    public func fetchOfferings() {
        Task {
            await loadOfferings()
        }
    }
    
    /// Loads available offerings from RevenueCat.
    @MainActor
    public func loadOfferings() async {
        isLoadingOfferings = true
        offeringsError = nil
        defer { isLoadingOfferings = false }
        
        do {
            let offerings = try await Purchases.shared.offerings()
            let packages = offerings.current?.availablePackages ?? []
            availablePackages = packages.sorted {
                Self.packageSortOrder($0) < Self.packageSortOrder($1)
            }
            if availablePackages.isEmpty {
                offeringsError = NSLocalizedString("No subscription plans are available right now. Please try again later.", comment: "")
            }
        } catch {
            offeringsError = error.localizedDescription
            availablePackages = []
        }
    }
    
    /// Purchases a package.
    public func purchase(package: Package, completion: @escaping (Result<CustomerInfo, Error>) -> Void) {
        Task {
            await MainActor.run { isPurchasing = true }
            defer { Task { @MainActor in self.isPurchasing = false } }
            
            do {
                let result = try await Purchases.shared.purchase(package: package)
                await forceUpdateState(from: result.customerInfo)
                if result.userCancelled {
                    completion(.failure(PurchaseFlowError.userCancelled))
                } else {
                    completion(.success(result.customerInfo))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    public enum PurchaseFlowError: LocalizedError {
        case userCancelled
        
        public var errorDescription: String? {
            switch self {
            case .userCancelled:
                return NSLocalizedString("Purchase was cancelled.", comment: "")
            }
        }
    }
    
    // MARK: - Legacy / Helper Methods
    
    /// Triggers an asynchronous entitlement check.
    public func checkSubscriptionStatus() {
        Task {
            await resolveEntitlement()
        }
    }
    
    /// Restores purchases via StoreKit 2 + RevenueCat.
    public func restorePurchases(completion: @escaping (Result<Bool, Error>) -> Void) {
        Task {
            do {
                let success = try await restorePurchasesAsync()
                completion(.success(success))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    @MainActor
    private func restorePurchasesAsync() async throws -> Bool {
        let previousState = self.entitlementState
        let previousPremium = self.isPremium
        
        // Attempt StoreKit 2 sync first
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            updateState(isPremium: previousPremium, state: previousState)
            return false
        } catch {
            // Proceed to RevenueCat fallback check
        }
        
        if await syncWithStoreKit() {
            updateState(isPremium: true, state: .unlocked)
            Self.syncClientIdToRevenueCat()
            Task { try? await Purchases.shared.restorePurchases() }
            return true
        }
        
        do {
            let info = try await Purchases.shared.restorePurchases()
            let isSuccess = info.entitlements[config.entitlementId]?.isActive == true
            updateState(isPremium: isSuccess, state: isSuccess ? .unlocked : .locked, info: info)
            if isSuccess { Self.syncClientIdToRevenueCat() }
            return isSuccess
        } catch {
            updateState(isPremium: previousPremium, state: previousState)
            throw error
        }
    }
    
    @MainActor
    private func updateState(isPremium: Bool? = nil, state: EntitlementState? = nil, info: CustomerInfo? = nil) {
        if !config.isIAPEnabled {
            self.isPremium = true
            self.entitlementState = .unlocked
            if let info = info { self.customerInfo = info }
            return
        }
        if let isPremium = isPremium { self.isPremium = isPremium }
        if let state = state { self.entitlementState = state }
        if let info = info { self.customerInfo = info }
    }
    
    @MainActor
    public func forceUpdateState(from info: CustomerInfo) {
        if !config.isIAPEnabled {
            self.isPremium = true
            self.entitlementState = .unlocked
            self.customerInfo = info
            return
        }
        let isActive = info.entitlements[config.entitlementId]?.isActive == true
        self.entitlementState = isActive ? .unlocked : .locked
        self.isPremium = isActive
        self.customerInfo = info
        
        if isActive, let productID = info.entitlements[config.entitlementId]?.productIdentifier {
            UserDefaults.standard.set(productID, forKey: productIDCacheKey)
        }
        
        // Refresh entitlement state after 1 second sandbox delay safety net
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await resolveEntitlement()
        }
    }
}

// MARK: - PurchasesDelegate

extension TNSubscriptionIOS: PurchasesDelegate {
    nonisolated public func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.customerInfo = customerInfo
            if !self.config.isIAPEnabled {
                self.isPremium = true
                self.entitlementState = .unlocked
                return
            }
            let entitlement = customerInfo.entitlements[self.config.entitlementId]
            let isActive = entitlement?.isActive == true
            
            if isActive, let productID = entitlement?.productIdentifier {
                UserDefaults.standard.set(productID, forKey: self.productIDCacheKey)
            }
            
            self.entitlementState = isActive ? .unlocked : .locked
            self.isPremium = isActive
        }
    }
}
