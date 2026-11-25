import Foundation
import StoreKit
@_exported import SwiftUI
import Combine
import UIKit
import Adapty

// MARK: - Shared Configuration

// The configuration types live in TNSubscriptionShared, and the code this engine shares with the
// Core and Qonversion engines (consumables, identity, logging, the paywall) in TNSubscriptionKit,
// which re-exports TNSubscriptionShared.
// (Các kiểu cấu hình nằm trong TNSubscriptionShared; phần code dùng chung với engine Core và
// Qonversion — consumable, identity, log, paywall — nằm trong TNSubscriptionKit, module này re-export
// luôn TNSubscriptionShared.)
@_exported import TNSubscriptionKit

/// The engine-neutral name for this engine's entry point. Code that uses only the shared
/// configuration and the common API compiles against any engine unchanged; the exact list is in
/// README, "What is the same, what differs", and is enforced by `TNEngineContractTests`.
/// (Tên trung lập cho điểm vào của engine này. Code chỉ dùng cấu hình chung và phần API chung thì
/// compile được với mọi engine mà không phải sửa; danh sách chính xác nằm trong README, mục "What is
/// the same, what differs", và được `TNEngineContractTests` bảo đảm.)
public typealias TNSubscription = TNSubscriptionAdapty

// MARK: - Adapty Delegate Proxy

/// Receives Adapty's profile pushes and hands them to the engine on the main actor.
/// (Nhận profile do Adapty đẩy về và chuyển cho engine trên main actor.)
///
/// It holds no state, which is what lets it satisfy `AdaptyDelegate`'s `Sendable`
/// requirement without `@unchecked`.
/// (Nó không giữ state nào, nhờ vậy đáp ứng yêu cầu `Sendable` của `AdaptyDelegate` mà không
/// cần `@unchecked`.)
final class TNAdaptyDelegateProxy: AdaptyDelegate {
    static let shared = TNAdaptyDelegateProxy()

    func didLoadLatestProfile(_ profile: AdaptyProfile) {
        Task { @MainActor in
            TNSubscriptionAdapty.shared?.apply(profile: profile, reason: "Adapty pushed an updated profile")
        }
    }
}

// MARK: - TNSubscriptionAdapty

/// The main entry point for TNSubscriptionAdapty: subscriptions backed by **Adapty**.
/// (Điểm vào chính của TNSubscriptionAdapty: subscription chạy trên **Adapty**.)
///
/// ```swift
/// TNSubscriptionAdapty.configure(config: TNSubscriptionConfig(
///     apiKey: "public_live_xxxxx",
///     entitlements: [TNEntitlement(id: "premium", productIDs: ["com.app.weekly", "com.app.yearly"])],
///     currentOfferingIdentifier: "main"
/// ))
///
/// if TNSubscriptionAdapty.shared.isPremium { ... }
/// TNSubscriptionAdapty.presentDefaultPaywall(from: viewController)
/// ```
///
/// ### Source of truth (Nguồn chân lý)
/// Adapty's server profile decides access: it sees purchases from every platform plus grants
/// made in the dashboard. When Adapty is unreachable, the engine falls back to Apple's local
/// `Transaction.currentEntitlements` (see `TNSubscriptionConfig.offlineStoreKitFallback`), so a
/// paying user is never locked out by a network error.
/// (Profile trên server Adapty quyết định quyền truy cập: nó thấy giao dịch từ mọi nền tảng cùng
/// các quyền cấp từ dashboard. Khi không kết nối được Adapty, engine dùng
/// `Transaction.currentEntitlements` cục bộ của Apple, để người đã trả tiền không bao giờ bị khoá
/// chỉ vì lỗi mạng.)
@MainActor
public final class TNSubscriptionAdapty: ObservableObject {

    // MARK: - Singleton

    /// The shared instance, available after `configure(config:)`.
    /// (Instance dùng chung, có sau khi gọi `configure(config:)`.)
    public private(set) static var shared: TNSubscriptionAdapty!

    /// `true` once `configure(config:)` has run. (`true` sau khi `configure(config:)` đã chạy.)
    public static var isConfigured: Bool { shared != nil }

    // MARK: - Published State

    /// The three states a paywall must distinguish. Never show a paywall during `.unknown`.
    /// (Ba trạng thái paywall cần phân biệt. Đừng bao giờ hiện paywall khi đang `.unknown`.)
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

    /// The placement currently in `availablePackages`.
    /// (Placement đang nằm trong `availablePackages`.)
    @Published public private(set) var currentOfferingIdentifier: String?

    /// `true` once `Adapty.activate` has succeeded. Purchases and placements need it; local
    /// entitlement checks do not.
    /// (`true` sau khi `Adapty.activate` thành công. Mua và placement cần nó; kiểm tra quyền lợi
    /// cục bộ thì không.)
    @Published public private(set) var isAdaptyActivated = false

    // MARK: - Internal State

    private let config: TNSubscriptionConfig
    private let keyProblem: TNKeyProblem?
    private var currentFlow: AdaptyFlow?
    private var loggedFlowIds: Set<String> = []
    private var activationTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?

