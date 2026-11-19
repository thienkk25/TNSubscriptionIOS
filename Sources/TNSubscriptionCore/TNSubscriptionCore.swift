import Foundation
import StoreKit
@_exported import SwiftUI
import Combine
import UIKit

// MARK: - Shared Configuration

// TNSubscriptionConfig, TNEntitlement, TNOffering, TNLogLevel, DefaultPaywallConfig and
// TNConsumableProduct live in TNSubscriptionShared, so they are identical in every engine.
// (Các kiểu cấu hình nằm trong TNSubscriptionShared, nên giống hệt nhau ở mọi engine.)
@_exported import TNSubscriptionShared

/// The engine-neutral name for this engine's entry point. Code that uses only the shared
/// configuration and the common API compiles against any engine unchanged; the exact list is in
/// README, "What is the same, what differs", and is enforced by `TNEngineContractTests`.
/// (Tên trung lập cho điểm vào của engine này. Code chỉ dùng cấu hình chung và phần API chung thì
/// compile được với mọi engine mà không phải sửa; danh sách chính xác nằm trong README, mục "What is
/// the same, what differs", và được `TNEngineContractTests` bảo đảm.)
public typealias TNSubscription = TNSubscriptionCore

// MARK: - TNEntitlementSnapshot

/// A lock-protected mirror of the entitlement state, living outside the main actor so
/// background code can read it without `await`.
/// (Bản sao của trạng thái quyền lợi được bảo vệ bằng lock, nằm ngoài main actor để code
/// background đọc được mà không cần `await`.)
///
/// It exists because `TNSubscriptionCore` is `@MainActor`: its stored properties cannot be
/// touched from a background thread at all, and a `nonisolated(unsafe)` static would be
/// exactly the data race the isolation is there to prevent.
/// (Nó tồn tại vì `TNSubscriptionCore` là `@MainActor`: các thuộc tính của nó không thể bị
/// truy cập từ thread background, và dùng `nonisolated(unsafe)` sẽ tạo ra đúng cái data race
/// mà việc cô lập này muốn ngăn.)
final class TNEntitlementSnapshot: @unchecked Sendable {

    static let shared = TNEntitlementSnapshot()

    private let lock = NSLock()
    private var _isPremium = false
    private var _activeEntitlements: Set<String> = []

    private init() {}

    var isPremium: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isPremium
    }

    var activeEntitlements: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return _activeEntitlements
    }

    func update(isPremium: Bool, active: Set<String>) {
        lock.lock()
        _isPremium = isPremium
        _activeEntitlements = active
        lock.unlock()
    }
}

// MARK: - TNSubscriptionCore

/// The main entry point for TNSubscriptionCore: subscriptions and lifetime unlocks
/// built on **Apple StoreKit 2 only**.
/// (Điểm vào chính của TNSubscriptionCore: subscription và mở khoá vĩnh viễn, xây
/// hoàn toàn trên **Apple StoreKit 2**.)
///
/// No API key, no vendor SDK, no third-party network call. Entitlements are decided from
/// Apple's cryptographically signed transactions, verified on-device, and they keep working
/// offline.
/// (Không API key, không SDK bên thứ ba, không gọi mạng tới nhà cung cấp nào. Quyền lợi
/// được quyết định từ các giao dịch có chữ ký số của Apple, xác minh ngay trên thiết bị,
/// và vẫn hoạt động khi offline.)
///
/// ```swift
/// // 1. Configure once at app launch (Cấu hình một lần khi app khởi động)
/// TNSubscriptionCore.configure(config: TNSubscriptionConfig(
///     entitlements: [
///         TNEntitlement(id: "Premium", productIDs: ["com.app.weekly", "com.app.yearly"]),
///     ]
/// ))
///
/// // 2. Check premium status (Kiểm tra trạng thái premium)
/// if TNSubscriptionCore.shared.isPremium { ... }
///
/// // 3. Check one specific entitlement (Kiểm tra một quyền lợi cụ thể)
/// if TNSubscriptionCore.shared.hasEntitlement("Sale") { ... }
///
/// // 4. Present the built-in paywall (Hiển thị paywall có sẵn)
/// TNSubscriptionCore.presentDefaultPaywall(from: viewController)
/// ```
///
/// ### Why `@MainActor` (Vì sao có `@MainActor`)
/// This class publishes SwiftUI state, so it is main-actor isolated — which is also what
/// Swift 6 strict concurrency requires. For entitlement checks from a background context,
/// read the lock-protected snapshot `TNSubscriptionCore.cachedIsPremium`, which is
/// `nonisolated` and needs no `await`.
/// (Class này publish state cho SwiftUI nên được cô lập trên main actor — đây cũng là yêu
/// cầu của strict concurrency trong Swift 6. Nếu cần kiểm tra quyền lợi từ background,
/// hãy đọc snapshot `TNSubscriptionCore.cachedIsPremium` — `nonisolated`, không cần `await`.)
@MainActor
public final class TNSubscriptionCore: ObservableObject {

    // MARK: - Singleton

    /// The shared instance. Only available after `configure(config:)` has been called.
    /// (Instance dùng chung. Chỉ có sau khi đã gọi `configure(config:)`.)
    public private(set) static var shared: TNSubscriptionCore!

    /// `true` once `configure(config:)` has run, so you can guard optional call sites.
    /// (`true` sau khi `configure(config:)` đã chạy, dùng để bảo vệ các lời gọi không bắt buộc.)
    public static var isConfigured: Bool { shared != nil }

    // MARK: - Published State

    /// The three states a paywall needs to distinguish.
    /// (Ba trạng thái mà một paywall cần phân biệt.)
    ///
    /// `.unknown` matters: it is the gap between launch and the first verified answer.
    /// Showing a paywall during `.unknown` is what makes paying users see a paywall for a
    /// fraction of a second on every cold start.
    /// (`.unknown` rất quan trọng: đó là khoảng giữa lúc khởi động và câu trả lời đã xác minh
    /// đầu tiên. Hiển thị paywall trong lúc `.unknown` chính là lý do người đã trả tiền vẫn
    /// thấy paywall nhoáng lên mỗi lần mở app.)
    public enum EntitlementState: String, Sendable {
        /// Not yet determined — show a loading state, never a paywall.
        /// (Chưa xác định — hãy hiện trạng thái đang tải, đừng hiện paywall.)
        case unknown
        /// Verified: this Apple ID owns nothing active.
        /// (Đã xác minh: Apple ID này không có quyền lợi nào đang hoạt động.)
        case locked
        /// Verified: at least one entitlement is active.
        /// (Đã xác minh: có ít nhất một quyền lợi đang hoạt động.)
        case unlocked
    }

    /// The current entitlement state.
    /// (Trạng thái quyền lợi hiện tại.)
    @Published public private(set) var entitlementState: EntitlementState = .unknown

    /// The latest snapshot of everything this Apple ID owns.
    /// (Snapshot mới nhất của mọi thứ Apple ID này đang sở hữu.)
    @Published public private(set) var customerInfo: TNCustomerInfo?

    /// `true` if ANY configured entitlement is currently active.
    /// (`true` nếu BẤT KỲ quyền lợi nào đã cấu hình đang hoạt động.)
    @Published public private(set) var isPremium: Bool = false

    /// The set of currently active entitlement IDs (e.g. `["Premium", "Sale"]`).
    /// (Tập hợp ID các quyền lợi đang hoạt động, ví dụ `["Premium", "Sale"]`.)
    @Published public private(set) var activeEntitlements: Set<String> = []

    /// The packages of the currently loaded offering, sorted longest-period-first.
    /// (Các gói của offering đang tải, sắp xếp theo kỳ hạn dài nhất trước.)
    @Published public private(set) var availablePackages: [TNPackage] = []

    /// Introductory-offer eligibility keyed by StoreKit `productIdentifier`.
    /// (Điều kiện nhận ưu đãi người mới, theo `productIdentifier` của StoreKit.)
    @Published public private(set) var introEligibility: [String: TNIntroEligibilityStatus] = [:]

