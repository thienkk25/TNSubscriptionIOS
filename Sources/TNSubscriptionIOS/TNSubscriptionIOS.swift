import Foundation
import StoreKit
import RevenueCat
@_exported import SwiftUI
import Combine

// MARK: - TNSubscriptionIOS Configuration

/// A single entitlement definition with its associated StoreKit Product IDs.
///
/// Example:
/// ```swift
/// TNEntitlement(id: "Premium", productIDs: ["com.app.weekly", "com.app.yearly"])
/// TNEntitlement(id: "Sale", productIDs: ["com.app.sale_yearly"])
/// ```
public struct TNEntitlement {
    /// The entitlement identifier as configured in RevenueCat (e.g. "Premium").
    public let id: String
    
    /// The set of StoreKit Product IDs that grant this entitlement.
    public let productIDs: Set<String>
    
    public init(id: String, productIDs: Set<String>) {
        self.id = id
        self.productIDs = productIDs
    }
}

/// Configuration for the TNSubscriptionIOS core engine.
/// Host apps must call `TNSubscriptionIOS.configure(...)` before using any functionality.
///
/// Usage:
/// ```swift
/// TNSubscriptionIOS.configure(config: TNSubscriptionConfig(
///     apiKey: "appl_xxxxx",
///     entitlements: [
///         TNEntitlement(id: "Premium", productIDs: ["com.app.weekly", "com.app.monthly", "com.app.yearly"]),
///         TNEntitlement(id: "Sale", productIDs: ["com.app.sale_yearly"]),
///     ]
/// ))
/// ```
public struct TNSubscriptionConfig {
    public let apiKey: String
    public let entitlements: [TNEntitlement]
    public let isIAPEnabled: Bool
    
    /// All product IDs across all entitlements (flattened for StoreKit lookup).
    var allProductIDs: Set<String> {
        entitlements.reduce(into: Set<String>()) { $0.formUnion($1.productIDs) }
    }
    
    /// All entitlement IDs (for RevenueCat lookup).
    var allEntitlementIDs: [String] {
        entitlements.map(\.id)
    }
    
    /// - Parameters:
    ///   - apiKey: Your RevenueCat API key.
    ///   - entitlements: Array of entitlements, each with its product IDs.
    ///   - isIAPEnabled: Set to `false` during development to bypass paywall. Default is `true`.
    public init(
        apiKey: String,
        entitlements: [TNEntitlement],
        isIAPEnabled: Bool = true
    ) {
        self.apiKey = apiKey
        self.entitlements = entitlements
        self.isIAPEnabled = isIAPEnabled
    }
    
    /// Convenience initializer for apps with a single entitlement.
    ///
    /// ```swift
    /// TNSubscriptionConfig(
    ///     apiKey: "appl_xxx",
    ///     entitlementId: "Premium",
    ///     productIDs: ["com.app.weekly", "com.app.yearly"]
    /// )
    /// ```
    public init(
        apiKey: String,
        entitlementId: String = "Premium",
        productIDs: Set<String>,
        isIAPEnabled: Bool = true
    ) {
        self.apiKey = apiKey
        self.entitlements = [TNEntitlement(id: entitlementId, productIDs: productIDs)]
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
///     entitlements: [
///         TNEntitlement(id: "Premium", productIDs: ["com.app.weekly", "com.app.yearly"]),
///         TNEntitlement(id: "Sale", productIDs: ["com.app.sale_yearly"]),
///     ]
/// ))
///
/// // 2. Check premium status (ANY entitlement active)
/// if TNSubscriptionIOS.shared.isPremium { ... }
///
/// // 3. Check specific entitlement
/// if TNSubscriptionIOS.shared.hasEntitlement("Sale") { ... }
///
/// // 4. Get all active entitlements
/// let active = TNSubscriptionIOS.shared.activeEntitlements // Set<String>
///
/// // 5. Present default paywall
/// TNSubscriptionIOS.presentDefaultPaywall(from: vc, config: ...)
///
/// // 6. Or present custom paywall
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
    
    /// `true` if ANY configured entitlement is currently active.
    @Published public var isPremium: Bool = false
    
    /// The set of currently active entitlement IDs (e.g. `["Premium", "Sale"]`).
    @Published public var activeEntitlements: Set<String> = []
    
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
            self.activeEntitlements = Set(config.allEntitlementIDs)
            return
        }
        
