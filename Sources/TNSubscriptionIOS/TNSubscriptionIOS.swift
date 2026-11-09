import Foundation
import StoreKit
import RevenueCat
@_exported import SwiftUI
import Combine
import UIKit
import Security

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
    /// Set to `true` only if your app has a Backend/Proxy and wants `client_id` synced to RevenueCat at launch.
    /// Defaults to `false` (serverless apps do not need backend identity sync; accessing `TNSubscriptionIOS.clientId` will still lazily sync if needed).
    public let enableBackendIdentitySync: Bool
    
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
    ///   - enableBackendIdentitySync: Set to `true` if your app uses a custom Backend/Proxy. Default is `false`.
    public init(
        apiKey: String,
        entitlements: [TNEntitlement],
        isIAPEnabled: Bool = true,
        enableBackendIdentitySync: Bool = false
    ) {
        self.apiKey = apiKey
        self.entitlements = entitlements
        self.isIAPEnabled = isIAPEnabled
        self.enableBackendIdentitySync = enableBackendIdentitySync
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
        isIAPEnabled: Bool = true,
        enableBackendIdentitySync: Bool = false
    ) {
        self.apiKey = apiKey
        self.entitlements = [TNEntitlement(id: entitlementId, productIDs: productIDs)]
        self.isIAPEnabled = isIAPEnabled
        self.enableBackendIdentitySync = enableBackendIdentitySync
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
    /// Introductory offer / free trial eligibility keyed by StoreKit `productIdentifier`.
    @Published public private(set) var introEligibility: [String: IntroEligibilityStatus] = [:]
    @Published public var isLoadingOfferings = false
    @Published public var isPurchasing = false
    @Published public var offeringsError: String?
    
    // MARK: - Internal Config
    
    private let config: TNSubscriptionConfig
    private let productIDCacheKey = "tn_cachedPremiumProductID"
    private let productIDMapCacheKey = "tn_cachedEntitlementProductMap"
    private var updatesTask: Task<Void, Never>? = nil
    
    // MARK: - Configure
    
    /// Configures the TNSubscriptionIOS SDK. Must be called once before any other usage,
    /// typically in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// - Parameter config: The subscription configuration.
    public static func configure(config: TNSubscriptionConfig) {
        // Configure RevenueCat when a non-empty API key is provided
        if !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Purchases.configure(withAPIKey: config.apiKey)
        }
        
        // Create shared instance
        let instance = TNSubscriptionIOS(config: config)
        shared = instance
        
        // Only refresh currencies at launch if the app has already accessed TNInAppCurrencyManager
        if Purchases.isConfigured, TNInAppCurrencyManager.isInitialized {
            TNInAppCurrencyManager.shared.fetchCurrencies()
        }
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
        
        guard Purchases.isConfigured else {
            self.entitlementState = .locked
            self.isPremium = false
            return
        }
        
        Purchases.shared.delegate = self
        
        // Only sync client_id on launch if explicitly enabled for Backend/Proxy projects
        if config.enableBackendIdentitySync {
            Self.syncClientIdToRevenueCat()
        }
        
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
    
    // MARK: - In-App Currencies (RevenueCat)
    
    /// Access the RevenueCat In-App Currency manager.
    public var currencyManager: TNInAppCurrencyManager {
        TNInAppCurrencyManager.shared
    }
    
    /// Returns the current balance for a virtual currency code (e.g. "coins").
    public func currencyBalance(for code: String) -> Int {
        TNInAppCurrencyManager.shared.balance(for: code)
    }
    
    // MARK: - Persistent Client ID & Identity Headers (Backend API & RevenueCat)
    
    private static let clientIdKeychainAccount = "client_id"
    private static let clientIdUserDefaultsKey = "persistent_client_id"
    internal static let keychainService: String = Bundle.main.bundleIdentifier ?? "com.tnsubscription.ios"
    private static var cachedClientId: String?
    private static var didSyncClientIdToRC = false
    private static let clientIdLock = NSLock()
    
    /// A persistent, unique client ID stored in Keychain (survives app reinstalls) and cached in memory for $O(1)$ access.
    ///
    /// **Optional**: Only needed when your app calls a custom Backend API or Proxy Gateway (`X-Client-Id` header).
    /// Serverless apps (using only StoreKit 2 / RevenueCat) do not need to use this property.
    public static var clientId: String {
        clientIdLock.lock()
        let resolvedId: String
        if let memoryCached = cachedClientId, !memoryCached.isEmpty {
            resolvedId = memoryCached
        } else if let keychainId = loadFromKeychain(account: clientIdKeychainAccount), !keychainId.isEmpty {
            cachedClientId = keychainId
            resolvedId = keychainId
        } else if let defaultsId = UserDefaults.standard.string(forKey: clientIdUserDefaultsKey), !defaultsId.isEmpty {
            saveToKeychain(account: clientIdKeychainAccount, value: defaultsId)
            cachedClientId = defaultsId
            resolvedId = defaultsId
        } else {
            let newId = UUID().uuidString
            saveToKeychain(account: clientIdKeychainAccount, value: newId)
            UserDefaults.standard.set(newId, forKey: clientIdUserDefaultsKey)
            cachedClientId = newId
            resolvedId = newId
        }
        let shouldSync = !didSyncClientIdToRC && Purchases.isConfigured
        if shouldSync {
            didSyncClientIdToRC = true
        }
        clientIdLock.unlock()
        
        if shouldSync {
            Purchases.shared.attribution.setAttributes(["client_id": resolvedId])
        }
        return resolvedId
    }
    
    /// The hardware vendor device identifier (`UIDevice.current.identifierForVendor?.uuidString`).
    public static var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? ""
    }
    
    /// Standard TN Studio Proxy Gateway client identity HTTP headers (`X-Client-Id`, `X-Device-Id`, and optional `X-User-Id`).
    ///
    /// - Parameter userId: Optional authenticated user ID.
    /// - Returns: Dictionary of HTTP header fields.
    public static func identityHeaders(userId: String? = nil) -> [String: String] {
        var headers: [String: String] = [
            "X-Client-Id": clientId
        ]
        let devId = deviceId
        if !devId.isEmpty {
            headers["X-Device-Id"] = devId
        }
        if let uid = userId, !uid.isEmpty {
            headers["X-User-Id"] = uid
        }
        return headers
    }
    
    // MARK: - Keychain Helpers
    
    internal static func loadFromKeychain(account: String) -> String? {
        // 1. Query with kSecAttrService
        let scopedQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let scopedStatus = SecItemCopyMatching(scopedQuery as CFDictionary, &result)
        if scopedStatus == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty {
            return value
        }
        
        // 2. Backward-compatible fallback: query legacy item without kSecAttrService and migrate
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var legacyResult: AnyObject?
        let legacyStatus = SecItemCopyMatching(legacyQuery as CFDictionary, &legacyResult)
        guard legacyStatus == errSecSuccess, let data = legacyResult as? Data, let legacyValue = String(data: data, encoding: .utf8), !legacyValue.isEmpty else {
            return nil
        }
        saveToKeychain(account: account, value: legacyValue)
        return legacyValue
    }
    
    internal static func saveToKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    /// Syncs the persistent client_id to RevenueCat as a custom subscriber attribute.
    private static func syncClientIdToRevenueCat() {
        guard Purchases.isConfigured else { return }
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
    
    /// Caches active entitlement -> productID mapping for offline StoreKit 2 verification, or clears cache if none active.
    private func cacheActiveEntitlementProducts(from info: CustomerInfo) {
        var entitlementMap: [String: String] = [:]
        var firstProductID: String?
        
        for entitlement in config.entitlements {
            if let ent = info.entitlements[entitlement.id], ent.isActive {
                entitlementMap[entitlement.id] = ent.productIdentifier
                if firstProductID == nil {
                    firstProductID = ent.productIdentifier
                }
            }
        }
        
        if let firstProductID = firstProductID {
            UserDefaults.standard.set(firstProductID, forKey: productIDCacheKey)
            UserDefaults.standard.set(entitlementMap, forKey: productIDMapCacheKey)
        } else {
            UserDefaults.standard.removeObject(forKey: productIDCacheKey)
            UserDefaults.standard.removeObject(forKey: productIDMapCacheKey)
        }
    }
    
    /// Main source of truth resolver
    @MainActor
    public func resolveEntitlement() async {
        if !config.isIAPEnabled {
            updateState(isPremium: true, state: .unlocked, activeEntitlements: Set(config.allEntitlementIDs))
            return
        }
        
        // Priority 1: StoreKit 2 Local Entitlements (Works Offline, immediate unlock)
        let storeKitActive = await syncWithStoreKit()
        if !storeKitActive.isEmpty {
            updateState(isPremium: true, state: .unlocked, activeEntitlements: storeKitActive)
            // Also sync with RevenueCat to pick up cross-platform/promotional entitlements and update customerInfo
            Task { @MainActor in
                let rcActive = await self.syncWithRevenueCat()
                let combined = storeKitActive.union(rcActive)
                let hasPremium = !combined.isEmpty
                self.updateState(isPremium: hasPremium, state: hasPremium ? .unlocked : .locked, activeEntitlements: combined)
            }
            return
        }
        
        // Priority 2: RevenueCat Network/Cache Check
        let rcActive = await syncWithRevenueCat()
        let hasPremium = !rcActive.isEmpty
        let newState: EntitlementState = hasPremium ? .unlocked : .locked
        if self.entitlementState != newState || self.activeEntitlements != rcActive || self.isPremium != hasPremium {
            updateState(isPremium: hasPremium, state: newState, activeEntitlements: rcActive)
        }
    }
    
    /// Checks StoreKit 2 local state directly. Returns the set of active entitlement IDs.
    private func syncWithStoreKit() async -> Set<String> {
        let cachedMap = UserDefaults.standard.dictionary(forKey: productIDMapCacheKey) as? [String: String] ?? [:]
        let cachedValidProductID = UserDefaults.standard.string(forKey: productIDCacheKey)
        var activeIDs = Set<String>()
        let now = Date()
        
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            
            guard transaction.revocationDate == nil else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate < now {
                continue
            }
            
            var matchedConfiguredEntitlement = false
            // Check against configured Product IDs per entitlement
            for entitlement in config.entitlements {
                if entitlement.productIDs.contains(transaction.productID) {
                    activeIDs.insert(entitlement.id)
                    matchedConfiguredEntitlement = true
                }
            }
            
            // Fallback to dynamically cached entitlement -> productID map from RevenueCat
            if !matchedConfiguredEntitlement {
                for (entitlementId, cachedProdId) in cachedMap where cachedProdId == transaction.productID {
                    activeIDs.insert(entitlementId)
                    matchedConfiguredEntitlement = true
                }
            }
            
            // Legacy single productID fallback
            if !matchedConfiguredEntitlement, activeIDs.isEmpty, let cachedID = cachedValidProductID, !cachedID.isEmpty {
                if transaction.productID == cachedID, let first = config.entitlements.first {
                    activeIDs.insert(first.id)
                }
            }
        }
        return activeIDs
    }
    
    /// Syncs and checks RevenueCat state. Returns the set of active entitlement IDs.
    @MainActor
    @discardableResult
    private func syncWithRevenueCat() async -> Set<String> {
        guard Purchases.isConfigured else { return [] }
        do {
            let info = try await Purchases.shared.customerInfo()
            updateState(info: info)
            let active = resolveActiveEntitlements(from: info)
            cacheActiveEntitlementProducts(from: info)
            return active
        } catch {
            if let cached = Purchases.shared.cachedCustomerInfo {
                updateState(info: cached)
                let active = resolveActiveEntitlements(from: cached)
                cacheActiveEntitlementProducts(from: cached)
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
        guard let ent = customerInfo?.entitlements[entitlementId], ent.isActive else { return nil }
        return ent.productIdentifier
    }
    
    /// A human-readable display name for the user's current plan.
    public var currentPlanDisplayName: String? {
        guard let productID = currentPlanProductID else { return nil }
        return Self.displayName(forProductID: productID)
    }
    
    /// Returns a human-readable name for a given product ID.
    public static func displayName(forProductID productID: String) -> String {
        let lower = productID.lowercased()
        if lower.contains("week") { return NSLocalizedString("Weekly", comment: "") }
        if lower.contains("month") { return NSLocalizedString("Monthly", comment: "") }
        if lower.contains("year") || lower.contains("annual") { return NSLocalizedString("Yearly", comment: "") }
        if lower.contains("life") { return NSLocalizedString("Lifetime", comment: "") }
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
        package.packageType == .annual || package.storeProduct.productIdentifier.lowercased().contains("yearly")
    }
    
    /// Fetches available offerings from RevenueCat (fire-and-forget).
    /// - Parameter offeringIdentifier: Optional specific offering identifier (e.g., `"sale"`). Defaults to `nil` (uses `offerings.current`).
    public func fetchOfferings(offeringIdentifier: String? = nil) {
        Task {
            await loadOfferings(offeringIdentifier: offeringIdentifier)
        }
    }
    
    /// Loads available offerings from RevenueCat.
    /// - Parameter offeringIdentifier: Optional specific offering identifier (e.g., `"sale"`). Defaults to `nil` (uses `offerings.current`).
    @MainActor
    public func loadOfferings(offeringIdentifier: String? = nil) async {
        guard Purchases.isConfigured else {
            availablePackages = []
            return
        }
        isLoadingOfferings = true
        offeringsError = nil
        defer { isLoadingOfferings = false }
        
        do {
            let offerings = try await Purchases.shared.offerings()
            let targetOffering: Offering?
            if let id = offeringIdentifier, !id.isEmpty {
                targetOffering = offerings.offering(identifier: id) ?? offerings.current
            } else {
                targetOffering = offerings.current
            }
            let packages = targetOffering?.availablePackages ?? []
            let sorted = packages.sorted {
                Self.packageSortOrder($0) < Self.packageSortOrder($1)
            }
            availablePackages = sorted
            if sorted.isEmpty {
                offeringsError = NSLocalizedString("No subscription plans are available right now. Please try again later.", comment: "")
            } else {
                await checkIntroEligibility(for: sorted)
            }
        } catch {
            offeringsError = error.localizedDescription
            availablePackages = []
        }
    }
    
    // MARK: - Introductory Offers (New Subscribers) & Promotional Offers (Existing/Lapsed Subscribers)
    
    /// Checks trial or introductory discount eligibility for the given packages and updates `introEligibility`.
    @MainActor
    @discardableResult
    public func checkIntroEligibility(for packages: [Package]? = nil) async -> [String: IntroEligibilityStatus] {
        guard Purchases.isConfigured else { return [:] }
        let targetPackages = packages ?? availablePackages
        let productIDs = targetPackages.map(\.storeProduct.productIdentifier)
        guard !productIDs.isEmpty else { return [:] }
        
        let eligibilityMap = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: productIDs)
        var statusMap = self.introEligibility
        for (productID, eligibility) in eligibilityMap {
            statusMap[productID] = eligibility.status
        }
        self.introEligibility = statusMap
        return statusMap
    }
    
    /// Returns `true` if the user is a new subscriber eligible for the package's introductory offer or free trial.
    /// (Kiểm tra xem người dùng có đủ điều kiện nhận ưu đãi người mới / dùng thử miễn phí cho gói này không.)
    public func isEligibleForIntroOffer(package: Package) -> Bool {
        guard package.storeProduct.introductoryDiscount != nil else { return false }
        let productID = package.storeProduct.productIdentifier
        return introEligibility[productID] == .eligible
    }
    
    /// Returns `true` if the user is eligible for the introductory offer of a specific StoreKit Product ID.
    public func isEligibleForIntroOffer(productID: String) -> Bool {
        introEligibility[productID] == .eligible
    }
    
    /// Returns the `StoreProductDiscount` for the package's introductory offer **only** if the user is eligible.
    /// Returns `nil` if no intro offer exists or if the user has already used their trial/intro offer.
    public func introOffer(for package: Package) -> StoreProductDiscount? {
        guard isEligibleForIntroOffer(package: package) else { return nil }
        return package.storeProduct.introductoryDiscount
    }
    
    /// Returns a human-readable summary of the introductory offer if the user is eligible
    /// (e.g. `"3-Day Free Trial"` or `"$0.99 for 1 Month"`), or `nil` if not eligible.
    public func introOfferSummary(for package: Package) -> String? {
        guard let discount = introOffer(for: package) else { return nil }
        let periodText = Self.formatSubscriptionPeriod(discount.subscriptionPeriod, numberOfPeriods: discount.numberOfPeriods)
        switch discount.paymentMode {
        case .freeTrial:
            return String(format: NSLocalizedString("%@ Free Trial", comment: ""), periodText)
        case .payAsYouGo, .payUpFront:
            return String(format: NSLocalizedString("%@ for %@", comment: ""), discount.localizedPriceString, periodText)
        @unknown default:
            return nil
        }
    }
    
    /// Formats a RevenueCat `SubscriptionPeriod` into a localized string (e.g. `"3 Days"`, `"1 Week"`, `"1 Month"`).
    public static func formatSubscriptionPeriod(_ period: RevenueCat.SubscriptionPeriod, numberOfPeriods: Int = 1) -> String {
        let totalUnits = max(1, period.value * max(1, numberOfPeriods))
        switch period.unit {
        case .day:
            return totalUnits == 1
                ? NSLocalizedString("1 Day", comment: "")
                : String(format: NSLocalizedString("%d Days", comment: ""), totalUnits)
        case .week:
            return totalUnits == 1
                ? NSLocalizedString("1 Week", comment: "")
                : String(format: NSLocalizedString("%d Weeks", comment: ""), totalUnits)
        case .month:
            return totalUnits == 1
                ? NSLocalizedString("1 Month", comment: "")
                : String(format: NSLocalizedString("%d Months", comment: ""), totalUnits)
        case .year:
            return totalUnits == 1
                ? NSLocalizedString("1 Year", comment: "")
                : String(format: NSLocalizedString("%d Years", comment: ""), totalUnits)
        @unknown default:
            return "\(totalUnits)"
        }
    }
    
    /// Returns all promotional discounts configured in App Store Connect for the given package.
    public func promotionalDiscounts(for package: Package) -> [StoreProductDiscount] {
        package.storeProduct.discounts
    }
    
    /// Fetches all signed `PromotionalOffer` objects that the current user is eligible to redeem for the given package.
    /// Requires an In-App Purchase Key (`.p8`) uploaded to the RevenueCat Dashboard.
    @MainActor
    public func eligiblePromotionalOffers(for package: Package) async -> [PromotionalOffer] {
        guard Purchases.isConfigured else { return [] }
        return await Purchases.shared.eligiblePromotionalOffers(forProduct: package.storeProduct)
    }
    
    /// Purchases a package with a signed `PromotionalOffer` using Swift Concurrency (`async/await`).
    @MainActor
    @discardableResult
    public func purchaseAsync(package: Package, promotionalOffer: PromotionalOffer) async throws -> CustomerInfo {
        isPurchasing = true
        defer { isPurchasing = false }
        
        let result = try await Purchases.shared.purchase(package: package, promotionalOffer: promotionalOffer)
        forceUpdateState(from: result.customerInfo)
        if result.userCancelled {
            throw PurchaseFlowError.userCancelled
        }
        if TNInAppCurrencyManager.isInitialized {
            TNInAppCurrencyManager.shared.handlePurchaseOrRestoreSuccess()
        }
        return result.customerInfo
    }
    
    /// Automatically signs a `StoreProductDiscount` via RevenueCat and purchases the package with that promotional offer.
    @MainActor
    @discardableResult
    public func purchasePromotionalOfferAsync(package: Package, discount: StoreProductDiscount) async throws -> CustomerInfo {
        isPurchasing = true
        defer { isPurchasing = false }
        
        let signedOffer = try await Purchases.shared.promotionalOffer(
            forProductDiscount: discount,
            product: package.storeProduct
        )
        let result = try await Purchases.shared.purchase(package: package, promotionalOffer: signedOffer)
        forceUpdateState(from: result.customerInfo)
        if result.userCancelled {
            throw PurchaseFlowError.userCancelled
        }
        if TNInAppCurrencyManager.isInitialized {
            TNInAppCurrencyManager.shared.handlePurchaseOrRestoreSuccess()
        }
        return result.customerInfo
    }
    
    /// Purchases a package with a `StoreProductDiscount` (Promotional Offer), calling back on `@MainActor`.
    public func purchasePromotionalOffer(
        package: Package,
        discount: StoreProductDiscount,
        completion: @escaping (Result<CustomerInfo, Error>) -> Void
    ) {
        Task { @MainActor in
            do {
                let info = try await purchasePromotionalOfferAsync(package: package, discount: discount)
                completion(.success(info))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    /// Purchases a package using Swift Concurrency (`async/await`).
    @MainActor
    @discardableResult
    public func purchaseAsync(package: Package) async throws -> CustomerInfo {
        isPurchasing = true
        defer { isPurchasing = false }
        
        let result = try await Purchases.shared.purchase(package: package)
        forceUpdateState(from: result.customerInfo)
        if result.userCancelled {
            throw PurchaseFlowError.userCancelled
        }
        if TNInAppCurrencyManager.isInitialized {
            TNInAppCurrencyManager.shared.handlePurchaseOrRestoreSuccess()
        }
        return result.customerInfo
    }
    
    /// Purchases a package with a completion callback (guaranteed to execute on `@MainActor`).
    public func purchase(package: Package, completion: @escaping (Result<CustomerInfo, Error>) -> Void) {
        Task { @MainActor in
            do {
                let customerInfo = try await purchaseAsync(package: package)
                completion(.success(customerInfo))
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
    
    /// Presents the native iOS App Store Offer Code Redemption Sheet.
    /// Once the user redeems a code, StoreKit 2 (`Transaction.updates`) and RevenueCat (`PurchasesDelegate`)
    /// automatically unlock the corresponding entitlement.
    ///
    /// ```swift
    /// TNSubscriptionIOS.shared.presentOfferCodeRedemption()
    /// ```
    @MainActor
    public func presentOfferCodeRedemption() {
        if Purchases.isConfigured {
            Purchases.shared.presentCodeRedemptionSheet()
        } else {
            SKPaymentQueue.default().presentCodeRedemptionSheet()
        }
    }
    
    /// Restores purchases via StoreKit 2 + RevenueCat (completion callback is guaranteed to execute on `@MainActor`).
    public func restorePurchases(completion: @escaping (Result<Bool, Error>) -> Void) {
        Task { @MainActor in
            do {
                let success = try await restorePurchasesAsync()
                completion(.success(success))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    /// Restores purchases via StoreKit 2 + RevenueCat using Swift Concurrency (`async/await`).
    @MainActor
    @discardableResult
    public func restorePurchasesAsync() async throws -> Bool {
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
            if config.enableBackendIdentitySync {
                Self.syncClientIdToRevenueCat()
            }
            if TNInAppCurrencyManager.isInitialized {
                TNInAppCurrencyManager.shared.handlePurchaseOrRestoreSuccess()
            }
            Task { @MainActor in
                if let info = try? await Purchases.shared.restorePurchases() {
                    let rcActive = self.resolveActiveEntitlements(from: info)
                    self.cacheActiveEntitlementProducts(from: info)
                    let combined = storeKitActive.union(rcActive)
                    self.updateState(isPremium: !combined.isEmpty, state: !combined.isEmpty ? .unlocked : .locked, activeEntitlements: combined, info: info)
                }
            }
            return true
        }
        
        do {
            let info = try await Purchases.shared.restorePurchases()
            let active = resolveActiveEntitlements(from: info)
            let isSuccess = !active.isEmpty
            cacheActiveEntitlementProducts(from: info)
            updateState(isPremium: isSuccess, state: isSuccess ? .unlocked : .locked, activeEntitlements: active, info: info)
            if isSuccess {
                if config.enableBackendIdentitySync {
                    Self.syncClientIdToRevenueCat()
                }
                if TNInAppCurrencyManager.isInitialized {
                    TNInAppCurrencyManager.shared.handlePurchaseOrRestoreSuccess()
                }
            }
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
        
        cacheActiveEntitlementProducts(from: info)
        
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
        if TNInAppCurrencyManager.isInitialized {
            TNInAppCurrencyManager.shared.handlePurchaseOrRestoreSuccess()
        }
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
            
            self.cacheActiveEntitlementProducts(from: customerInfo)
            
            self.activeEntitlements = active
            self.entitlementState = isActive ? .unlocked : .locked
            self.isPremium = isActive
        }
    }
}

// MARK: - URLRequest Identity Headers Extension

public extension URLRequest {
    /// Attaches standard TN Studio Proxy Gateway client identity headers (`X-Client-Id`, `X-Device-Id`, and optional `X-User-Id`).
    mutating func applyTNIdentityHeaders(userId: String? = nil) {
        for (header, value) in TNSubscriptionIOS.identityHeaders(userId: userId) {
            setValue(value, forHTTPHeaderField: header)
        }
    }
    
    /// Returns a copy of the request with TN Studio Proxy Gateway client identity headers attached.
    func applyingTNIdentityHeaders(userId: String? = nil) -> URLRequest {
        var copy = self
        copy.applyTNIdentityHeaders(userId: userId)
        return copy
    }
}
