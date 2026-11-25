import Foundation
import StoreKit
@_exported import SwiftUI
import Combine
import UIKit
import Qonversion

// MARK: - Shared Configuration

// The configuration types live in TNSubscriptionShared, and the code this engine shares with the
// Core and Adapty engines (consumables, identity, logging, the paywall) in TNSubscriptionKit, which
// re-exports TNSubscriptionShared.
// (Các kiểu cấu hình nằm trong TNSubscriptionShared; phần code dùng chung với engine Core và Adapty
// — consumable, identity, log, paywall — nằm trong TNSubscriptionKit, module này re-export luôn
// TNSubscriptionShared.)
@_exported import TNSubscriptionKit

/// The engine-neutral name for this engine's entry point. Code that uses only the shared
/// configuration and the common API compiles against any engine unchanged; the exact list is in
/// README, "What is the same, what differs", and is enforced by `TNEngineContractTests`.
/// (Tên trung lập cho điểm vào của engine này. Code chỉ dùng cấu hình chung và phần API chung thì
/// compile được với mọi engine mà không phải sửa; danh sách chính xác nằm trong README, mục "What is
/// the same, what differs", và được `TNEngineContractTests` bảo đảm.)
public typealias TNSubscription = TNSubscriptionQonversion

// MARK: - Deferred Purchases Listener

/// Receives purchases that complete later — Ask to Buy approvals, Strong Customer Authentication —
/// and has the engine re-read entitlements.
/// (Nhận các giao dịch hoàn tất muộn — Ask to Buy được duyệt, xác thực SCA — và yêu cầu engine đọc lại
/// quyền lợi.)
///
/// Qonversion keeps only a **weak** reference to its listener, so the engine holds this object
/// strongly; otherwise it would be released at once and deferred purchases would go unnoticed.
/// (Qonversion chỉ giữ tham chiếu **weak** tới listener, nên engine giữ object này dạng strong; nếu
/// không nó sẽ bị giải phóng ngay và các giao dịch hoàn tất muộn sẽ không được ghi nhận.)
final class TNQonversionDeferredListener: NSObject, Qonversion.DeferredPurchasesListener {
    func deferredPurchaseCompleted(_ purchaseResult: Qonversion.PurchaseResult) {
        Task { @MainActor in
            TNLog.info("A deferred purchase completed (Ask to Buy / SCA); re-reading entitlements.")
            await TNSubscriptionQonversion.shared?.resolveEntitlement()
        }
    }
}

// MARK: - TNSubscriptionQonversion

/// The main entry point for TNSubscriptionQonversion: subscriptions backed by **Qonversion**.
/// (Điểm vào chính của TNSubscriptionQonversion: subscription chạy trên **Qonversion**.)
///
/// ```swift
/// TNSubscription.configure(config: TNSubscriptionConfig(
///     apiKey: "your-qonversion-project-key",
///     entitlements: [TNEntitlement(id: "premium", productIDs: ["com.app.weekly", "com.app.yearly"])]
/// ))
/// ```
///
/// ### How it differs from Adapty and RevenueCat (Khác Adapty và RevenueCat thế nào)
/// Qonversion has deprecated its own offerings in favour of Remote Config, so offerings here are
/// declared in code with `TNOffering` — exactly as in `TNSubscriptionCore` — and can be swapped at
/// runtime with `updateOfferings(_:current:)`. Qonversion still decides who is entitled.
/// (Qonversion đã deprecated offering của họ để chuyển sang Remote Config, nên ở đây offering được
/// khai báo trong code bằng `TNOffering` — y như `TNSubscriptionCore` — và đổi được lúc runtime bằng
/// `updateOfferings(_:current:)`. Qonversion vẫn là bên quyết định ai có quyền lợi.)
@MainActor
public final class TNSubscriptionQonversion: ObservableObject {

    // MARK: - Singleton

    /// The shared instance, available after `configure(config:)`.
    /// (Instance dùng chung, có sau khi gọi `configure(config:)`.)
    public private(set) static var shared: TNSubscriptionQonversion!

    /// `true` once `configure(config:)` has run. (`true` sau khi `configure(config:)` đã chạy.)
    public static var isConfigured: Bool { shared != nil }