    private let entitlementCacheKey = "tn_adapty_cachedEntitlements"

    // MARK: - Nonisolated Snapshot

    /// A thread-safe snapshot of `isPremium`, readable from any context without `await`.
    /// (Snapshot an toàn luồng của `isPremium`, đọc được từ mọi ngữ cảnh không cần `await`.)
    public nonisolated static var cachedIsPremium: Bool { TNEntitlementSnapshot.shared.isPremium }

    /// A thread-safe snapshot of `activeEntitlements`.
    /// (Snapshot an toàn luồng của `activeEntitlements`.)
    public nonisolated static var cachedActiveEntitlements: Set<String> {
        TNEntitlementSnapshot.shared.activeEntitlements
    }

    // MARK: - Configure

    /// Configures the engine and activates Adapty. Call once, at launch.
    /// (Cấu hình engine và kích hoạt Adapty. Gọi một lần, khi khởi động.)
    public static func configure(config: TNSubscriptionConfig) {
        logLevel = config.logLevel
        TNLog.setCategory("TNSubscriptionAdapty")
        TNLog.bridgeAdaptyLogs()

        guard shared == nil else {
            TNLog.warn("configure(config:) was called more than once; the later call was ignored.")
            return
        }

        // The shared check decides both what is wrong and whether it blocks launch, so every
        // engine follows the same policy. Only a blocking problem is kept: it is what stops the SDK.
        let detected = config.isIAPEnabled ? TNVendorKey.check(config.apiKey, for: .adapty) : nil
        var keyProblem: TNKeyProblem?
        if let detected {
            if detected.blocksLaunch(for: .adapty) {
                keyProblem = detected
                TNLog.error("\(detected.explanation(for: .adapty)) Adapty will NOT be activated; entitlements fall back to local StoreKit and purchases are disabled.")
            } else {
                TNLog.warn(detected.explanation(for: .adapty))
            }
        }
        validate(config)
        for warning in config.ignoredSettings(for: .adapty) {
            TNLog.warn(warning)
        }

        shared = TNSubscriptionAdapty(config: config, keyProblem: keyProblem)
        TNLog.info("""
        TNSubscriptionAdapty configured. accessLevels=\(config.allEntitlementIDs), \
        defaultPlacement=\(config.currentOfferingIdentifier ?? "none"), IAP=\(config.isIAPEnabled ? "on" : "off").
        """)
    }

    /// Diagnostic verbosity, for this package and the Adapty SDK alike.
    /// (Mức độ log, áp dụng cho cả package này và Adapty SDK.)
    public static var logLevel: TNLogLevel {
        get { TNLog.level }
        set {
            TNLog.level = newValue
            Adapty.logLevel = newValue.adaptyLevel
        }
    }

    /// Routes this package's and Adapty's logs into your own logging stack.
    /// (Chuyển log của package này và của Adapty vào hệ thống log của bạn.)
    public static var logHandler: ((TNLogLevel, String) -> Void)? {
        get { TNLog.handler }
        set { TNLog.handler = newValue }
    }

    private static func validate(_ config: TNSubscriptionConfig) {
        guard config.isIAPEnabled else {
            TNLog.warn("isIAPEnabled is false — every entitlement is unlocked and Adapty is not activated.")
            return
        }
        if config.entitlements.isEmpty {
            TNLog.error("No entitlements configured. Pass at least one TNEntitlement whose id is an Adapty access level ID.")
        }
        for entitlement in config.entitlements where entitlement.id != entitlement.id.lowercased() {
            // Not an error — Adapty IDs are case-sensitive and may legitimately be mixed case —
            // but the default is lowercase "premium", and "Premium" is the commonest mismatch.
            TNLog.warn("Access level '\(entitlement.id)' has capitals. Adapty IDs are case-sensitive and the default is lowercase 'premium'; make sure this matches the dashboard exactly.")
        }
        if config.offlineStoreKitFallback {
            for entitlement in config.entitlements where entitlement.productIDs.isEmpty {
                TNLog.warn("Access level '\(entitlement.id)' has no productIDs, so the offline fallback can never unlock it. Add the product IDs that grant it.")
            }
        }
        if config.currentOfferingIdentifier == nil {
            TNLog.info("No currentOfferingIdentifier set; every paywall must pass a placement ID explicitly.")
        }
    }

    // MARK: - Init