        Purchases.shared.delegate = self
        
        // Sync client_id as a custom attribute to RevenueCat
        Self.syncClientIdToRevenueCat()
        
        // 1. Immediate Synchronous Check (Cache) to prevent UI flicker
        if let cached = Purchases.shared.cachedCustomerInfo {
            self.customerInfo = cached
            let active = resolveActiveEntitlements(from: cached)
            
            // Only trust the cache if active. If inactive, stay .unknown to prevent false paywall flickers.
            if !active.isEmpty {
                self.activeEntitlements = active
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
    
    // MARK: - Public Entitlement Queries
    
    /// Checks if a specific entitlement is currently active.
    ///
    /// ```swift
    /// if TNSubscriptionIOS.shared.hasEntitlement("Sale") {
    ///     // Show sale-specific content
    /// }
    /// ```
    public func hasEntitlement(_ entitlementId: String) -> Bool {
        activeEntitlements.contains(entitlementId)
    }
    
    /// Returns the product IDs configured for a specific entitlement.
    public func productIDs(for entitlementId: String) -> Set<String> {
        config.entitlements.first(where: { $0.id == entitlementId })?.productIDs ?? []
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
    
    /// Resolves active entitlements from a CustomerInfo object.
    private func resolveActiveEntitlements(from info: CustomerInfo) -> Set<String> {
        var active = Set<String>()
        for entitlement in config.entitlements {
            if info.entitlements[entitlement.id]?.isActive == true {
                active.insert(entitlement.id)
            }
        }
        return active
    }
    
    /// Main source of truth resolver
    @MainActor
    public func resolveEntitlement() async {
        if !config.isIAPEnabled {
            updateState(isPremium: true, state: .unlocked, activeEntitlements: Set(config.allEntitlementIDs))
            return
        }
        
        // Priority 1: StoreKit 2 Local Entitlements (Works Offline, highly reliable)
        let storeKitActive = await syncWithStoreKit()
        if !storeKitActive.isEmpty {
            if self.entitlementState != .unlocked {
                updateState(isPremium: true, state: .unlocked, activeEntitlements: storeKitActive)
            } else {
                // Merge with existing active entitlements
                self.activeEntitlements.formUnion(storeKitActive)
            }
            // Fire and forget RC sync for backend parity
            Task { await syncWithRevenueCat() }
            return
        }
        
        // Priority 2: RevenueCat Network/Cache Check
        let rcActive = await syncWithRevenueCat()
        let hasPremium = !rcActive.isEmpty
        let newState: EntitlementState = hasPremium ? .unlocked : .locked
        if self.entitlementState != newState || self.activeEntitlements != rcActive {
            updateState(isPremium: hasPremium, state: newState, activeEntitlements: rcActive)
        }
    }
    
    /// Checks StoreKit 2 local state directly. Returns the set of active entitlement IDs.
    private func syncWithStoreKit() async -> Set<String> {
        let cachedValidProductID = UserDefaults.standard.string(forKey: productIDCacheKey)
        var activeIDs = Set<String>()
        
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            
            if transaction.revocationDate == nil {
                // Check against configured Product IDs per entitlement
                for entitlement in config.entitlements {
                    if entitlement.productIDs.contains(transaction.productID) {
                        activeIDs.insert(entitlement.id)
                    }
                }
                
                // Fallback to dynamically cached Product ID from RevenueCat
                if activeIDs.isEmpty, let cachedID = cachedValidProductID, !cachedID.isEmpty {
                    if transaction.productID == cachedID {
                        // We don't know which entitlement it belongs to, mark first as active
                        if let first = config.entitlements.first {
                            activeIDs.insert(first.id)
                        }
                    }
                }
            }
        }
        return activeIDs
    }
    
    /// Syncs and checks RevenueCat state. Returns the set of active entitlement IDs.
    @MainActor
    @discardableResult
    private func syncWithRevenueCat() async -> Set<String> {
        do {
            let info = try await Purchases.shared.customerInfo()
            updateState(info: info)
            let active = resolveActiveEntitlements(from: info)
            
            // Cache active product IDs for StoreKit offline fallback
            for entitlement in config.entitlements {
                if let ent = info.entitlements[entitlement.id], ent.isActive {
                    UserDefaults.standard.set(ent.productIdentifier, forKey: productIDCacheKey)
                    break // Cache one is enough for fallback
                }
            }
            return active
        } catch {
            if let cached = Purchases.shared.cachedCustomerInfo {
                updateState(info: cached)
                let active = resolveActiveEntitlements(from: cached)
                for entitlement in config.entitlements {
                    if let ent = cached.entitlements[entitlement.id], ent.isActive {
                        UserDefaults.standard.set(ent.productIdentifier, forKey: productIDCacheKey)
                        break
                    }
                }
                return active
            }
            return []
        }
    }
    
    // MARK: - Offerings & Purchase
    
    /// The product ID of the user's current active plan (first active entitlement found).
    public var currentPlanProductID: String? {
        for entitlement in config.entitlements {
            if let ent = customerInfo?.entitlements[entitlement.id], ent.isActive {
                return ent.productIdentifier
            }
        }
        return nil
    }
    
    /// The product ID for a specific entitlement, if active.
    public func currentProductID(for entitlementId: String) -> String? {
        customerInfo?.entitlements[entitlementId]?.productIdentifier
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
        let previousActive = self.activeEntitlements
        
        // Attempt StoreKit 2 sync first
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            updateState(isPremium: previousPremium, state: previousState, activeEntitlements: previousActive)
            return false
        } catch {
            // Proceed to RevenueCat fallback check
        }
        
        let storeKitActive = await syncWithStoreKit()
        if !storeKitActive.isEmpty {
            updateState(isPremium: true, state: .unlocked, activeEntitlements: storeKitActive)
            Self.syncClientIdToRevenueCat()
            Task { try? await Purchases.shared.restorePurchases() }
            return true
        }
        
        do {
            let info = try await Purchases.shared.restorePurchases()
            let active = resolveActiveEntitlements(from: info)
            let isSuccess = !active.isEmpty
            updateState(isPremium: isSuccess, state: isSuccess ? .unlocked : .locked, activeEntitlements: active, info: info)
            if isSuccess { Self.syncClientIdToRevenueCat() }
            return isSuccess
        } catch {
            updateState(isPremium: previousPremium, state: previousState, activeEntitlements: previousActive)
            throw error
        }
    }
    
    @MainActor
    private func updateState(isPremium: Bool? = nil, state: EntitlementState? = nil, activeEntitlements: Set<String>? = nil, info: CustomerInfo? = nil) {
        if !config.isIAPEnabled {
            self.isPremium = true
            self.entitlementState = .unlocked
            self.activeEntitlements = Set(config.allEntitlementIDs)
            if let info = info { self.customerInfo = info }
            return
        }
        if let isPremium = isPremium { self.isPremium = isPremium }
        if let state = state { self.entitlementState = state }
        if let activeEntitlements = activeEntitlements { self.activeEntitlements = activeEntitlements }
        if let info = info { self.customerInfo = info }
    }
    
    @MainActor
    public func forceUpdateState(from info: CustomerInfo) {
        if !config.isIAPEnabled {
            self.isPremium = true
            self.entitlementState = .unlocked
            self.activeEntitlements = Set(config.allEntitlementIDs)
            self.customerInfo = info
            return
        }
        let active = resolveActiveEntitlements(from: info)
        let isActive = !active.isEmpty
        self.entitlementState = isActive ? .unlocked : .locked
        self.isPremium = isActive
        self.activeEntitlements = active
        self.customerInfo = info
        
        // Cache first active product ID for offline fallback
        for entitlement in config.entitlements {
            if let ent = info.entitlements[entitlement.id], ent.isActive {
                UserDefaults.standard.set(ent.productIdentifier, forKey: productIDCacheKey)
                break
            }
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
                self.activeEntitlements = Set(self.config.allEntitlementIDs)
                return
            }
            
            let active = self.resolveActiveEntitlements(from: customerInfo)
            let isActive = !active.isEmpty
            
            // Cache first active product ID
            for entitlement in self.config.entitlements {
                if let ent = customerInfo.entitlements[entitlement.id], ent.isActive {
                    UserDefaults.standard.set(ent.productIdentifier, forKey: self.productIDCacheKey)
                    break
                }
            }
            
            self.activeEntitlements = active
            self.entitlementState = isActive ? .unlocked : .locked
            self.isPremium = isActive
        }
    }
}