    // MARK: - Published State

    /// The three states a paywall must distinguish. Never show a paywall during `.unknown`.
    /// (Ba trạng thái paywall cần phân biệt. Đừng hiện paywall khi đang `.unknown`.)
    public typealias EntitlementState = TNEntitlementState

    @Published public private(set) var entitlementState: EntitlementState = .unknown
    @Published public private(set) var customerInfo: TNCustomerInfo?
    @Published public private(set) var isPremium: Bool = false
    @Published public private(set) var activeEntitlements: Set<String> = []
    @Published public private(set) var availablePackages: [TNPackage] = []
    @Published public private(set) var introEligibility: [String: TNIntroEligibilityStatus] = [:]
    @Published public private(set) var isLoadingOfferings = false
    @Published public private(set) var isPurchasing = false
    @Published public private(set) var offeringsError: String?
    @Published public private(set) var entitlementError: String?
    @Published public private(set) var currentOfferingIdentifier: String?

    /// `true` once the Qonversion SDK has been started. Purchases need it; local entitlement checks
    /// do not. (`true` sau khi SDK Qonversion đã được khởi chạy. Mua cần nó; kiểm tra quyền lợi cục bộ
    /// thì không.)
    @Published public private(set) var isQonversionLaunched = false

    // MARK: - Internal State

    private let config: TNSubscriptionConfig
    private let keyProblem: TNKeyProblem?
    private var offerings: [TNOffering]
    private var storeProducts: [String: Product] = [:]
    /// Qonversion products by **App Store** ID — what packages and entitlements are matched on.
    private var qonversionProductsByStoreID: [String: Qonversion.Product] = [:]
    /// App Store ID by **Qonversion** product ID — entitlements report Qonversion's ID.
    private var storeIDByQonversionID: [String: String] = [:]
    private let deferredListener = TNQonversionDeferredListener()
    private var updatesTask: Task<Void, Never>?

    private static let entitlementCacheKey = "tn_qonversion_cachedEntitlements"

    // MARK: - Nonisolated Snapshot

    /// A thread-safe snapshot of `isPremium`, readable from any context without `await`.
    /// (Snapshot an toàn luồng của `isPremium`, đọc được từ mọi ngữ cảnh không cần `await`.)
    public nonisolated static var cachedIsPremium: Bool { TNEntitlementSnapshot.shared.isPremium }

    /// A thread-safe snapshot of `activeEntitlements`. (Snapshot an toàn luồng của `activeEntitlements`.)
    public nonisolated static var cachedActiveEntitlements: Set<String> {
        TNEntitlementSnapshot.shared.activeEntitlements
    }

    // MARK: - Configure

    /// Configures the engine and starts Qonversion. Call once, at launch.
    /// (Cấu hình engine và khởi chạy Qonversion. Gọi một lần, khi khởi động.)
    public static func configure(config: TNSubscriptionConfig) {
        TNLog.level = config.logLevel
        TNLog.setCategory("TNSubscriptionQonversion")

        guard shared == nil else {
            TNLog.warn("configure(config:) was called more than once; the later call was ignored.")
            return
        }

        // The shared check decides both what is wrong and whether it blocks launch, so every
        // engine follows the same policy. Only a blocking problem is kept: it is what stops the SDK.
        let detected = config.isIAPEnabled ? TNVendorKey.check(config.apiKey, for: .qonversion) : nil
        var keyProblem: TNKeyProblem?
        if let detected {
            if detected.blocksLaunch(for: .qonversion) {
                keyProblem = detected
                TNLog.error("\(detected.explanation(for: .qonversion)) Qonversion will NOT be started; entitlements fall back to local StoreKit and purchases are disabled.")
            } else {
                TNLog.warn(detected.explanation(for: .qonversion))
            }
        }
        validate(config)
        for warning in config.ignoredSettings(for: .qonversion) {
            TNLog.warn(warning)
        }

        shared = TNSubscriptionQonversion(config: config, keyProblem: keyProblem)
        TNLog.info("""
        TNSubscriptionQonversion configured. entitlements=\(config.allEntitlementIDs), \
        offerings=\(config.resolvedOfferings.map(\.identifier)), IAP=\(config.isIAPEnabled ? "on" : "off").
        """)
    }