    private init(config: TNSubscriptionConfig, keyProblem: TNKeyProblem?) {
        self.config = config
        self.keyProblem = keyProblem
        self.currentOfferingIdentifier = config.currentOfferingIdentifier

        guard config.isIAPEnabled else {
            let all = Set(config.allEntitlementIDs)
            entitlementState = .unlocked
            isPremium = true
            activeEntitlements = all
            TNEntitlementSnapshot.shared.update(isPremium: true, active: all)
            return
        }

        // 1. Unlock a known-paying user immediately, before any network round trip.
        applyWarmStartCache()

        // 2. Adapty pushes profile changes (renewals, refunds, dashboard grants) here.
        Adapty.delegate = TNAdaptyDelegateProxy.shared

        // 3. Re-resolve on any StoreKit change too: this is what keeps the offline fallback
        //    current when Adapty itself cannot be reached.
        updatesTask = Task { [weak self] in
            for await _ in StoreKit.Transaction.updates {
                await self?.resolveEntitlement()
            }
        }

        // 4. Activate, then resolve for real — as two tasks, deliberately.
        //    `resolveEntitlement()` waits for `activationTask` to finish. Running the resolve
        //    *inside* that task would make it await itself and never return, leaving the state
        //    stuck on `.unknown` and the paywall spinner turning forever.
        //    (Kích hoạt rồi mới xác định quyền lợi — cố ý tách thành hai task. `resolveEntitlement()`
        //    chờ `activationTask` xong. Nếu chạy resolve *bên trong* task đó, nó sẽ tự chờ chính
        //    mình và không bao giờ trả về, khiến trạng thái kẹt ở `.unknown` và spinner paywall quay
        //    mãi.)
        activationTask = Task { [weak self] in
            await self?.activate()
        }
        Task { [weak self] in
            await self?.resolveEntitlement()
        }
    }

    deinit {
        updatesTask?.cancel()
        activationTask?.cancel()
    }