    /// `true` while products are being fetched from the App Store.
    /// (`true` trong lúc đang lấy sản phẩm từ App Store.)
    @Published public private(set) var isLoadingOfferings = false

    /// `true` while a purchase is in flight.
    /// (`true` trong lúc một giao dịch đang diễn ra.)
    @Published public private(set) var isPurchasing = false

    /// Why no plan could be **displayed**, or `nil` on success.
    /// (Lý do không **hiển thị** được gói nào, hoặc `nil` nếu thành công.)
    @Published public private(set) var offeringsError: String?

    /// Why the last entitlement resolution failed, or `nil` when it completed.
    /// (Lý do lần kiểm tra quyền lợi gần nhất thất bại, hoặc `nil` nếu đã hoàn tất.)
    ///
    /// This is the counterpart to `offeringsError`: that one explains why nothing could be
    /// *displayed*, this one why a purchase could not be *verified*.
    /// Note that `nil` does **not** mean the user is premium — read `isPremium` for that.
    /// (Đây là cặp đối ứng với `offeringsError`: cái kia giải thích vì sao không *hiển thị*
    /// được gì, cái này giải thích vì sao không *xác minh* được giao dịch.
    /// Lưu ý `nil` **không** có nghĩa người dùng là premium — hãy đọc `isPremium`.)
    @Published public private(set) var entitlementError: String?

    /// The identifier of the offering currently in `availablePackages`.
    /// (ID của offering đang nằm trong `availablePackages`.)
    @Published public private(set) var currentOfferingIdentifier: String?

    // MARK: - Internal State

    private let config: TNSubscriptionConfig
    private var offerings: [TNOffering]
    private var loadedProducts: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?
    private var promotionalOfferSigner: TNPromotionalOfferSigner?

    private let entitlementCacheKey = "tn_core_cachedEntitlements"

    // MARK: - Nonisolated Snapshot

    /// A thread-safe snapshot of `isPremium`, readable from any context without `await`.
    /// (Snapshot an toàn luồng của `isPremium`, đọc được từ mọi ngữ cảnh mà không cần `await`.)
    ///
    /// Use it for cheap gating in background code. For UI, bind to `isPremium` so the view
    /// updates when the state changes.
    /// (Dùng để kiểm tra nhanh trong code background. Với UI, hãy bind vào `isPremium` để
    /// view tự cập nhật khi trạng thái đổi.)
    public nonisolated static var cachedIsPremium: Bool {
        TNEntitlementSnapshot.shared.isPremium
    }

    /// A thread-safe snapshot of `activeEntitlements`.
    /// (Snapshot an toàn luồng của `activeEntitlements`.)
    public nonisolated static var cachedActiveEntitlements: Set<String> {
        TNEntitlementSnapshot.shared.activeEntitlements
    }

    private nonisolated static func updateSnapshot(isPremium: Bool, active: Set<String>) {
        TNEntitlementSnapshot.shared.update(isPremium: isPremium, active: active)
    }

    // MARK: - Configure

    /// Configures the SDK. Call once before any other usage, typically in
    /// `application(_:didFinishLaunchingWithOptions:)` or your `App.init()`.
    /// (Cấu hình SDK. Gọi một lần trước mọi thao tác khác, thường trong
    /// `application(_:didFinishLaunchingWithOptions:)` hoặc `App.init()`.)
    ///
    /// Calling it twice is a no-op and logs a warning.
    /// (Gọi lần thứ hai sẽ không làm gì và ghi một cảnh báo.)
    public static func configure(config: TNSubscriptionConfig) {
        TNLog.level = config.logLevel

        guard shared == nil else {
            TNLog.warn("configure(config:) was called more than once; the later call was ignored.")
            return
        }

        validate(config)
        for warning in config.ignoredSettings(for: .storeKit) {
            TNLog.warn(warning)
        }

        shared = TNSubscriptionCore(config: config)
        TNLog.info("""
        TNSubscriptionCore configured. entitlements=\(config.allEntitlementIDs), \
        products=\(config.allLoadableProductIDs.sorted()), \
        offerings=\(config.resolvedOfferings.map(\.identifier)), IAP=\(config.isIAPEnabled ? "on" : "off").
        """)
    }

    /// Tears down the configured instance so another `configure(config:)` can run.
    /// (Phá bỏ instance đã cấu hình để có thể gọi `configure(config:)` lần nữa.)
    ///
    /// **Test-only.** `configure` is deliberately one-shot in production: reconfiguring a live
    /// app mid-session would leave the old `Transaction.updates` listener running against a
    /// stale config. Integration tests need a clean slate per test, so this cancels the
    /// listener, drops the singleton and clears the warm-start cache.
    /// (**Chỉ dùng cho test.** `configure` được cố ý thiết kế chỉ gọi một lần trong production:
    /// cấu hình lại giữa phiên sẽ để lại listener `Transaction.updates` cũ chạy với config cũ.
    /// Integration test cần trạng thái sạch cho mỗi test, nên hàm này huỷ listener, bỏ singleton
    /// và xoá warm-start cache.)
    /// - Parameter preserveCache: Keep the warm-start cache, so a test can assert what a
    ///   second app launch would unlock synchronously.
    ///   (Giữ lại warm-start cache, để test kiểm tra được lần mở app thứ hai mở khoá đồng bộ
    ///   những gì.)
    internal static func resetForTesting(preserveCache: Bool = false) {
        shared?.updatesTask?.cancel()
        shared?.updatesTask = nil
        shared = nil
        if !preserveCache {
            UserDefaults.standard.removeObject(forKey: "tn_core_cachedEntitlements")
        }
        TNEntitlementSnapshot.shared.update(isPremium: false, active: [])
    }

    /// Diagnostic verbosity. Writable at any time, including before `configure`.
    /// (Mức độ log. Có thể gán bất cứ lúc nào, kể cả trước `configure`.)
    public static var logLevel: TNLogLevel {
        get { TNLog.level }
        set { TNLog.level = newValue }
    }

    /// Install a sink to route this package's diagnostics into your own logging stack.
    /// When `nil` (the default), messages go to the unified log under the
    /// `TNSubscriptionCore` category.
    /// (Gắn một handler để chuyển log của package này vào hệ thống log của bạn.
    /// Nếu `nil` (mặc định), log đi vào unified log với category `TNSubscriptionCore`.)
    public static var logHandler: ((TNLogLevel, String) -> Void)? {
        get { TNLog.handler }
        set { TNLog.handler = newValue }
    }

    /// Catches the configuration mistakes that otherwise surface as a silent empty paywall.
    /// (Bắt các lỗi cấu hình mà nếu không sẽ chỉ biểu hiện thành một paywall trống không rõ lý do.)
    private static func validate(_ config: TNSubscriptionConfig) {
        guard config.isIAPEnabled else {
            TNLog.warn("isIAPEnabled is false — every entitlement is unlocked and no purchase will be attempted.")
            return
        }

        if config.entitlements.isEmpty {
            TNLog.error("No entitlements configured. Nothing can ever unlock. Pass at least one TNEntitlement.")
        }

        if config.allProductIDs.isEmpty {
            TNLog.error("No product IDs configured across any entitlement. Nothing can ever unlock.")
        }

        for entitlement in config.entitlements where entitlement.productIDs.isEmpty {
            TNLog.error("Entitlement '\(entitlement.id)' has no product IDs, so it can never become active.")
        }

        let duplicates = Dictionary(grouping: config.entitlements, by: \.id).filter { $1.count > 1 }.keys
        if !duplicates.isEmpty {
            TNLog.error("Duplicate entitlement IDs: \(duplicates.sorted()). Only the first of each will be reachable.")
        }

        // An offering that names a product no entitlement grants will sell the user
        // something that does not unlock anything. That is worth shouting about.
        let entitlementProducts = config.allProductIDs
        for offering in config.resolvedOfferings {
            let orphans = offering.productIDs.filter { !entitlementProducts.contains($0) }
            if !orphans.isEmpty {
                TNLog.warn("""
                Offering '\(offering.identifier)' sells \(orphans) but no entitlement lists those product IDs, \
                so buying them would unlock nothing. Add them to a TNEntitlement.
                """)
            }
            if offering.productIDs.isEmpty {
                TNLog.warn("Offering '\(offering.identifier)' has no product IDs and will render an empty paywall.")
            }
        }

        if config.attachAppAccountToken, TNIdentity.appAccountToken == nil {
            TNLog.warn("""
            attachAppAccountToken is on but the persisted client_id is not a valid UUID, so Apple would \
            reject it. The token will be omitted. This only happens when a non-UUID value was migrated \
            in from an older build.
            """)
        }
    }