    /// Diagnostic verbosity. (Mức độ log.)
    public static var logLevel: TNLogLevel {
        get { TNLog.level }
        set { TNLog.level = newValue }
    }

    /// Routes this package's logs into your own logging stack. (Chuyển log vào hệ thống log của bạn.)
    public static var logHandler: ((TNLogLevel, String) -> Void)? {
        get { TNLog.handler }
        set { TNLog.handler = newValue }
    }

    private static func validate(_ config: TNSubscriptionConfig) {
        guard config.isIAPEnabled else {
            TNLog.warn("isIAPEnabled is false — every entitlement is unlocked and Qonversion is not started.")
            return
        }
        if config.entitlements.isEmpty {
            TNLog.error("No entitlements configured. Pass at least one TNEntitlement whose id is a Qonversion entitlement ID.")
        }
        if config.allLoadableProductIDs.isEmpty {
            TNLog.error("No product IDs anywhere in the config, so the paywall has nothing to sell. Add productIDs to your TNEntitlement or declare a TNOffering.")
        }
    }

    // MARK: - Init

    private init(config: TNSubscriptionConfig, keyProblem: TNKeyProblem?) {
        self.config = config
        self.keyProblem = keyProblem
        self.offerings = config.resolvedOfferings
        self.currentOfferingIdentifier = config.currentOfferingIdentifier ?? config.resolvedOfferings.first?.identifier

        guard config.isIAPEnabled else {
            let all = Set(config.allEntitlementIDs)
            entitlementState = .unlocked
            isPremium = true
            activeEntitlements = all
            TNEntitlementSnapshot.shared.update(isPremium: true, active: all)
            return
        }

        // 1. Unlock a known-paying user before any network round trip.
        applyWarmStartCache()

        // 2. Start Qonversion. Unlike Adapty this is synchronous, so there is no activation race.
        if keyProblem == nil {
            let launchMode: Qonversion.LaunchMode = config.observerMode ? .analytics : .subscriptionManagement
            let qonversionConfig = Qonversion.Configuration(
                projectKey: config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                launchMode: launchMode
            )
            qonversionConfig.setDeferredPurchasesListener(deferredListener)
            Qonversion.initWithConfig(qonversionConfig)
            isQonversionLaunched = true
            if let userId = config.customerUserId, !userId.isEmpty {
                Qonversion.shared().identify(userId)
            }
            TNLog.info("Qonversion started (\(config.observerMode ? "analytics / observer" : "subscription management") mode).")
        }

        // 3. Qonversion has no general "entitlements changed" listener any more, so renewals,
        //    refunds and purchases from other devices are picked up through StoreKit.
        updatesTask = Task { [weak self] in
            for await _ in StoreKit.Transaction.updates {
                await self?.resolveEntitlement()
            }
        }

        // 4. Load products, then resolve — products first, so Qonversion's product IDs can be
        //    mapped to App Store IDs.
        Task { [weak self] in
            await self?.loadProducts()
            await self?.resolveEntitlement()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Entitlement Queries

    public func hasEntitlement(_ entitlementId: String) -> Bool {
        activeEntitlements.contains(entitlementId)
    }

    public func productIDs(for entitlementId: String) -> Set<String> {
        config.entitlements.first { $0.id == entitlementId }?.productIDs ?? []
    }

    public func entitlementInfo(for entitlementId: String) -> TNEntitlementInfo? {
        customerInfo?.entitlements[entitlementId]
    }

    public var currentPlanProductID: String? {
        for entitlement in config.entitlements {
            if let info = customerInfo?.entitlements[entitlement.id], info.isActive {
                return info.productIdentifier
            }
        }
        return nil
    }

    public func currentProductID(for entitlementId: String) -> String? {
        guard let info = customerInfo?.entitlements[entitlementId], info.isActive else { return nil }
        return info.productIdentifier
    }

    public var currentPlanDisplayName: String? {
        guard let productID = currentPlanProductID else { return nil }
        if let product = storeProducts[productID] {
            return TNPackageType.inferred(from: product).localizedName ?? product.displayName
        }
        return Self.displayName(forProductID: productID)
    }

    public static func displayName(forProductID productID: String) -> String {
        TNPackageType.displayName(forProductID: productID)
    }

    // MARK: - Identity

    public nonisolated static var clientId: String { TNIdentity.clientId }
    public nonisolated static var deviceId: String { TNIdentity.deviceId }
    public nonisolated static func identityHeaders(userId: String? = nil) -> [String: String] {
        TNIdentity.identityHeaders(userId: userId)
    }

    /// Ties the Qonversion profile to your own user ID — call after login.
    /// (Gắn profile Qonversion với user ID của bạn — gọi sau khi đăng nhập.)
    public func identify(_ customerUserId: String) async throws {
        guard isQonversionLaunched else { throw TNPurchaseError.notLaunched }
        _ = try await Qonversion.shared().identify(customerUserId)
        TNLog.info("Identified the Qonversion profile with a customer user ID.")
        await resolveEntitlement()
    }

    /// Returns to an anonymous profile — call on logout.
    /// (Quay về profile ẩn danh — gọi khi đăng xuất.)
    public func logout() async {
        guard isQonversionLaunched else { return }
        Qonversion.shared().logout()
        TNLog.info("Logged out of the Qonversion profile.")
        await resolveEntitlement()
    }

    // MARK: - Products

    /// Loads Qonversion's products and the matching StoreKit 2 products.
    /// (Tải sản phẩm của Qonversion và sản phẩm StoreKit 2 tương ứng.)
    ///
    /// Qonversion only exposes StoreKit 1's `SKProduct`, so the StoreKit 2 `Product` is fetched
    /// separately by App Store ID: it drives display, price-per-month and intro-offer eligibility,
    /// exactly as in the other engines. Qonversion's product is what the purchase goes through.
    /// (Qonversion chỉ cung cấp `SKProduct` của StoreKit 1, nên `Product` của StoreKit 2 được tải riêng
    /// theo ID App Store: nó điều khiển phần hiển thị, giá theo tháng và điều kiện ưu đãi người mới, y như
    /// các engine khác. Còn giao dịch mua thì đi qua sản phẩm của Qonversion.)
    @discardableResult
    public func loadProducts() async -> [String: Product] {
        if isQonversionLaunched {
            do {
                let products = try await Qonversion.shared().products()
                var byStoreID: [String: Qonversion.Product] = [:]
                var storeIDs: [String: String] = [:]
                for (qonversionID, product) in products where !product.storeID.isEmpty {
                    byStoreID[product.storeID] = product
                    storeIDs[qonversionID] = product.storeID
                }
                qonversionProductsByStoreID = byStoreID
                storeIDByQonversionID = storeIDs
                TNLog.info("Loaded \(products.count) Qonversion product(s).")
            } catch {
                TNLog.error("Loading Qonversion products FAILED: \(error.localizedDescription)")
            }
        }

        let ids = config.allLoadableProductIDs
            .union(offerings.flatMap(\.productIDs))
            .union(qonversionProductsByStoreID.keys)
        guard !ids.isEmpty else { return storeProducts }
        do {
            let products = try await Product.products(for: ids)
            for product in products { storeProducts[product.id] = product }
            let missing = ids.subtracting(storeProducts.keys)
            if !missing.isEmpty {
                TNLog.warn("The App Store returned no product for \(missing.sorted()); check the IDs match App Store Connect exactly.")
            }
        } catch {
            TNLog.error("Fetching App Store products FAILED: \(error.localizedDescription)")
        }
        return storeProducts
    }

    // MARK: - Offerings

    /// Fire-and-forget variant of `loadOfferings(offeringIdentifier:)`.
    public func fetchOfferings(offeringIdentifier: String? = nil) {
        Task { await loadOfferings(offeringIdentifier: offeringIdentifier) }
    }

    /// Builds `availablePackages` from a `TNOffering`. (Dựng `availablePackages` từ một `TNOffering`.)
    ///
    /// A product appears only when both Qonversion and the App Store know it: Qonversion to buy it,
    /// the App Store to price it.
    /// (Một sản phẩm chỉ xuất hiện khi cả Qonversion lẫn App Store đều biết nó: Qonversion để mua, App
    /// Store để có giá.)
    public func loadOfferings(offeringIdentifier: String? = nil) async {
        guard config.isIAPEnabled else {
            availablePackages = []
            offeringsError = NSLocalizedString("In-app purchases are not enabled.", comment: "")
            return
        }
        guard isQonversionLaunched else {
            availablePackages = []
            offeringsError = NSLocalizedString("Plans could not be loaded.", comment: "")
            TNLog.error("loadOfferings skipped: Qonversion is not started (\(keyProblem?.explanation(for: .qonversion) ?? "unknown reason")).")
            return
        }

        isLoadingOfferings = true
        offeringsError = nil
        defer { isLoadingOfferings = false }

        if qonversionProductsByStoreID.isEmpty || storeProducts.isEmpty {
            await loadProducts()
        }

        let requested = offeringIdentifier ?? currentOfferingIdentifier
        let offering = offerings.first { $0.identifier == requested } ?? offerings.first
        if let requested, offering?.identifier != requested {
            TNLog.warn("Offering '\(requested)' is not declared; falling back to '\(offering?.identifier ?? "none")'.")
        }
        guard let offering else {
            availablePackages = []
            offeringsError = NSLocalizedString("No subscription plans are available right now. Please try again later.", comment: "")
            TNLog.error("No offering to show. Declare a TNOffering, or give your TNEntitlement product IDs so a default offering is synthesised.")
            return
        }
        currentOfferingIdentifier = offering.identifier

        var packages: [TNPackage] = []
        var notInQonversion: [String] = []
        var notInAppStore: [String] = []
        for storeID in offering.productIDs {
            guard let qonversionProduct = qonversionProductsByStoreID[storeID] else {
                notInQonversion.append(storeID)
                continue
            }
            guard let product = storeProducts[storeID] else {
                notInAppStore.append(storeID)
                continue
            }
            packages.append(TNPackage(offeringIdentifier: offering.identifier, product: product, qonversionProduct: qonversionProduct))
        }
        if !offering.preserveOrder {
            packages.sort { $0.packageType.sortOrder < $1.packageType.sortOrder }
        }
        availablePackages = packages

        if !notInQonversion.isEmpty {
            TNLog.warn("\(notInQonversion) are not set up as products in the Qonversion dashboard, so they cannot be bought; they were left off the paywall.")
        }
        if !notInAppStore.isEmpty {
            TNLog.warn("The App Store returned no product for \(notInAppStore); they were left off the paywall.")
        }
        if packages.isEmpty {
            offeringsError = NSLocalizedString("No subscription plans are available right now. Please try again later.", comment: "")
        } else {
            await checkIntroEligibility(for: packages)
            TNLog.info("Loaded offering '\(offering.identifier)' with \(packages.count) package(s).")
        }
    }

    /// Replaces the offerings at runtime — for example from Qonversion Remote Config.
    /// (Thay offering lúc runtime — ví dụ lấy từ Remote Config của Qonversion.)
    public func updateOfferings(_ newOfferings: [TNOffering], current: String? = nil) async {
        offerings = newOfferings
        if let current { currentOfferingIdentifier = current }
        await loadProducts()
        await loadOfferings(offeringIdentifier: currentOfferingIdentifier)
    }

    /// Metadata of the offering currently shown. (Metadata của offering đang hiển thị.)
    public var currentOfferingMetadata: [String: String] {
        offerings.first { $0.identifier == currentOfferingIdentifier }?.metadata ?? [:]
    }

    // MARK: - Introductory Offers

    /// Asks StoreKit which products still offer an intro offer to this Apple ID.
    /// (Hỏi StoreKit sản phẩm nào còn ưu đãi người mới cho Apple ID này.)
    @discardableResult
    public func checkIntroEligibility(for packages: [TNPackage]? = nil) async -> [String: TNIntroEligibilityStatus] {
        let targets = packages ?? availablePackages
        var updated = introEligibility
        for package in targets {
            guard let subscription = package.product.subscription, subscription.introductoryOffer != nil else {
                updated[package.productIdentifier] = .noIntroOfferExists
                continue
            }
            updated[package.productIdentifier] = await subscription.isEligibleForIntroOffer ? .eligible : .ineligible
        }
        introEligibility = updated
        return updated
    }

    public func isEligibleForIntroOffer(package: TNPackage) -> Bool {
        introEligibility[package.productIdentifier] == .eligible
    }

    public func isEligibleForIntroOffer(productID: String) -> Bool {
        introEligibility[productID] == .eligible
    }

    public func introOffer(for package: TNPackage) -> TNSubscriptionOffer? {
        guard isEligibleForIntroOffer(package: package),
              let offer = package.product.subscription?.introductoryOffer else { return nil }
        return TNSubscriptionOffer(storeKitOffer: offer, product: package.product)
    }

    public func introOfferSummary(for package: TNPackage) -> String? {
        introOffer(for: package)?.localizedSummary
    }

    // MARK: - Entitlement Resolution

    /// Re-reads the user's entitlements: Qonversion first, local StoreKit if it cannot be reached,
    /// otherwise the last known state. A network error never locks an unlocked user.
    /// (Đọc lại quyền lợi: Qonversion trước, StoreKit cục bộ nếu không kết nối được, nếu không thì giữ
    /// trạng thái gần nhất. Lỗi mạng không bao giờ khoá một người đang được mở khoá.)
    public func resolveEntitlement() async {
        guard config.isIAPEnabled else {
            apply(info: nil, state: .unlocked, active: Set(config.allEntitlementIDs))
            return
        }

        if isQonversionLaunched {
            do {
                let entitlements = try await Qonversion.shared().checkEntitlements()
                entitlementError = nil
                apply(qonversionEntitlements: entitlements, reason: "checkEntitlements")
                return
            } catch {
                entitlementError = error.localizedDescription
                TNLog.warn("Qonversion checkEntitlements FAILED (\(error.localizedDescription)).")
            }
        }

        guard config.offlineStoreKitFallback else {
            if entitlementState == .unknown { apply(info: nil, state: .locked, active: []) }
            return
        }
        apply(info: await buildFromStoreKit())
    }

    /// Fire-and-forget variant of `resolveEntitlement()`.
    public func checkSubscriptionStatus() {
        Task { await resolveEntitlement() }
    }

    private func apply(qonversionEntitlements: [String: Qonversion.Entitlement], reason: String) {
        let configured = Set(config.allEntitlementIDs)
        var infos: [String: TNEntitlementInfo] = [:]
        for (id, entitlement) in qonversionEntitlements where configured.contains(id) {
            // Qonversion reports its own product ID; the paywall compares App Store IDs.
            let storeID = storeIDByQonversionID[entitlement.productID] ?? entitlement.productID
            infos[id] = TNEntitlementInfo(entitlement: entitlement, storeProductID: storeID)
        }

        let unconfigured = Set(qonversionEntitlements.filter(\.value.isActive).keys).subtracting(configured)
        if !unconfigured.isEmpty {
            TNLog.warn("Qonversion reports active entitlement(s) \(unconfigured.sorted()) that are not in your config, so they unlock nothing here. Configured: \(configured.sorted()).")
        }

        let active = infos.values.filter(\.isActive)
        let info = TNCustomerInfo(
            entitlements: TNEntitlementInfos(all: infos),
            activeSubscriptions: Set(active.filter { $0.expirationDate != nil }.map(\.productIdentifier)),
            allPurchasedProductIdentifiers: Set(active.map(\.productIdentifier)),
            latestExpirationDate: active.compactMap(\.expirationDate).max(),
            originalPurchaseDate: infos.values.compactMap(\.originalPurchaseDate).min(),
            source: .qonversion
        )
        TNLog.debug("Applied Qonversion entitlements (\(reason)): active=\(info.entitlements.activeIdentifiers.sorted()).")
        apply(info: info)
    }

    private func apply(info: TNCustomerInfo) {
        let active = info.entitlements.activeIdentifiers
        persistEntitlementCache(from: info)
        apply(info: info, state: active.isEmpty ? .locked : .unlocked, active: active)
    }

    private func apply(info: TNCustomerInfo?, state: EntitlementState, active: Set<String>) {
        if let info { customerInfo = info }
        entitlementState = state
        isPremium = !active.isEmpty
        activeEntitlements = active
        TNEntitlementSnapshot.shared.update(isPremium: !active.isEmpty, active: active)
    }

    private func buildFromStoreKit() async -> TNCustomerInfo {
        var infos: [String: TNEntitlementInfo] = [:]
        var owned: Set<String> = []
        var subscriptions: Set<String> = []
        let now = Date()
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry <= now { continue }
            owned.insert(transaction.productID)
            if transaction.productType == .autoRenewable { subscriptions.insert(transaction.productID) }
            for entitlement in config.entitlements where entitlement.productIDs.contains(transaction.productID) {
                let candidate = TNEntitlementInfo(entitlementId: entitlement.id, transaction: transaction)
                if let existing = infos[entitlement.id],
                   (existing.expirationDate ?? .distantFuture) >= (candidate.expirationDate ?? .distantFuture) {
                    continue
                }
                infos[entitlement.id] = candidate
            }
        }
        TNLog.info("Resolved from local StoreKit (offline fallback): \(infos.keys.sorted()).")
        return TNCustomerInfo(
            entitlements: TNEntitlementInfos(all: infos),
            activeSubscriptions: subscriptions,
            allPurchasedProductIdentifiers: owned,
            latestExpirationDate: infos.values.compactMap(\.expirationDate).max(),
            originalPurchaseDate: infos.values.compactMap(\.originalPurchaseDate).min(),
            source: .storeKitFallback
        )
    }

    // MARK: - Warm Start Cache

    private func applyWarmStartCache() {
        let stillValid = TNEntitlementCache.unexpired(key: Self.entitlementCacheKey)
        guard !stillValid.isEmpty else { return }
        activeEntitlements = stillValid
        isPremium = true
        entitlementState = .unlocked
        TNEntitlementSnapshot.shared.update(isPremium: true, active: stillValid)
    }

    private func persistEntitlementCache(from info: TNCustomerInfo) {
        TNEntitlementCache.store(info.entitlements.active.mapValues(\.expirationDate), key: Self.entitlementCacheKey)
    }

    // MARK: - Purchase

    /// Buys a package through Qonversion. (Mua một gói qua Qonversion.)
    @discardableResult
    public func purchaseAsync(package: TNPackage) async throws -> TNCustomerInfo {
        guard isQonversionLaunched else {
            TNLog.error("Purchase refused: Qonversion is not started (\(keyProblem?.explanation(for: .qonversion) ?? "unknown reason")).")
            throw TNPurchaseError.notLaunched
        }

        isPurchasing = true
        defer { isPurchasing = false }

        let productID = package.productIdentifier
        TNLog.info("Purchasing \(productID)…")

        let result = await Qonversion.shared().purchase(package.qonversionProduct)

        if result.isCanceledByUser {
            TNLog.info("Purchase of \(productID) cancelled by the user.")
            throw TNPurchaseError.userCancelled
        }
        if result.isPending {
            TNLog.info("Purchase of \(productID) is PENDING external approval (Ask to Buy / SCA).")
            throw TNPurchaseError.purchasePending
        }
        if result.isError || !result.isSuccessful {
            let message = result.error?.localizedDescription ?? "unknown error"
            TNLog.error("Purchase of \(productID) FAILED: \(message)")
            // The transaction may exist even though validation failed — re-read rather than leave
            // the user locked until the next launch.
            await resolveEntitlement()
            throw TNPurchaseError.qonversion(result.error)
        }

        if let entitlements = result.entitlements {
            apply(qonversionEntitlements: entitlements, reason: "purchase")
        } else {
            await resolveEntitlement()
        }
        if result.isFallbackGenerated {
            TNLog.warn("Qonversion could not reach its server and generated these entitlements locally; they will be re-checked on the next resolve.")
        }
        TNLog.info("Purchase of \(productID) succeeded. active=\(activeEntitlements.sorted())")
        return customerInfo ?? TNCustomerInfo()
    }

    /// Completion-handler variant, called on the main actor. (Bản dùng completion handler.)
    public func purchase(package: TNPackage, completion: @escaping (Result<TNCustomerInfo, Error>) -> Void) {
        Task { @MainActor in
            do { completion(.success(try await purchaseAsync(package: package))) }
            catch { completion(.failure(error)) }
        }
    }

    // MARK: - Restore

    /// Restores purchases and returns whether anything is now active.
    /// (Phục hồi giao dịch và trả về việc hiện có quyền lợi nào hoạt động hay không.)
    @discardableResult
    public func restorePurchasesAsync() async throws -> Bool {
        TNLog.info("Restoring purchases…")
        guard isQonversionLaunched else {
            await resolveEntitlement()
            return isPremium
        }
        do {
            let entitlements = try await Qonversion.shared().restore()
            apply(qonversionEntitlements: entitlements, reason: "restore")
        } catch {
            TNLog.error("Restore FAILED: \(error.localizedDescription)")
            throw TNPurchaseError.qonversion(error)
        }
        return isPremium
    }

    /// Completion-handler variant, called on the main actor. (Bản dùng completion handler.)
    public func restorePurchases(completion: @escaping (Result<Bool, Error>) -> Void) {
        Task { @MainActor in
            do { completion(.success(try await restorePurchasesAsync())) }
            catch { completion(.failure(error)) }
        }
    }

    // MARK: - Apple Sheets

    /// Presents Apple's Offer Code redemption sheet. (Hiển thị bảng nhập Offer Code của Apple.)
    public func presentOfferCodeRedemption() {
        if isQonversionLaunched {
            Qonversion.shared().presentCodeRedemptionSheet()
        } else {
            TNAppStoreSheets.presentOfferCodeRedemption()
        }
    }

    /// Presents Apple's Manage Subscriptions sheet. (Hiển thị bảng Quản lý đăng ký của Apple.)
    public func showManageSubscriptions() {
        TNAppStoreSheets.showManageSubscriptions()
    }

    /// Presents Apple's refund sheet for an owned App Store product.
    /// (Hiển thị bảng yêu cầu hoàn tiền của Apple cho một sản phẩm App Store đang sở hữu.)
    @discardableResult
    public func requestRefund(for productID: String) async -> Bool {
        await TNAppStoreSheets.requestRefund(for: productID)
    }

    // MARK: - Paywall Helpers

    public var recommendedPackage: TNPackage? {
        TNPriceMath.recommended(availablePackages, pricePerMonth: \.pricePerMonth)
    }

    public func isRecommended(_ package: TNPackage) -> Bool {
        recommendedPackage?.identifier == package.identifier
    }

    // MARK: - Testing

    /// **Test-only.** Drops the singleton so another `configure` can run.
    /// (**Chỉ dùng cho test.** Bỏ singleton để có thể gọi `configure` lần nữa.)
    internal static func resetForTesting(preserveCache: Bool = false) {
        shared?.updatesTask?.cancel()
        shared = nil
        if !preserveCache {
            TNEntitlementCache.clear(key: entitlementCacheKey)
        }
        TNEntitlementSnapshot.shared.update(isPremium: false, active: [])
    }
}

// MARK: - TNPurchaseError

/// What can go wrong in a purchase flow. (Những lỗi có thể xảy ra khi mua.)
public enum TNPurchaseError: LocalizedError {
    case userCancelled
    case purchasePending
    /// Qonversion was not started — bad or missing project key. (Qonversion chưa được khởi chạy — key sai hoặc thiếu.)
    case notLaunched
    /// Qonversion reported an error. (Qonversion báo lỗi.)
    case qonversion(Error?)

    public var errorDescription: String? {
        switch self {
        case .userCancelled:
            return NSLocalizedString("Purchase was cancelled.", comment: "")
        case .purchasePending:
            return NSLocalizedString("Your purchase is waiting for approval. You'll get access as soon as it's approved.", comment: "")
        case .notLaunched:
            return NSLocalizedString("Purchases are not available right now. Please try again later.", comment: "")
        case .qonversion(let error):
            return error?.localizedDescription
                ?? NSLocalizedString("Something went wrong with your purchase. Please try again.", comment: "")
        }
    }
}