    private func activate() async {
        guard keyProblem == nil else { return }

        var builder = AdaptyConfiguration
            .builder(withAPIKey: config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            .with(observerMode: config.observerMode)
            .with(logLevel: TNLog.level.adaptyLevel)

        if let userId = config.customerUserId, !userId.isEmpty {
            let token = config.attachAppAccountToken ? TNIdentity.appAccountToken : nil
            builder = builder.with(customerUserId: userId, withAppAccountToken: token)
        }

        do {
            try await Adapty.activate(with: builder.build())
            isAdaptyActivated = true
            TNLog.info("Adapty activated.")
        } catch {
            entitlementError = error.localizedDescription
            TNLog.error("Adapty activation FAILED: \(error.localizedDescription). Falling back to local StoreKit entitlements.")
        }
    }

    /// Waits for activation to finish, so a call made right after launch does not race it.
    /// (Chờ kích hoạt xong, để một lời gọi ngay sau khi khởi động không bị race với nó.)
    private func awaitActivation() async {
        await activationTask?.value
    }

    /// Waits until Adapty has finished activating, and returns whether it succeeded.
    /// (Chờ tới khi Adapty kích hoạt xong, và trả về việc kích hoạt có thành công hay không.)
    ///
    /// **Call this before `AdaptyUI.activate()`.** Adapty activates in a background task started
    /// by `configure(config:)`, and `AdaptyUI.activate()` throws `adaptyNotActivated` if that task
    /// has not begun yet — so calling it right after `configure` fails intermittently.
    /// (**Gọi hàm này trước `AdaptyUI.activate()`.** Adapty kích hoạt trong một task nền do
    /// `configure(config:)` khởi chạy, và `AdaptyUI.activate()` sẽ throw `adaptyNotActivated` nếu
    /// task đó chưa bắt đầu — nên gọi ngay sau `configure` sẽ thỉnh thoảng thất bại.)
    ///
    /// ```swift
    /// if await TNSubscription.shared.waitUntilAdaptyActivated() {
    ///     try await AdaptyUI.activate()
    /// }
    /// ```
    ///
    /// Returns `false` without waiting when IAP is disabled, and `false` once activation has
    /// failed (a bad API key, for example) — it never hangs.
    /// (Trả về `false` ngay khi IAP bị tắt, và `false` khi kích hoạt thất bại — ví dụ API key sai.
    /// Hàm này không bao giờ treo.)
    @discardableResult
    public func waitUntilAdaptyActivated() async -> Bool {
        await awaitActivation()
        return isAdaptyActivated
    }

    // MARK: - Entitlement Queries

    /// Whether one access level is active. (Một access level có đang hoạt động không.)
    public func hasEntitlement(_ entitlementId: String) -> Bool {
        activeEntitlements.contains(entitlementId)
    }

    /// The product IDs configured for an access level. (Các product ID đã cấu hình cho một access level.)
    public func productIDs(for entitlementId: String) -> Set<String> {
        config.entitlements.first { $0.id == entitlementId }?.productIDs ?? []
    }

    /// Detailed state for one access level. (Trạng thái chi tiết của một access level.)
    public func entitlementInfo(for entitlementId: String) -> TNEntitlementInfo? {
        customerInfo?.entitlements[entitlementId]
    }

    /// The product behind the first active access level. (Sản phẩm đứng sau access level đầu tiên đang hoạt động.)
    public var currentPlanProductID: String? {
        for entitlement in config.entitlements {
            if let info = customerInfo?.entitlements[entitlement.id], info.isActive {
                return info.productIdentifier
            }
        }
        return nil
    }

    /// The product behind one access level, if active. (Sản phẩm đứng sau một access level, nếu đang hoạt động.)
    public func currentProductID(for entitlementId: String) -> String? {
        guard let info = customerInfo?.entitlements[entitlementId], info.isActive else { return nil }
        return info.productIdentifier
    }

    /// A human-readable name for the current plan. (Tên dễ đọc của gói hiện tại.)
    public var currentPlanDisplayName: String? {
        guard let productID = currentPlanProductID else { return nil }
        if let package = availablePackages.first(where: { $0.productIdentifier == productID }) {
            return package.packageType.localizedName ?? package.localizedTitle
        }
        return Self.displayName(forProductID: productID)
    }

    /// Guesses a plan name from a product ID. (Đoán tên gói từ product ID.)
    public static func displayName(forProductID productID: String) -> String {
        TNPackageType.displayName(forProductID: productID)
    }

    // MARK: - Identity

    /// The persistent Keychain client ID. (Client ID cố định trong Keychain.)
    public nonisolated static var clientId: String { TNIdentity.clientId }

    /// The per-install vendor identifier. (Vendor identifier theo lần cài.)
    public nonisolated static var deviceId: String { TNIdentity.deviceId }

    /// Identity headers for your own backend. (Header danh tính để gọi backend của bạn.)
    public nonisolated static func identityHeaders(userId: String? = nil) -> [String: String] {
        TNIdentity.identityHeaders(userId: userId)
    }

    /// Ties the Adapty profile to your own user ID — call after login.
    /// (Gắn Adapty profile với user ID của bạn — gọi sau khi đăng nhập.)
    ///
    /// Purchases made while anonymous are merged into the identified profile by Adapty.
    /// (Giao dịch thực hiện lúc ẩn danh sẽ được Adapty gộp vào profile đã định danh.)
    public func identify(_ customerUserId: String) async throws {
        await awaitActivation()
        guard isAdaptyActivated else { throw TNPurchaseError.notActivated }
        let token = config.attachAppAccountToken ? TNIdentity.appAccountToken : nil
        try await Adapty.identify(customerUserId, withAppAccountToken: token)
        TNLog.info("Identified the Adapty profile with a customer user ID.")
        await resolveEntitlement()
    }

    /// Returns to an anonymous profile — call on logout.
    /// (Quay về profile ẩn danh — gọi khi đăng xuất.)
    public func logout() async throws {
        await awaitActivation()
        guard isAdaptyActivated else { throw TNPurchaseError.notActivated }
        try await Adapty.logout()
        TNLog.info("Logged out of the Adapty profile.")
        await resolveEntitlement()
    }

    // MARK: - Entitlement Resolution

    /// Re-reads the user's access levels. Safe to call often.
    /// (Đọc lại access level của người dùng. Gọi thường xuyên vẫn an toàn.)
    ///
    /// Order: Adapty profile → (if unreachable) Apple's local entitlements → (if the fallback is
    /// off) keep the last known state. A transient network error never locks a user who was
    /// unlocked a moment ago.
    /// (Thứ tự: Adapty profile → (nếu không kết nối được) quyền lợi cục bộ của Apple → (nếu tắt
    /// phương án dự phòng) giữ trạng thái đã biết gần nhất. Lỗi mạng tạm thời không bao giờ khoá
    /// một người vừa được mở khoá trước đó.)
    public func resolveEntitlement() async {
        guard config.isIAPEnabled else {
            apply(info: nil, state: .unlocked, active: Set(config.allEntitlementIDs))
            return
        }

        await awaitActivation()

        if isAdaptyActivated {
            do {
                let profile = try await Adapty.getProfile()
                entitlementError = nil
                apply(profile: profile, reason: "getProfile")
                return
            } catch {
                entitlementError = error.localizedDescription
                TNLog.warn("Adapty getProfile FAILED (\(error.localizedDescription)).")
            }
        }

        guard config.offlineStoreKitFallback else {
            if entitlementState == .unknown {
                apply(info: nil, state: .locked, active: [])
            }
            TNLog.warn("Offline fallback is disabled; keeping the last known state (\(entitlementState.rawValue)).")
            return
        }

        let info = await buildFromStoreKit()
        TNLog.info("Resolved from local StoreKit (offline fallback): \(info.entitlements.activeIdentifiers.sorted()).")
        apply(info: info)
    }

    /// Fire-and-forget variant of `resolveEntitlement()`.
    /// (Phiên bản "gọi rồi quên" của `resolveEntitlement()`.)
    public func checkSubscriptionStatus() {
        Task { await resolveEntitlement() }
    }

    /// Applies an Adapty profile. Called from `resolveEntitlement`, purchases, restores, and the
    /// delegate.
    /// (Áp dụng một Adapty profile. Được gọi từ `resolveEntitlement`, mua, phục hồi và delegate.)
    func apply(profile: AdaptyProfile, reason: String) {
        let configured = Set(config.allEntitlementIDs)
        let info = TNCustomerInfo(profile: profile, configuredIds: configured)

        let unconfigured = Set(profile.accessLevels.filter(\.value.isActive).keys).subtracting(configured)
        if !unconfigured.isEmpty {
            TNLog.warn("""
            Adapty reports active access level(s) \(unconfigured.sorted()) that are not in your config, \
            so they unlock nothing here. Configured: \(configured.sorted()). Adapty IDs are \
            case-sensitive — check for a 'Premium' vs 'premium' mismatch.
            """)
        }

        TNLog.debug("Applied Adapty profile (\(reason)): active=\(info.entitlements.activeIdentifiers.sorted()).")
        apply(info: info)
    }

    private func apply(info: TNCustomerInfo) {
        let active = info.entitlements.activeIdentifiers
        persistEntitlementCache(from: info)
        apply(info: info, state: active.isEmpty ? .locked : .unlocked, active: active)
    }

    private func apply(info: TNCustomerInfo?, state: EntitlementState, active: Set<String>) {
        if let info { customerInfo = info }
        if entitlementState != state || activeEntitlements != active {
            TNLog.debug("State → \(state.rawValue), active=\(active.sorted()).")
        }
        entitlementState = state
        isPremium = !active.isEmpty
        activeEntitlements = active
        TNEntitlementSnapshot.shared.update(isPremium: !active.isEmpty, active: active)
    }

    /// Reads Apple's verified local entitlements and maps them through `TNEntitlement.productIDs`.
    /// (Đọc quyền lợi cục bộ đã xác minh của Apple và map qua `TNEntitlement.productIDs`.)
    private func buildFromStoreKit() async -> TNCustomerInfo {
        var infos: [String: TNEntitlementInfo] = [:]
        var owned: Set<String> = []
        var subscriptions: Set<String> = []
        let now = Date()

        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry <= now { continue }

            owned.insert(transaction.productID)
            if transaction.productType == .autoRenewable { subscriptions.insert(transaction.productID) }

            for entitlement in config.entitlements where entitlement.productIDs.contains(transaction.productID) {
                let candidate = TNEntitlementInfo(entitlementId: entitlement.id, transaction: transaction)
                // Prefer the grant that lasts longest; a lifetime purchase (no expiry) beats all.
                if let existing = infos[entitlement.id],
                   (existing.expirationDate ?? .distantFuture) >= (candidate.expirationDate ?? .distantFuture) {
                    continue
                }
                infos[entitlement.id] = candidate
            }
        }

        return TNCustomerInfo(
            entitlements: TNEntitlementInfos(all: infos),
            activeSubscriptions: subscriptions,
            allPurchasedProductIdentifiers: owned,
            nonSubscriptionProductIdentifiers: owned.subtracting(subscriptions),
            latestExpirationDate: infos.values.compactMap(\.expirationDate).max(),
            originalPurchaseDate: infos.values.compactMap(\.originalPurchaseDate).min(),
            source: .storeKitFallback
        )
    }