    // MARK: - Init

    private init(config: TNSubscriptionConfig) {
        self.config = config
        self.offerings = config.resolvedOfferings
        self.currentOfferingIdentifier = config.currentOfferingIdentifier
            ?? config.resolvedOfferings.first?.identifier

        // IAP disabled: unlock everything and do no StoreKit work at all.
        guard config.isIAPEnabled else {
            let all = Set(config.allEntitlementIDs)
            self.entitlementState = .unlocked
            self.isPremium = true
            self.activeEntitlements = all
            Self.updateSnapshot(isPremium: true, active: all)
            return
        }

        // 1. Warm start from our own cache, so a paying user never sees a paywall flicker.
        //    Unlike a blind cache, this only trusts entries whose expiry is still in the
        //    future, so a lapsed subscription cannot be revived by stale data.
        applyWarmStartCache()

        // 2. Watch for transactions that happen outside a purchase call we made:
        //    renewals, Ask-to-Buy approvals, offer codes, Family Sharing changes,
        //    refunds, and purchases made on another device.
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.handle(externalTransaction: update)
            }
        }

        // 3. Resolve for real.
        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Loads products, finishes anything left over from a previous run, then resolves.
    /// (Tải sản phẩm, hoàn tất các giao dịch còn sót từ lần chạy trước, rồi kiểm tra quyền lợi.)
    private func bootstrap() async {
        await loadProducts()
        await finishPendingTransactions()
        await resolveEntitlement()
    }

    // MARK: - Public Entitlement Queries

    /// Checks whether one specific entitlement is currently active.
    /// (Kiểm tra một quyền lợi cụ thể có đang hoạt động hay không.)
    ///
    /// ```swift
    /// if TNSubscriptionCore.shared.hasEntitlement("Sale") { /* show sale content */ }
    /// ```
    public func hasEntitlement(_ entitlementId: String) -> Bool {
        activeEntitlements.contains(entitlementId)
    }

    /// The product IDs configured for one entitlement.
    /// (Các product ID đã cấu hình cho một quyền lợi.)
    public func productIDs(for entitlementId: String) -> Set<String> {
        config.entitlements.first { $0.id == entitlementId }?.productIDs ?? []
    }

    /// Detailed state for one entitlement, including expiry and renewal intent.
    /// (Thông tin chi tiết của một quyền lợi, gồm ngày hết hạn và ý định gia hạn.)
    public func entitlementInfo(for entitlementId: String) -> TNEntitlementInfo? {
        customerInfo?.entitlements[entitlementId]
    }

    /// The product ID of the user's current plan (the first active entitlement found).
    /// (Product ID của gói hiện tại — quyền lợi đang hoạt động đầu tiên tìm thấy.)
    public var currentPlanProductID: String? {
        for entitlement in config.entitlements {
            if let info = customerInfo?.entitlements[entitlement.id], info.isActive {
                return info.productIdentifier
            }
        }
        return nil
    }

    /// The product ID backing one specific entitlement, if it is active.
    /// (Product ID đang cấp một quyền lợi cụ thể, nếu quyền lợi đó đang hoạt động.)
    public func currentProductID(for entitlementId: String) -> String? {
        guard let info = customerInfo?.entitlements[entitlementId], info.isActive else { return nil }
        return info.productIdentifier
    }

    /// A human-readable name for the user's current plan.
    /// (Tên dễ đọc của gói hiện tại.)
    public var currentPlanDisplayName: String? {
        guard let productID = currentPlanProductID else { return nil }
        if let product = loadedProducts[productID] {
            return TNPackageType.inferred(from: product).localizedName ?? product.displayName
        }
        return Self.displayName(forProductID: productID)
    }

    /// Guesses a display name from a product ID, for when the product is not loaded
    /// (offline cold start, say).
    /// (Đoán tên hiển thị từ product ID, dùng khi chưa tải được sản phẩm —
    /// ví dụ khởi động lạnh lúc offline.)
    ///
    /// Prefer the store-provided `product.displayName` whenever the product is available:
    /// this heuristic only reads the ID string.
    /// (Hãy ưu tiên `product.displayName` do store cung cấp khi có sẵn sản phẩm:
    /// hàm này chỉ suy luận từ chuỗi ID.)
    public static func displayName(forProductID productID: String) -> String {
        let lower = productID.lowercased()
        if lower.contains("week") { return NSLocalizedString("Weekly", comment: "") }
        if lower.contains("month") { return NSLocalizedString("Monthly", comment: "") }
        if lower.contains("year") || lower.contains("annual") { return NSLocalizedString("Yearly", comment: "") }
        if lower.contains("life") || lower.contains("forever") { return NSLocalizedString("Lifetime", comment: "") }
        return NSLocalizedString("Premium", comment: "")
    }

    // MARK: - Identity Passthrough

    /// A persistent client ID stored in the Keychain. See `TNIdentity`.
    /// (Client ID cố định lưu trong Keychain. Xem `TNIdentity`.)
    public nonisolated static var clientId: String { TNIdentity.clientId }

    /// The per-install vendor identifier. See `TNIdentity`.
    /// (Vendor identifier theo lần cài. Xem `TNIdentity`.)
    public nonisolated static var deviceId: String { TNIdentity.deviceId }

    /// Identity headers for your own backend. See `TNIdentity`.
    /// (Các header danh tính để gọi backend của bạn. Xem `TNIdentity`.)
    public nonisolated static func identityHeaders(userId: String? = nil) -> [String: String] {
        TNIdentity.identityHeaders(userId: userId)
    }

    // MARK: - Entitlement Resolution

    /// Re-reads Apple's verified entitlements and republishes state. Safe to call often.
    /// (Đọc lại quyền lợi đã xác minh từ Apple và publish lại state. Gọi thường xuyên vẫn an toàn.)
    ///
    /// This is the single source of truth. It reads `Transaction.currentEntitlements`, which
    /// Apple serves from the on-device signed receipt — so it works offline and needs no server.
    /// (Đây là nguồn chân lý duy nhất. Nó đọc `Transaction.currentEntitlements`, do Apple cung cấp
    /// từ receipt đã ký trên thiết bị — nên hoạt động offline và không cần server.)
    public func resolveEntitlement() async {
        guard config.isIAPEnabled else {
            let all = Set(config.allEntitlementIDs)
            apply(state: .unlocked, isPremium: true, active: all, info: customerInfo)
            return
        }

        let info = await buildCustomerInfo()
        let active = info.entitlements.activeIdentifiers
        let hasPremium = !active.isEmpty

        entitlementError = nil
        persistEntitlementCache(from: info)

        if hasPremium {
            TNLog.info("Unlocked via StoreKit 2: \(active.sorted())")
        } else {
            logNoEntitlementDiagnostics(info: info)
        }

        apply(state: hasPremium ? .unlocked : .locked, isPremium: hasPremium, active: active, info: info)
    }

    /// Fire-and-forget variant of `resolveEntitlement()`.
    /// (Phiên bản "gọi rồi quên" của `resolveEntitlement()`.)
    public func checkSubscriptionStatus() {
        Task { await resolveEntitlement() }
    }

    /// Walks every current entitlement Apple reports and assembles a `TNCustomerInfo`.
    /// (Duyệt mọi quyền lợi hiện tại Apple báo về và dựng nên một `TNCustomerInfo`.)
    private func buildCustomerInfo() async -> TNCustomerInfo {
        var entitlementInfos: [String: TNEntitlementInfo] = [:]
        var activeSubscriptions: Set<String> = []
        var allOwned: Set<String> = []
        var nonSubscriptions: Set<String> = []
        var latestExpiration: Date?
        var earliestPurchase: Date?
        var inspected = 0
        var unverified = 0

        let now = Date()

        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                unverified += 1
                TNLog.warn("Skipping an UNVERIFIED StoreKit transaction (failed on-device JWS validation).")
                continue
            }

            inspected += 1

            guard transaction.tn_isEntitling(asOf: now) else {
                TNLog.debug("Skipping \(transaction.productID): revoked=\(transaction.revocationDate != nil), expiry=\(transaction.expirationDate.map(String.init(describing:)) ?? "none").")
                continue
            }

            allOwned.insert(transaction.productID)

            if transaction.productType == .autoRenewable {
                activeSubscriptions.insert(transaction.productID)
            } else if transaction.productType == .nonConsumable {
                nonSubscriptions.insert(transaction.productID)
            }

            if let expiry = transaction.expirationDate {
                latestExpiration = max(latestExpiration ?? expiry, expiry)
            }
            let originalDate = transaction.originalPurchaseDate
            earliestPurchase = min(earliestPurchase ?? originalDate, originalDate)

            TNLog.verbose("Inspecting StoreKit entitlement for \(transaction.productID).")

            // Which configured entitlements does this transaction grant?
            let matched = config.entitlements.filter { $0.productIDs.contains(transaction.productID) }

            if matched.isEmpty {
                TNLog.debug("""
                StoreKit transaction for \(transaction.productID) matched NO configured entitlement. \
                Configured product IDs: \(config.allProductIDs.sorted()).
                """)
                continue
            }

            let renewal = await renewalState(for: transaction)
            let periodType = resolvePeriodType(for: transaction)

            for entitlement in matched {
                let info = TNEntitlementInfo(
                    identifier: entitlement.id,
                    isActive: true,
                    productIdentifier: transaction.productID,
                    willRenew: renewal.willRenew,
                    periodType: periodType,
                    latestPurchaseDate: transaction.purchaseDate,
                    originalPurchaseDate: transaction.originalPurchaseDate,
                    expirationDate: transaction.expirationDate,
                    revocationDate: transaction.revocationDate,
                    store: transaction.tn_store,
                    isSandbox: transaction.tn_isSandbox,
                    ownershipType: transaction.tn_ownershipType,
                    issue: renewal.issue,
                    transaction: transaction
                )

                // A lifetime purchase beats a subscription for the same entitlement:
                // it never expires, so it is the stronger grant to report.
                if let existing = entitlementInfos[entitlement.id] {
                    let existingIsLifetime = existing.expirationDate == nil
                    let newIsLifetime = info.expirationDate == nil
                    let newExpiresLater = (info.expirationDate ?? .distantFuture) > (existing.expirationDate ?? .distantFuture)
                    if newIsLifetime && !existingIsLifetime {
                        entitlementInfos[entitlement.id] = info
                    } else if !existingIsLifetime && newExpiresLater {
                        entitlementInfos[entitlement.id] = info
                    }
                } else {
                    entitlementInfos[entitlement.id] = info
                }
            }
        }

        TNLog.verbose("buildCustomerInfo inspected \(inspected) entitlement(s), skipped \(unverified) unverified; active=\(entitlementInfos.keys.sorted()).")

        return TNCustomerInfo(
            entitlements: TNEntitlementInfos(all: entitlementInfos),
            activeSubscriptions: activeSubscriptions,
            allPurchasedProductIdentifiers: allOwned,
            nonSubscriptionProductIdentifiers: nonSubscriptions,
            latestExpirationDate: latestExpiration,
            originalPurchaseDate: earliestPurchase,
            requestDate: now
        )
    }

    /// Asks Apple whether a subscription intends to renew, and what is wrong if anything is.
    /// (Hỏi Apple xem subscription có ý định gia hạn không, và đang gặp vấn đề gì nếu có.)
    ///
    /// Requires the product to be loaded. When it is not (offline cold start), `willRenew`
    /// defaults to `true`: claiming a healthy subscription is about to lapse is the worse error.
    /// (Cần sản phẩm đã được tải. Khi chưa tải được (khởi động lạnh lúc offline), `willRenew`
    /// mặc định là `true`: báo sai rằng một subscription đang khoẻ sắp hết hạn là lỗi tệ hơn.)
    private func renewalState(for transaction: StoreKit.Transaction) async -> (willRenew: Bool, issue: TNSubscriptionIssue?) {
        guard transaction.productType == .autoRenewable else {
            return (false, nil)  // lifetime / consumable: nothing to renew
        }
        guard let subscription = loadedProducts[transaction.productID]?.subscription else {
            TNLog.verbose("Renewal state for \(transaction.productID) unavailable: product not loaded.")
            return (true, nil)
        }

        let statuses: [Product.SubscriptionInfo.Status]
        do {
            statuses = try await subscription.status
        } catch {
            TNLog.debug("Reading subscription status for \(transaction.productID) failed: \(error.localizedDescription).")
            return (true, nil)
        }

        // `status` covers the whole subscription group, so pick the entry for this product.
        let match = statuses.first {
            (try? $0.transaction.payloadValue)?.productID == transaction.productID
        } ?? statuses.first

        guard let match else { return (true, nil) }

        let willRenew = (try? match.renewalInfo.payloadValue)?.willAutoRenew ?? true

        let issue: TNSubscriptionIssue?
        switch match.state {
        case .subscribed:
            issue = nil
        case .inGracePeriod:
            issue = .gracePeriod
        case .inBillingRetryPeriod:
            issue = .billingRetry
        case .revoked:
            issue = .revoked
        case .expired:
            issue = .expired
        default:
            issue = nil
        }

        return (willRenew, issue)
    }

    /// Distinguishes a free trial from a paid introductory period, which the transaction
    /// alone does not tell you — only the product's offer does.
    /// (Phân biệt dùng thử miễn phí với kỳ giới thiệu có phí — bản thân giao dịch không
    /// cho biết điều này, chỉ ưu đãi trên sản phẩm mới biết.)
    private func resolvePeriodType(for transaction: StoreKit.Transaction) -> TNPeriodType {
        let base = transaction.tn_periodType
        guard base == .intro else { return base }
        if let intro = loadedProducts[transaction.productID]?.subscription?.introductoryOffer,
           intro.paymentMode == .freeTrial {
            return .trial
        }
        return .intro
    }

    /// Explains why nothing unlocked, so a misconfiguration is not mistaken for a
    /// genuine non-subscriber.
    /// (Giải thích vì sao không có gì được mở khoá, để không nhầm lỗi cấu hình
    /// với một người thật sự chưa mua.)
    private func logNoEntitlementDiagnostics(info: TNCustomerInfo) {
        let expected = config.allEntitlementIDs.joined(separator: ", ")

        if info.allPurchasedProductIdentifiers.isEmpty {
            TNLog.info("""
            No active entitlement. This Apple ID owns no unexpired purchase for this app, which is the \
            normal state for a non-subscriber. Expected one of [\(expected)].
            """)
            return
        }

        TNLog.warn("""
        No active entitlement, but this Apple ID DOES own \(info.allPurchasedProductIdentifiers.sorted()). \
        That mismatch is a configuration bug, not a non-subscriber: none of those product IDs appears in \
        any TNEntitlement. Configured product IDs are \(config.allProductIDs.sorted()). Fix the product IDs \
        in your TNEntitlement list so they match the store exactly, including case.
        """)
    }

    // MARK: - Warm Start Cache

    /// Unlocks immediately at launch from the last verified result, so a paying user does
    /// not see a paywall flash before the async check lands.
    /// (Mở khoá ngay khi khởi động dựa trên kết quả đã xác minh lần trước, để người đã trả
    /// tiền không thấy paywall nhoáng lên trước khi kiểm tra bất đồng bộ xong.)
    ///
    /// Only entries whose expiry is still in the future are trusted, so stale data can never
    /// revive a lapsed subscription. A `nil` expiry means a lifetime purchase.
    /// (Chỉ tin các bản ghi còn hạn, nên dữ liệu cũ không bao giờ "hồi sinh" được một
    /// subscription đã hết hạn. `nil` nghĩa là mua vĩnh viễn.)
    ///
    /// On a jailbroken device this cache could be tampered with, but only to bring forward an
    /// unlock by the few milliseconds until Apple's verified answer overwrites it.
    /// (Trên thiết bị đã jailbreak, cache này có thể bị sửa, nhưng chỉ để mở khoá sớm hơn vài
    /// milli-giây cho tới khi câu trả lời đã xác minh của Apple ghi đè lên.)
    private func applyWarmStartCache() {
        guard let raw = UserDefaults.standard.dictionary(forKey: entitlementCacheKey) else {
            entitlementState = .unknown
            TNLog.debug("No warm-start cache; staying .unknown pending the first verified check.")
            return
        }

        let now = Date()
        var stillValid: Set<String> = []

        for (entitlementId, value) in raw {
            // Every entry is a timestamp, including a lifetime grant — see
            // `persistEntitlementCache` for why there is no null sentinel.
            guard let timestamp = value as? Double else { continue }
            if Date(timeIntervalSince1970: timestamp) > now {
                stillValid.insert(entitlementId)
            }
        }

        if stillValid.isEmpty {
            entitlementState = .unknown
            TNLog.debug("Warm-start cache held nothing unexpired; staying .unknown pending a fresh check.")
            return
        }

        activeEntitlements = stillValid
        isPremium = true
        entitlementState = .unlocked
        Self.updateSnapshot(isPremium: true, active: stillValid)
        TNLog.debug("Warm start unlocked \(stillValid.sorted()) from cache, pending verification.")
    }

    private func persistEntitlementCache(from info: TNCustomerInfo) {
        let active = info.entitlements.active
        guard !active.isEmpty else {
            UserDefaults.standard.removeObject(forKey: entitlementCacheKey)
            return
        }
        // A lifetime grant is stored as the distant future, not as a null sentinel.
        // `NSNull` is not a property-list type, so a single one in this dictionary makes
        // UserDefaults reject the WHOLE write — which silently disabled the warm start for
        // exactly the customers who paid the most, and left them staring at a paywall flicker
        // on every cold launch. Keeping every value a `Double` also removes the need for a
        // special case when reading it back.
        var payload: [String: Double] = [:]
        for (id, entitlement) in active {
            payload[id] = (entitlement.expirationDate ?? .distantFuture).timeIntervalSince1970
        }
        UserDefaults.standard.set(payload, forKey: entitlementCacheKey)
    }

    // MARK: - State Application

    private func apply(
        state: EntitlementState,
        isPremium newPremium: Bool,
        active: Set<String>,
        info: TNCustomerInfo?
    ) {
        if let info { customerInfo = info }

        let changed = entitlementState != state
            || isPremium != newPremium
            || activeEntitlements != active

        entitlementState = state
        isPremium = newPremium
        activeEntitlements = active
        Self.updateSnapshot(isPremium: newPremium, active: active)

        if changed {
            TNLog.debug("State → \(state.rawValue), isPremium=\(newPremium), active=\(active.sorted()).")
        }
    }

    // MARK: - Products & Offerings

    /// Fetches every configured product from the App Store and caches it.
    /// (Lấy mọi sản phẩm đã cấu hình từ App Store và cache lại.)
    @discardableResult
    public func loadProducts() async -> [String: Product] {
        let ids = config.allLoadableProductIDs
        guard !ids.isEmpty else {
            TNLog.error("loadProducts found no product IDs to load. Check your TNEntitlement / TNOffering config.")
            return [:]
        }

        do {
            let products = try await Product.products(for: ids)
            loadedProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

            let missing = ids.subtracting(loadedProducts.keys)
            if !missing.isEmpty {
                TNLog.error("""
                The App Store returned no product for \(missing.sorted()). Check, in order: \
                (1) you are on a real device, or the scheme uses a .storekit configuration file — a bare \
                Simulator with no StoreKit config returns nothing; (2) the Paid Applications Agreement is \
                active with Tax and Bank details filled in on App Store Connect; (3) the products are \
                'Approved' or 'Ready to Submit' and have been for 24h+; (4) the product IDs match the \
                store exactly, including case; (5) the Xcode bundle ID matches App Store Connect.
                """)
            }
            TNLog.info("Loaded \(products.count) product(s) from the App Store: \(products.map(\.id).sorted()).")
            return loadedProducts
        } catch {
            TNLog.error("Fetching products FAILED: \(error.localizedDescription)")
            return loadedProducts
        }
    }

    /// A loaded StoreKit product by ID, if it has been fetched.
    /// (Một sản phẩm StoreKit đã tải, theo ID, nếu đã lấy được.)
    public func product(for productID: String) -> Product? {
        loadedProducts[productID]
    }

    /// Replaces the offering list at runtime — the hook for A/B testing or a seasonal
    /// paywall driven by your own remote config.
    /// (Thay danh sách offering lúc runtime — điểm móc để A/B test hoặc đổi paywall theo
    /// mùa, điều khiển bằng remote config của bạn.)
    ///
    /// Products referenced here that were not in the original config are loaded on demand.
    /// (Các sản phẩm được tham chiếu ở đây mà không có trong config ban đầu sẽ được tải khi cần.)
    public func updateOfferings(_ newOfferings: [TNOffering], current: String? = nil) async {
        offerings = newOfferings
        if let current { currentOfferingIdentifier = current }

        let needed = Set(newOfferings.flatMap(\.productIDs)).subtracting(loadedProducts.keys)
        if !needed.isEmpty {
            do {
                let products = try await Product.products(for: needed)
                for product in products { loadedProducts[product.id] = product }
                TNLog.info("Loaded \(products.count) additional product(s) for the updated offerings.")
            } catch {
                TNLog.error("Loading products for the updated offerings FAILED: \(error.localizedDescription)")
            }
        }

        await loadOfferings(offeringIdentifier: currentOfferingIdentifier)
    }

    /// Fire-and-forget variant of `loadOfferings(offeringIdentifier:)`.
    /// (Phiên bản "gọi rồi quên" của `loadOfferings(offeringIdentifier:)`.)
    public func fetchOfferings(offeringIdentifier: String? = nil) {
        Task { await loadOfferings(offeringIdentifier: offeringIdentifier) }
    }

    /// Builds `availablePackages` for one offering and checks intro eligibility.
    /// (Dựng `availablePackages` cho một offering và kiểm tra điều kiện ưu đãi người mới.)
    public func loadOfferings(offeringIdentifier: String? = nil) async {
        guard config.isIAPEnabled else {
            availablePackages = []
            offeringsError = NSLocalizedString("In-app purchases are not enabled.", comment: "")
            return
        }

        isLoadingOfferings = true
        offeringsError = nil
        defer { isLoadingOfferings = false }

        if loadedProducts.isEmpty {
            await loadProducts()
        }

        let requested = offeringIdentifier ?? currentOfferingIdentifier
        let target: TNOffering?
        if let requested, !requested.isEmpty {
            target = offerings.first { $0.identifier == requested } ?? offerings.first
            if offerings.first(where: { $0.identifier == requested }) == nil {
                TNLog.warn("Offering '\(requested)' is not configured; falling back to '\(offerings.first?.identifier ?? "none")'. Available: \(offerings.map(\.identifier)).")
            }
        } else {
            target = offerings.first
        }

        guard let offering = target else {
            availablePackages = []
            offeringsError = NSLocalizedString("No subscription plans are available right now. Please try again later.", comment: "")
            TNLog.error("No offering could be resolved. Declare at least one TNOffering, or configure entitlement product IDs so a 'default' offering can be synthesised.")
            return
        }

        currentOfferingIdentifier = offering.identifier

        var packages: [TNPackage] = []
        var missing: [String] = []
        for productID in offering.productIDs {
            guard let product = loadedProducts[productID] else {
                missing.append(productID)
                continue
            }
            packages.append(TNPackage(offeringIdentifier: offering.identifier, product: product))
        }

        if !offering.preserveOrder {
            packages.sort { $0.packageType.sortOrder < $1.packageType.sortOrder }
        }

        availablePackages = packages

        if packages.isEmpty {
            offeringsError = NSLocalizedString("No subscription plans are available right now. Please try again later.", comment: "")
            TNLog.error("Offering '\(offering.identifier)' produced 0 packages; the App Store returned none of \(offering.productIDs). See the loadProducts diagnostics above for the likely cause.")
        } else {
            if !missing.isEmpty {
                TNLog.warn("Offering '\(offering.identifier)' is missing \(missing) — those products were not returned by the App Store and have been dropped from the paywall.")
            }
            TNLog.info("Loaded offering '\(offering.identifier)' with \(packages.count) package(s): \(packages.map(\.productIdentifier)).")
            await checkIntroEligibility(for: packages)
        }
    }

    /// The metadata of the offering currently displayed.
    /// (Metadata của offering đang hiển thị.)
    public var currentOfferingMetadata: [String: String] {
        offerings.first { $0.identifier == currentOfferingIdentifier }?.metadata ?? [:]
    }

    // MARK: - Introductory Offers

    /// Asks StoreKit which of these products the user may still claim an intro offer on,
    /// and updates `introEligibility`.
    /// (Hỏi StoreKit xem người dùng còn được nhận ưu đãi người mới với sản phẩm nào,
    /// rồi cập nhật `introEligibility`.)
    ///
    /// Apple decides this per **subscription group**, from the Apple ID's history — so one
    /// expired trial on the monthly plan correctly makes the yearly plan ineligible too.
    /// (Apple quyết định theo từng **subscription group**, dựa trên lịch sử của Apple ID — nên
    /// một lần dùng thử đã hết ở gói tháng cũng đúng là làm gói năm không còn đủ điều kiện.)
    @discardableResult
    public func checkIntroEligibility(for packages: [TNPackage]? = nil) async -> [String: TNIntroEligibilityStatus] {
        let targets = packages ?? availablePackages
        guard !targets.isEmpty else { return introEligibility }

        var updated = introEligibility

        for package in targets {
            guard let subscription = package.product.subscription else {
                updated[package.productIdentifier] = .noIntroOfferExists
                continue
            }
            guard subscription.introductoryOffer != nil else {
                updated[package.productIdentifier] = .noIntroOfferExists
                continue
            }
            let eligible = await subscription.isEligibleForIntroOffer
            updated[package.productIdentifier] = eligible ? .eligible : .ineligible
        }

        introEligibility = updated
        TNLog.debug("Intro eligibility: \(updated.mapValues(\.rawValue))")
        return updated
    }

    /// `true` when the user may claim this package's introductory offer or free trial.
    /// (`true` khi người dùng còn được nhận ưu đãi người mới / dùng thử của gói này.)
    public func isEligibleForIntroOffer(package: TNPackage) -> Bool {
        introEligibility[package.productIdentifier] == .eligible
    }

    /// `true` when the user may claim the introductory offer of a product ID.
    /// (`true` khi người dùng còn được nhận ưu đãi người mới của một product ID.)
    public func isEligibleForIntroOffer(productID: String) -> Bool {
        introEligibility[productID] == .eligible
    }

    /// The package's introductory offer, **only** if the user is still eligible for it.
    /// (Ưu đãi người mới của gói, **chỉ khi** người dùng còn đủ điều kiện.)
    ///
    /// Returns `nil` when no intro offer exists or the trial has already been used — so a
    /// "Start Free Trial" button built on this never lies to a returning user.
    /// (Trả về `nil` khi không có ưu đãi hoặc đã dùng hết — nên nút "Dùng thử miễn phí"
    /// dựng trên hàm này không bao giờ nói sai với người dùng quay lại.)
    public func introOffer(for package: TNPackage) -> TNSubscriptionOffer? {
        guard isEligibleForIntroOffer(package: package),
              let offer = package.product.subscription?.introductoryOffer else { return nil }
        return TNSubscriptionOffer(storeKitOffer: offer, product: package.product)
    }

    /// A localised summary of the intro offer if the user is eligible, e.g. `"3 Days Free Trial"`.
    /// (Mô tả đã dịch của ưu đãi người mới nếu đủ điều kiện, ví dụ `"Dùng thử miễn phí 3 Ngày"`.)
    public func introOfferSummary(for package: TNPackage) -> String? {
        introOffer(for: package)?.localizedSummary
    }

    // MARK: - Promotional Offers

    /// Installs the callback that asks your backend to sign a promotional offer.
    /// (Gắn callback để yêu cầu backend của bạn ký một promotional offer.)
    ///
    /// Apple requires promotional offers to be signed with your Subscription Key (`.p8`).
    /// That private key must never ship in the app, so there is no pure on-device path:
    /// without a signer, `purchaseAsync(package:promotionalOffer:)` throws
    /// `.promotionalOfferSignerMissing`.
    /// (Apple yêu cầu promotional offer phải được ký bằng Subscription Key (`.p8`) của bạn.
    /// Private key đó tuyệt đối không được nhúng trong app, nên không có cách nào làm hoàn toàn
    /// trên thiết bị: nếu chưa gắn signer, `purchaseAsync(package:promotionalOffer:)` sẽ
    /// throw `.promotionalOfferSignerMissing`.)
    ///
    /// Introductory offers and offer codes need none of this — Apple applies those itself.
    /// (Ưu đãi người mới và offer code không cần điều này — Apple tự áp dụng.)
    public func configurePromotionalOfferSigner(_ signer: @escaping TNPromotionalOfferSigner) {
        promotionalOfferSigner = signer
        TNLog.info("A promotional offer signer was installed.")
    }

    /// Every promotional offer App Store Connect has configured for this package.
    /// (Mọi promotional offer đã cấu hình trên App Store Connect cho gói này.)
    ///
    /// Eligibility for these is **your** decision (win-back, loyalty, …), not Apple's.
    /// (Điều kiện nhận các ưu đãi này do **bạn** quyết định — giữ chân, tri ân… — không phải Apple.)
    public func promotionalOffers(for package: TNPackage) -> [TNSubscriptionOffer] {
        guard let offers = package.product.subscription?.promotionalOffers else { return [] }
        return offers.compactMap { TNSubscriptionOffer(storeKitOffer: $0, product: package.product) }
    }

    // MARK: - Purchase

    /// Buys a package.
    /// (Mua một gói.)
    ///
    /// Verifies Apple's signature, finishes the transaction, then re-resolves entitlements
    /// before returning — so by the time this returns, `isPremium` is already correct.
    /// (Xác minh chữ ký của Apple, hoàn tất giao dịch, rồi kiểm tra lại quyền lợi trước khi
    /// trả về — nên khi hàm này trả về, `isPremium` đã đúng.)
    @discardableResult
    public func purchaseAsync(package: TNPackage) async throws -> TNCustomerInfo {
        try await performPurchase(package: package, offer: nil)
    }

    /// Buys a package with a promotional offer, asking your signer for the signature first.
    /// (Mua một gói kèm promotional offer, yêu cầu signer của bạn ký trước.)
    @discardableResult
    public func purchaseAsync(package: TNPackage, promotionalOffer offer: TNSubscriptionOffer) async throws -> TNCustomerInfo {
        guard offer.type == .promotional || offer.type == .winBack else {
            TNLog.error("purchaseAsync(package:promotionalOffer:) was passed a \(offer.type.rawValue) offer. Apple applies those automatically — use purchaseAsync(package:) instead.")
            throw TNPurchaseError.offerNotApplicable(offer.type)
        }
        return try await performPurchase(package: package, offer: offer)
    }

    /// Completion-handler variant of `purchaseAsync(package:)`, always called on the main actor.
    /// (Bản dùng completion handler của `purchaseAsync(package:)`, luôn gọi lại trên main actor.)
    public func purchase(package: TNPackage, completion: @escaping (Result<TNCustomerInfo, Error>) -> Void) {
        Task { @MainActor in
            do {
                completion(.success(try await purchaseAsync(package: package)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func performPurchase(package: TNPackage, offer: TNSubscriptionOffer?) async throws -> TNCustomerInfo {
        isPurchasing = true
        defer { isPurchasing = false }

        let productID = package.productIdentifier
        var options: Set<Product.PurchaseOption> = []

        if config.attachAppAccountToken, let token = TNIdentity.appAccountToken {
            options.insert(.appAccountToken(token))
        }

        if let offer {
            guard let offerID = offer.offerIdentifier else {
                throw TNPurchaseError.offerMissingIdentifier
            }
            guard let signer = promotionalOfferSigner else {
                TNLog.error("""
                No promotional offer signer installed. Apple requires promotional offers to be signed with \
                your .p8 Subscription Key, which cannot ship in the app. Call \
                configurePromotionalOfferSigner(_:) and return a signature from your backend.
                """)
                throw TNPurchaseError.promotionalOfferSignerMissing
            }

            let request = TNPromotionalOfferSignatureRequest(
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
                productIdentifier: productID,
                offerIdentifier: offerID,
                applicationUsername: TNIdentity.clientId
            )

            let signature: TNPromotionalOfferSignature
            do {
                signature = try await signer(request)
            } catch {
                TNLog.error("Signing promotional offer '\(offerID)' for \(productID) FAILED: \(error.localizedDescription)")
                throw TNPurchaseError.promotionalOfferSigningFailed(error)
            }

            options.insert(.promotionalOffer(
                offerID: offerID,
                keyID: signature.keyID,
                nonce: signature.nonce,
                signature: signature.signature,
                timestamp: signature.timestamp
            ))
            TNLog.info("Purchasing \(productID) with promotional offer '\(offerID)'…")
        } else {
            TNLog.info("Purchasing \(productID)…")
        }

        let result: Product.PurchaseResult
        do {
            result = try await package.product.purchase(options: options)
        } catch {
            TNLog.error("Purchase of \(productID) FAILED: \(error.localizedDescription)")
            // The transaction may exist locally even though the call threw, so re-resolve
            // rather than leaving the user locked until the next launch.
            await resolveEntitlement()
            throw error
        }

        switch result {
        case .success(let verification):
            let transaction = try verified(verification, context: "purchase of \(productID)")
            await transaction.finish()
            await resolveEntitlement()
            TNLog.info("Purchase of \(productID) succeeded. active=\(activeEntitlements.sorted())")
            return customerInfo ?? TNCustomerInfo()

        case .userCancelled:
            TNLog.info("Purchase of \(productID) cancelled by the user.")
            throw TNPurchaseError.userCancelled

        case .pending:
            // Ask to Buy, or Strong Customer Authentication. The transaction will arrive
            // later through Transaction.updates, possibly on a different launch.
            TNLog.info("Purchase of \(productID) is PENDING external approval (Ask to Buy / SCA).")
            throw TNPurchaseError.purchasePending

        @unknown default:
            TNLog.error("Purchase of \(productID) returned an unknown StoreKit result.")
            throw TNPurchaseError.unknown
        }
    }

    // MARK: - Restore

    /// Restores purchases, calling back on the main actor.
    /// (Phục hồi giao dịch, gọi lại trên main actor.)
    public func restorePurchases(completion: @escaping (Result<Bool, Error>) -> Void) {
        Task { @MainActor in
            do {
                completion(.success(try await restorePurchasesAsync()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Restores purchases and returns whether anything is now active.
    /// (Phục hồi giao dịch và trả về việc hiện có quyền lợi nào hoạt động hay không.)
    ///
    /// `AppStore.sync()` prompts for the App Store password, so call it only from an explicit
    /// "Restore Purchases" button — never automatically at launch. Entitlements already resolve
    /// on their own without it.
    /// (`AppStore.sync()` sẽ hỏi mật khẩu App Store, nên chỉ gọi từ nút "Phục hồi giao dịch"
    /// do người dùng bấm — đừng gọi tự động khi khởi động. Quyền lợi vẫn tự xác định được mà
    /// không cần hàm này.)
    @discardableResult
    public func restorePurchasesAsync() async throws -> Bool {
        TNLog.info("Restoring purchases…")

        let previousState = entitlementState
        let previousPremium = isPremium
        let previousActive = activeEntitlements

        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            TNLog.info("Restore cancelled by the user at the App Store sign-in prompt.")
            apply(state: previousState, isPremium: previousPremium, active: previousActive, info: customerInfo)
            return false
        } catch {
            // Even when sync fails (offline, say), the local entitlements are still worth
            // re-reading: they may already hold what the user is trying to restore.
            TNLog.warn("AppStore.sync() failed (\(error.localizedDescription)); re-reading local entitlements anyway.")
        }

        await loadProducts()
        await resolveEntitlement()

        if isPremium {
            TNLog.info("Restored: \(activeEntitlements.sorted())")
        } else {
            TNLog.info("Restore completed but found no active entitlement for this Apple ID.")
        }
        return isPremium
    }

    // MARK: - Transaction Handling

    /// Handles a transaction that arrived outside a purchase call we made: a renewal, an
    /// Ask-to-Buy approval, an offer code, a refund, or a purchase from another device.
    /// (Xử lý giao dịch đến từ bên ngoài lời gọi mua của chúng ta: gia hạn, phê duyệt
    /// Ask-to-Buy, offer code, hoàn tiền, hoặc giao dịch từ thiết bị khác.)
    private func handle(externalTransaction result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else {
            TNLog.warn("Ignoring an UNVERIFIED transaction from Transaction.updates.")
            return
        }

        TNLog.info("Transaction.updates delivered \(transaction.productID) (\(transaction.productType.rawValue)).")

        await resolveEntitlement()
        await finishIfOurs(transaction)
    }

    /// Finishes transactions left unfinished by a previous run — e.g. the app was killed
    /// between the purchase and the grant.
    /// (Hoàn tất các giao dịch còn dở từ lần chạy trước — ví dụ app bị tắt giữa lúc mua và
    /// lúc cấp quyền.)
    private func finishPendingTransactions() async {
        var count = 0
        for await result in StoreKit.Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            if await finishIfOurs(transaction) { count += 1 }
        }
        if count > 0 {
            TNLog.info("Finished \(count) transaction(s) left over from a previous run.")
        }
    }

    /// Finishes a transaction, but **only** for subscriptions and lifetime unlocks.
    /// (Hoàn tất một giao dịch, nhưng **chỉ** với subscription và mở khoá vĩnh viễn.)
    ///
    /// Consumables are deliberately left alone: finishing one before its reward is credited
    /// loses the user's purchase with no way to recover it. `TNConsumableManager` finishes
    /// those itself, after granting the reward.
    /// (Consumable được cố ý bỏ qua: hoàn tất một consumable trước khi cộng thưởng sẽ làm mất
    /// giao dịch của người dùng mà không có cách nào lấy lại. `TNConsumableManager` tự hoàn tất
    /// chúng, sau khi đã cộng thưởng.)
    @discardableResult
    private func finishIfOurs(_ transaction: StoreKit.Transaction) async -> Bool {
        switch transaction.productType {
        case .autoRenewable, .nonConsumable:
            await transaction.finish()
            TNLog.debug("Finished transaction \(transaction.id) for \(transaction.productID).")
            return true
        default:
            TNLog.debug("Leaving transaction \(transaction.id) for \(transaction.productID) unfinished: \(transaction.productType.rawValue) is not this manager's to finish.")
            return false
        }
    }

    private func verified<T>(_ result: VerificationResult<T>, context: String) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            TNLog.error("""
            On-device JWS verification FAILED for the \(context): \(error.localizedDescription). \
            The transaction is being rejected — treating an unverified transaction as valid is exactly \
            the hole a receipt-validation bypass walks through.
            """)
            throw TNPurchaseError.failedVerification(error)
        }
    }

    // MARK: - Apple Sheets

    /// Presents Apple's native Offer Code redemption sheet.
    /// (Hiển thị bảng nhập Offer Code của Apple.)
    ///
    /// Once a code is redeemed, `Transaction.updates` delivers the transaction and the
    /// entitlement unlocks on its own.
    /// (Sau khi người dùng nhập code, `Transaction.updates` sẽ gửi giao dịch về và quyền lợi
    /// tự mở khoá.)
    public func presentOfferCodeRedemption() {
        guard let scene = Self.activeWindowScene() else {
            TNLog.error("Cannot present the offer code sheet: no active UIWindowScene.")
            return
        }
        Task {
            do {
                try await AppStore.presentOfferCodeRedeemSheet(in: scene)
            } catch {
                TNLog.error("Presenting the offer code sheet FAILED: \(error.localizedDescription)")
            }
        }
    }

    /// Presents Apple's native "Manage Subscriptions" sheet, falling back to the App Store
    /// account page if the sheet cannot open.
    /// (Hiển thị bảng "Quản lý đăng ký" của Apple, nếu không mở được thì chuyển sang trang
    /// tài khoản App Store.)
    public func showManageSubscriptions() {
        Task {
            if let scene = Self.activeWindowScene() {
                do {
                    try await AppStore.showManageSubscriptions(in: scene)
                    return
                } catch {
                    TNLog.warn("showManageSubscriptions failed (\(error.localizedDescription)); falling back to the App Store URL.")
                }
            }
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                await UIApplication.shared.open(url)
            }
        }
    }

    /// Presents Apple's refund request sheet for a product the user owns.
    /// (Hiển thị bảng yêu cầu hoàn tiền của Apple cho một sản phẩm người dùng đang sở hữu.)
    ///
    /// Handling this in-app is what stops a refund request turning into a one-star review.
    /// (Xử lý ngay trong app là cách để một yêu cầu hoàn tiền không biến thành đánh giá 1 sao.)
    @discardableResult
    public func requestRefund(for productID: String) async -> Bool {
        guard let scene = Self.activeWindowScene() else {
            TNLog.error("Cannot present the refund sheet: no active UIWindowScene.")
            return false
        }
        guard let info = customerInfo,
              let entitlement = info.entitlements.all.values.first(where: { $0.productIdentifier == productID }) else {
            TNLog.warn("requestRefund(for:) found no owned transaction for \(productID).")
            return false
        }

        do {
            let status = try await StoreKit.Transaction.beginRefundRequest(for: entitlement.transaction.id, in: scene)
            switch status {
            case .success:
                TNLog.info("Refund request for \(productID) was submitted.")
                return true
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            TNLog.error("Presenting the refund sheet for \(productID) FAILED: \(error.localizedDescription)")
            return false
        }
    }

    static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    // MARK: - Paywall Helpers

    /// Which package to pre-select and badge as the best deal.
    /// (Gói nào nên được chọn trước và gắn nhãn tốt nhất.)
    ///
    /// Prefers the genuinely cheapest per month, so the badge is true rather than just
    /// assuming the annual plan.
    /// (Ưu tiên gói thật sự rẻ nhất tính theo tháng, để nhãn này nói đúng chứ không chỉ
    /// mặc định là gói năm.)
    public var recommendedPackage: TNPackage? {
        let subscriptions = availablePackages.filter { $0.pricePerMonth != nil }
        guard !subscriptions.isEmpty else { return availablePackages.first }
        return subscriptions.min {
            ($0.pricePerMonth ?? .greatestFiniteMagnitude) < ($1.pricePerMonth ?? .greatestFiniteMagnitude)
        }
    }

    /// `true` when this package is the recommended one.
    /// (`true` khi gói này là gói được đề xuất.)
    public func isRecommended(_ package: TNPackage) -> Bool {
        recommendedPackage?.identifier == package.identifier
    }
}

// MARK: - TNPurchaseError

/// The things that can go wrong in a purchase flow, with messages written for a user.
/// (Những lỗi có thể xảy ra trong luồng mua, với thông báo viết cho người dùng đọc.)
public enum TNPurchaseError: LocalizedError {
    /// The user dismissed Apple's payment sheet.
    /// (Người dùng đã tắt bảng thanh toán của Apple.)
    case userCancelled
    /// Waiting on Ask to Buy or Strong Customer Authentication.
    /// (Đang chờ Ask to Buy hoặc Strong Customer Authentication.)
    case purchasePending
    /// Apple's signature did not validate on-device.
    /// (Chữ ký của Apple không xác minh được trên thiết bị.)
    case failedVerification(Error)
    /// A promotional offer was requested with no signer installed.
    /// (Yêu cầu promotional offer nhưng chưa gắn signer.)
    case promotionalOfferSignerMissing
    /// The signer threw.
    /// (Signer báo lỗi.)
    case promotionalOfferSigningFailed(Error)
    /// The offer has no App Store Connect identifier, so it cannot be redeemed explicitly.
    /// (Ưu đãi không có ID trên App Store Connect nên không thể áp dụng tường minh.)
    case offerMissingIdentifier
    /// An introductory offer or offer code was passed where a promotional offer was expected.
    /// (Truyền vào ưu đãi người mới hoặc offer code ở chỗ cần promotional offer.)
    case offerNotApplicable(TNOfferType)
    /// StoreKit returned a result this version does not know about.
    /// (StoreKit trả về một kết quả mà phiên bản này chưa biết.)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .userCancelled:
            return NSLocalizedString("Purchase was cancelled.", comment: "")
        case .purchasePending:
            return NSLocalizedString("Your purchase is waiting for approval. You'll get access as soon as it's approved.", comment: "")
        case .failedVerification:
            return NSLocalizedString("This purchase could not be verified with the App Store. Please contact support.", comment: "")
        case .promotionalOfferSignerMissing:
            return NSLocalizedString("This offer is not available right now.", comment: "")
        case .promotionalOfferSigningFailed:
            return NSLocalizedString("This offer could not be applied. Please try again later.", comment: "")
        case .offerMissingIdentifier:
            return NSLocalizedString("This offer is not available right now.", comment: "")
        case .offerNotApplicable:
            return NSLocalizedString("This offer is applied automatically and does not need to be claimed.", comment: "")
        case .unknown:
            return NSLocalizedString("Something went wrong with your purchase. Please try again.", comment: "")
        }
    }
}

// MARK: - TNPackageType Naming

public extension TNPackageType {
    /// A localised plan name, or `nil` for the types that have no sensible fixed name.
    /// (Tên gói đã dịch, hoặc `nil` với các loại không có tên cố định hợp lý.)
    var localizedName: String? {
        switch self {
        case .weekly: return NSLocalizedString("Weekly", comment: "")
        case .monthly: return NSLocalizedString("Monthly", comment: "")
        case .twoMonth: return NSLocalizedString("2 Months", comment: "")
        case .threeMonth: return NSLocalizedString("3 Months", comment: "")
        case .sixMonth: return NSLocalizedString("6 Months", comment: "")
        case .annual: return NSLocalizedString("Yearly", comment: "")
        case .lifetime: return NSLocalizedString("Lifetime", comment: "")
        case .custom, .unknown: return nil
        }
    }
}