    // MARK: - Warm Start Cache

    /// Unlocks immediately at launch from the last verified result, trusting only unexpired
    /// entries. A lifetime grant is stored as the distant future.
    /// (Mở khoá ngay khi khởi động dựa trên kết quả đã xác minh lần trước, chỉ tin bản ghi còn hạn.
    /// Quyền vĩnh viễn được lưu bằng distant future.)
    private func applyWarmStartCache() {
        let stillValid = TNEntitlementCache.unexpired(key: entitlementCacheKey)
        guard !stillValid.isEmpty else { return }
        activeEntitlements = stillValid
        isPremium = true
        entitlementState = .unlocked
        TNEntitlementSnapshot.shared.update(isPremium: true, active: stillValid)
        TNLog.debug("Warm start unlocked \(stillValid.sorted()) from cache, pending verification.")
    }

    private func persistEntitlementCache(from info: TNCustomerInfo) {
        TNEntitlementCache.store(info.entitlements.active.mapValues(\.expirationDate), key: entitlementCacheKey)
    }

    // MARK: - Placements (Offerings)

    /// Fire-and-forget variant of `loadOfferings(offeringIdentifier:)`.
    /// (Phiên bản "gọi rồi quên" của `loadOfferings(offeringIdentifier:)`.)
    public func fetchOfferings(offeringIdentifier: String? = nil) {
        Task { await loadOfferings(offeringIdentifier: offeringIdentifier) }
    }

    /// Loads an Adapty placement into `availablePackages`.
    /// (Tải một placement của Adapty vào `availablePackages`.)
    ///
    /// - Parameter offeringIdentifier: The **placement ID**. `nil` uses `currentOfferingIdentifier`.
    ///   (**Placement ID**. `nil` dùng `currentOfferingIdentifier`.)
    ///
    /// Packages keep the order set in the Adapty dashboard. Unlike `TNSubscriptionCore`, nothing
    /// is re-sorted: the order is part of what an Adapty A/B test varies.
    /// (Các gói giữ thứ tự đã đặt trên dashboard Adapty. Khác với `TNSubscriptionCore`, không sắp
    /// xếp lại: thứ tự là một phần mà A/B test của Adapty thay đổi.)
    public func loadOfferings(offeringIdentifier: String? = nil) async {
        guard config.isIAPEnabled else {
            availablePackages = []
            offeringsError = NSLocalizedString("In-app purchases are not enabled.", comment: "")
            return
        }

        isLoadingOfferings = true
        offeringsError = nil
        defer { isLoadingOfferings = false }

        await awaitActivation()

        guard isAdaptyActivated else {
            availablePackages = []
            offeringsError = NSLocalizedString("Plans could not be loaded.", comment: "")
            TNLog.error("loadOfferings skipped: Adapty is not activated (\(keyProblem?.explanation(for: .adapty) ?? entitlementError ?? "activation failed")).")
            return
        }

        guard let placementId = offeringIdentifier ?? config.currentOfferingIdentifier, !placementId.isEmpty else {
            availablePackages = []
            offeringsError = NSLocalizedString("Plans could not be loaded.", comment: "")
            TNLog.error("loadOfferings needs a placement ID: pass one, or set TNSubscriptionConfig.currentOfferingIdentifier.")
            return
        }

        do {
            let flow = try await Adapty.getFlow(placementId: placementId)
            let products = try await Adapty.getPaywallProducts(flow: flow)

            currentFlow = flow
            currentOfferingIdentifier = placementId
            availablePackages = products.map { TNPackage(offeringIdentifier: placementId, adaptyProduct: $0) }
            updateIntroEligibility(from: products)

            if products.isEmpty {
                offeringsError = NSLocalizedString("No subscription plans are available right now. Please try again later.", comment: "")
                TNLog.error("""
                Placement '\(placementId)' returned 0 products. Adapty drops any product the App Store did \
                not return, so check: the product IDs in Adapty match App Store Connect exactly; the Paid \
                Applications Agreement is active; the products are approved; and, in the Simulator, a \
                .storekit configuration file is attached to the scheme.
                """)
            } else {
                TNLog.info("Loaded placement '\(placementId)' (flow '\(flow.name)', variation \(flow.variationId)) with \(products.count) product(s).")
            }
        } catch {
            availablePackages = []
            offeringsError = error.localizedDescription
            TNLog.error("Loading placement '\(placementId)' FAILED: \(error.localizedDescription). Check the placement ID exists in the Adapty dashboard.")
        }
    }

    /// Tells Adapty this placement's paywall was shown. **Required for A/B tests.**
    /// (Báo cho Adapty biết paywall của placement này đã được hiển thị. **Bắt buộc cho A/B test.**)
    ///
    /// Adapty measures conversion as purchases ÷ views. A custom paywall that never reports its
    /// views gives every variant a zero denominator, and the A/B test results mean nothing.
    /// `TNDefaultPaywallView` calls this for you; call it yourself from a custom paywall. It
    /// reports each flow once per session.
    /// (Adapty đo tỉ lệ chuyển đổi = giao dịch ÷ lượt xem. Một paywall tự viết mà không báo lượt
    /// xem sẽ khiến mọi biến thể có mẫu số bằng 0, và kết quả A/B test trở nên vô nghĩa.
    /// `TNDefaultPaywallView` tự gọi hàm này; nếu tự viết paywall thì hãy tự gọi. Mỗi flow chỉ
    /// được báo một lần mỗi phiên.)
    public func logPaywallShown() async {
        guard let flow = currentFlow, isAdaptyActivated else { return }
        guard !loggedFlowIds.contains(flow.id) else { return }
        do {
            try await Adapty.logShowFlow(flow)
            loggedFlowIds.insert(flow.id)
            TNLog.debug("Logged a paywall view for flow '\(flow.name)'.")
        } catch {
            TNLog.warn("Logging the paywall view FAILED: \(error.localizedDescription). This placement's A/B test will undercount views.")
        }
    }

    /// Remote config attached to the current placement in the Adapty dashboard, flattened to
    /// strings — headline copy, badge labels, feature flags.
    /// (Remote config gắn với placement hiện tại trên dashboard Adapty, chuyển thành chuỗi —
    /// tiêu đề, nhãn badge, feature flag.)
    public var currentOfferingMetadata: [String: String] {
        guard let dictionary = currentFlow?.remoteConfigs.first?.dictionary else { return [:] }
        return dictionary.reduce(into: [:]) { result, pair in
            result[pair.key] = "\(pair.value)"
        }
    }

    /// The raw remote config JSON, for values that are not plain strings.
    /// (JSON remote config gốc, cho các giá trị không phải chuỗi thuần.)
    public var currentRemoteConfigJSON: String? {
        currentFlow?.remoteConfigs.first?.jsonString
    }

    // MARK: - Offers

    private func updateIntroEligibility(from products: [AdaptyPaywallProduct]) {
        var updated = introEligibility
        for product in products {
            updated[product.vendorProductId] = Self.introEligibility(
                hasIntroOffer: product.skProduct.subscription?.introductoryOffer != nil,
                selectedOfferType: product.subscriptionOffer.map { TNOfferType($0.offerType) }
            )
        }
        introEligibility = updated
    }

    /// Derives intro eligibility from the one offer Adapty selected.
    /// (Suy ra điều kiện ưu đãi người mới từ ưu đãi duy nhất mà Adapty đã chọn.)
    ///
    /// Adapty only attaches an introductory offer when the user is eligible for it, so its
    /// presence *is* eligibility. A product that has an intro offer but got a different one (or
    /// none) is ineligible for the intro.
    /// (Adapty chỉ gắn ưu đãi người mới khi người dùng đủ điều kiện, nên việc nó xuất hiện *chính
    /// là* điều kiện. Sản phẩm có ưu đãi người mới mà lại nhận ưu đãi khác (hoặc không có) thì
    /// không đủ điều kiện nhận ưu đãi người mới.)
    nonisolated static func introEligibility(hasIntroOffer: Bool, selectedOfferType: TNOfferType?) -> TNIntroEligibilityStatus {
        guard hasIntroOffer else { return .noIntroOfferExists }
        return selectedOfferType == .introductory ? .eligible : .ineligible
    }

    /// `true` when the user may claim this package's introductory offer.
    /// (`true` khi người dùng còn được nhận ưu đãi người mới của gói này.)
    public func isEligibleForIntroOffer(package: TNPackage) -> Bool {
        introEligibility[package.productIdentifier] == .eligible
    }

    /// `true` when the user may claim the introductory offer of a product ID.
    /// (`true` khi người dùng còn được nhận ưu đãi người mới của một product ID.)
    public func isEligibleForIntroOffer(productID: String) -> Bool {
        introEligibility[productID] == .eligible
    }

    /// The offer the user will get on this package — introductory, promotional or win-back.
    /// `makePurchase` applies it automatically.
    /// (Ưu đãi người dùng sẽ nhận trên gói này — người mới, promotional hoặc win-back.
    /// `makePurchase` tự áp dụng nó.)
    public func offer(for package: TNPackage) -> TNSubscriptionOffer? {
        package.adaptyProduct.subscriptionOffer.map {
            TNSubscriptionOffer(adaptyOffer: $0, productIdentifier: package.productIdentifier)
        }
    }

    /// The introductory offer, **only** if that is the offer the user will get.
    /// (Ưu đãi người mới, **chỉ khi** đó đúng là ưu đãi người dùng sẽ nhận.)
    public func introOffer(for package: TNPackage) -> TNSubscriptionOffer? {
        guard let offer = offer(for: package), offer.type == .introductory else { return nil }
        return offer
    }

    /// A localised summary of the intro offer, e.g. `"3 Days Free Trial"`.
    /// (Mô tả đã dịch của ưu đãi người mới, ví dụ `"Dùng thử miễn phí 3 Ngày"`.)
    public func introOfferSummary(for package: TNPackage) -> String? {
        introOffer(for: package)?.localizedSummary
    }

    // MARK: - Purchase

    /// Buys a package through Adapty, applying whichever offer Adapty selected.
    /// (Mua một gói qua Adapty, kèm ưu đãi mà Adapty đã chọn.)
    @discardableResult
    public func purchaseAsync(package: TNPackage) async throws -> TNCustomerInfo {
        await awaitActivation()
        guard isAdaptyActivated else {
            TNLog.error("Purchase refused: Adapty is not activated (\(keyProblem?.explanation(for: .adapty) ?? entitlementError ?? "activation failed")).")
            throw TNPurchaseError.notActivated
        }

        isPurchasing = true
        defer { isPurchasing = false }

        let productID = package.productIdentifier
        TNLog.info("Purchasing \(productID)\(offer(for: package).map { " with \($0.type.rawValue) offer" } ?? "")…")

        let result: AdaptyPurchaseResult
        do {
            result = try await Adapty.makePurchase(product: package.adaptyProduct)
        } catch {
            if error.adaptyErrorCode == .paymentCancelled {
                TNLog.info("Purchase of \(productID) cancelled by the user.")
                throw TNPurchaseError.userCancelled
            }
            TNLog.error("Purchase of \(productID) FAILED: \(error.localizedDescription)")
            // The transaction may exist even when Adapty's validation failed: re-read rather than
            // leave the user locked until the next launch.
            await resolveEntitlement()
            throw TNPurchaseError.adapty(error)
        }

        switch result {
        case .success(let profile, _):
            apply(profile: profile, reason: "purchase")
            TNLog.info("Purchase of \(productID) succeeded. active=\(activeEntitlements.sorted())")
            if activeEntitlements.isEmpty {
                TNLog.warn("""
                The purchase succeeded but unlocked nothing. In the Adapty dashboard, check that \(productID) \
                is attached to one of \(config.allEntitlementIDs.sorted()), with the ID spelt exactly the same.
                """)
            }
            return customerInfo ?? TNCustomerInfo()
        case .userCancelled:
            TNLog.info("Purchase of \(productID) cancelled by the user.")
            throw TNPurchaseError.userCancelled
        case .pending:
            TNLog.info("Purchase of \(productID) is PENDING external approval (Ask to Buy / SCA).")
            throw TNPurchaseError.purchasePending
        }
    }

    /// Completion-handler variant, always called on the main actor.
    /// (Bản dùng completion handler, luôn gọi lại trên main actor.)
    public func purchase(package: TNPackage, completion: @escaping (Result<TNCustomerInfo, Error>) -> Void) {
        Task { @MainActor in
            do {
                completion(.success(try await purchaseAsync(package: package)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Restore

    /// Restores purchases and returns whether anything is now active.
    /// (Phục hồi giao dịch và trả về việc hiện có quyền lợi nào hoạt động hay không.)
    @discardableResult
    public func restorePurchasesAsync() async throws -> Bool {
        await awaitActivation()
        TNLog.info("Restoring purchases…")

        guard isAdaptyActivated else {
            // Without Adapty, a restore is just a fresh read of Apple's local entitlements.
            await resolveEntitlement()
            return isPremium
        }

        do {
            let profile = try await Adapty.restorePurchases()
            apply(profile: profile, reason: "restore")
        } catch {
            TNLog.error("Restore FAILED: \(error.localizedDescription)")
            throw TNPurchaseError.adapty(error)
        }

        TNLog.info(isPremium ? "Restored: \(activeEntitlements.sorted())" : "Restore completed but found no active access level.")
        return isPremium
    }

    /// Completion-handler variant, always called on the main actor.
    /// (Bản dùng completion handler, luôn gọi lại trên main actor.)
    public func restorePurchases(completion: @escaping (Result<Bool, Error>) -> Void) {
        Task { @MainActor in
            do {
                completion(.success(try await restorePurchasesAsync()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Apple Sheets

    /// Presents Apple's Offer Code redemption sheet. (Hiển thị bảng nhập Offer Code của Apple.)
    public func presentOfferCodeRedemption() {
        Adapty.presentCodeRedemptionSheet()
    }

    /// Presents Apple's Manage Subscriptions sheet, falling back to the App Store page.
    /// (Hiển thị bảng Quản lý đăng ký của Apple, nếu không được thì mở trang App Store.)
    public func showManageSubscriptions() {
        TNAppStoreSheets.showManageSubscriptions()
    }

    /// Presents Apple's refund request sheet for an owned App Store product.
    /// (Hiển thị bảng yêu cầu hoàn tiền của Apple cho một sản phẩm App Store đang sở hữu.)
    @discardableResult
    public func requestRefund(for productID: String) async -> Bool {
        await TNAppStoreSheets.requestRefund(for: productID)
    }

    // MARK: - Paywall Helpers

    /// The genuinely cheapest plan per month. (Gói thật sự rẻ nhất tính theo tháng.)
    public var recommendedPackage: TNPackage? {
        TNPriceMath.recommended(availablePackages, pricePerMonth: \.pricePerMonth)
    }

    /// `true` when this package is the recommended one. (`true` khi đây là gói được đề xuất.)
    public func isRecommended(_ package: TNPackage) -> Bool {
        recommendedPackage?.identifier == package.identifier
    }

    // MARK: - Testing

    /// **Test-only.** Drops the singleton so another `configure` can run.
    /// (**Chỉ dùng cho test.** Bỏ singleton để có thể gọi `configure` lần nữa.)
    internal static func resetForTesting(preserveCache: Bool = false) {
        shared?.updatesTask?.cancel()
        shared?.activationTask?.cancel()
        shared = nil
        if !preserveCache {
            TNEntitlementCache.clear(key: "tn_adapty_cachedEntitlements")
        }
        TNEntitlementSnapshot.shared.update(isPremium: false, active: [])
    }
}

// MARK: - TNPurchaseError

/// What can go wrong in a purchase flow, with messages written for a user.
/// (Những lỗi có thể xảy ra khi mua, với thông báo viết cho người dùng đọc.)
public enum TNPurchaseError: LocalizedError {
    /// The user dismissed Apple's payment sheet. (Người dùng đã tắt bảng thanh toán của Apple.)
    case userCancelled
    /// Waiting on Ask to Buy or SCA. (Đang chờ Ask to Buy hoặc SCA.)
    case purchasePending
    /// Adapty is not activated — bad API key or activation failure.
    /// (Adapty chưa được kích hoạt — API key sai hoặc kích hoạt thất bại.)
    case notActivated
    /// Adapty reported an error. (Adapty báo lỗi.)
    case adapty(AdaptyError)

    public var errorDescription: String? {
        switch self {
        case .userCancelled:
            return NSLocalizedString("Purchase was cancelled.", comment: "")
        case .purchasePending:
            return NSLocalizedString("Your purchase is waiting for approval. You'll get access as soon as it's approved.", comment: "")
        case .notActivated:
            return NSLocalizedString("Purchases are not available right now. Please try again later.", comment: "")
        case .adapty(let error):
            return error.localizedDescription
        }
    }
}
