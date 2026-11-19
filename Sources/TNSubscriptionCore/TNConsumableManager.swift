import Foundation
import StoreKit
import Combine

// `TNConsumableProduct` lives in TNSubscriptionShared. (`TNConsumableProduct` nằm trong TNSubscriptionShared.)

// MARK: - Storage Keys

// These live at file scope rather than as static members: `TNConsumableManager` is
// `@MainActor`, which would make its statics main-actor isolated and therefore unreadable
// from the nonisolated dedup helpers.
// (Các key này đặt ở phạm vi file thay vì làm static member: `TNConsumableManager` là
// `@MainActor`, nên static của nó sẽ bị cô lập trên main actor và các hàm chống trùng
// nonisolated không đọc được.)
private let tnBalanceKeyPrefix = "tn_core_consumable_balance_"
private let tnProcessedTxListKey = "tn_core_consumable_processed_tx_ids"
private let tnMaxProcessedTxHistory = 200

// MARK: - TNConsumableManager

/// Manages consumable in-app purchases and the balances they credit, on StoreKit 2 alone.
/// (Quản lý mua consumable và số dư tương ứng, chỉ dùng StoreKit 2.)
///
/// ### Where the balance lives (Số dư được lưu ở đâu)
/// On the device: the Keychain, mirrored to UserDefaults. There is no vendor backend keeping
/// a server-authoritative balance, which has two consequences worth being explicit about:
/// (Trên thiết bị: Keychain, có bản sao ở UserDefaults. Không có backend nào giữ số dư
/// "chuẩn" phía server, điều này dẫn tới hai hệ quả cần nói rõ:)
///
/// - The balance does **not** follow the user to a new device, and is lost if they delete the
///   app and the Keychain item with it. Purchases themselves are never lost — but a consumable
///   that was already credited cannot be re-credited by Apple, so plan for this.
///   (Số dư **không** theo người dùng sang máy mới, và sẽ mất nếu họ xoá app cùng Keychain item.
///   Bản thân giao dịch thì không bao giờ mất — nhưng một consumable đã được cộng thì Apple
///   không cộng lại, nên hãy tính trước việc này.)
/// - A determined user on a jailbroken device can edit it. For anything that must be
///   tamper-proof — a tradeable currency, anything that touches other players — keep the
///   authoritative balance on your own server and use `configureSpendHandler(_:)`.
///   (Người dùng trên máy jailbreak có thể sửa số dư. Với bất cứ thứ gì cần chống gian lận —
///   tiền có thể giao dịch, thứ ảnh hưởng tới người chơi khác — hãy giữ số dư chuẩn trên
///   server của bạn và dùng `configureSpendHandler(_:)`.)
///
/// ```swift
/// // 1. Configure (Cấu hình)
/// TNConsumableManager.configure(products: [
///     TNConsumableProduct(id: "com.app.100coins", reward: 100, currency: "coins"),
///     TNConsumableProduct(id: "com.app.500coins", reward: 500, currency: "coins"),
/// ])
///
/// // 2. Load products (Tải sản phẩm)
/// TNConsumableManager.shared.loadProducts()
///
/// // 3. Purchase (Mua)
/// let reward = try await TNConsumableManager.shared.purchaseAsync(productId: "com.app.100coins")
///
/// // 4. Read and spend (Đọc và tiêu)
/// let coins = TNConsumableManager.shared.balance(for: "coins")
/// TNConsumableManager.shared.deductBalance(10, for: "coins")
/// ```
@MainActor
public final class TNConsumableManager: ObservableObject {

    // MARK: - Singleton

    /// The shared instance. Only available after `configure(products:)` is called.
    /// (Instance dùng chung. Chỉ có sau khi gọi `configure(products:)`.)
    public private(set) static var shared: TNConsumableManager!

    /// `true` once `configure(products:)` has run.
    /// (`true` sau khi `configure(products:)` đã chạy.)
    public static var isConfigured: Bool { shared != nil }

    // MARK: - Published State

    /// StoreKit products loaded from the App Store, cheapest first.
    /// (Sản phẩm StoreKit đã tải từ App Store, rẻ nhất trước.)
    @Published public private(set) var storeProducts: [Product] = []

    /// `true` while products are loading.
    /// (`true` trong lúc đang tải sản phẩm.)
    @Published public private(set) var isLoadingProducts = false

    /// `true` while a purchase is in flight.
    /// (`true` trong lúc một giao dịch đang diễn ra.)
    @Published public private(set) var isPurchasing = false

    /// Current balances, keyed by currency name.
    /// (Số dư hiện tại, theo tên loại tiền.)
    @Published public private(set) var balances: [String: Int] = [:]

    /// Why the last product load failed, or `nil` on success.
    /// (Lý do lần tải sản phẩm gần nhất thất bại, hoặc `nil` nếu thành công.)
    @Published public private(set) var loadError: String?

    // MARK: - Internal

    private let products: [TNConsumableProduct]
    private var updatesTask: Task<Void, Never>?
    private var spendHandler: SpendHandler?


    // MARK: - Configure

    /// Configures the consumable manager. Call once at launch.
    /// (Cấu hình consumable manager. Gọi một lần khi khởi động.)
    public static func configure(products: [TNConsumableProduct]) {
        guard shared == nil else {
            TNLog.warn("[Consumable] configure(products:) was called more than once; the later call was ignored.")
            return
        }

        if products.isEmpty {
            TNLog.warn("[Consumable] configure(products:) was passed an empty list; nothing can be purchased.")
        }
        for product in products where product.reward <= 0 {
            TNLog.error("[Consumable] '\(product.id)' has a reward of \(product.reward); buying it would credit nothing.")
        }
        let duplicates = Dictionary(grouping: products, by: \.id).filter { $1.count > 1 }.keys
        if !duplicates.isEmpty {
            TNLog.error("[Consumable] Duplicate product IDs \(duplicates.sorted()); only the first of each is reachable.")
        }

        shared = TNConsumableManager(products: products)
        TNLog.info("[Consumable] Configured with \(products.count) product(s): \(products.map(\.id)).")
    }

    /// Tears down the configured instance, its balances and its dedup history.
    /// (Phá bỏ instance đã cấu hình, số dư và lịch sử chống trùng của nó.)
    ///
    /// **Test-only**, for the same reason as `TNSubscriptionCore.resetForTesting()`.
    /// Balances persist in the Keychain, so without this a crediting test would see the
    /// previous test's coins and the dedup list would suppress a legitimate credit.
    /// (**Chỉ dùng cho test**, vì cùng lý do như `TNSubscriptionCore.resetForTesting()`.
    /// Số dư lưu trong Keychain, nên nếu không có hàm này, một test cộng thưởng sẽ thấy số coin
    /// của test trước và danh sách chống trùng sẽ chặn một lần cộng hợp lệ.)
    internal static func resetForTesting(currencies: [String] = []) {
        resetInstanceForTesting()
        UserDefaults.standard.removeObject(forKey: tnProcessedTxListKey)
        for currency in currencies {
            let key = tnBalanceKeyPrefix + currency
            UserDefaults.standard.removeObject(forKey: key)
            TNIdentity.saveToKeychain(account: key, value: "0")
        }
    }

    /// Drops the singleton but keeps the persisted balances and dedup history.
    /// (Bỏ singleton nhưng giữ lại số dư đã lưu và lịch sử chống trùng.)
    ///
    /// **Test-only.** This is what an app relaunch actually looks like, so it is the only way
    /// to test that a balance survives one and that recovery does not re-credit.
    /// (**Chỉ dùng cho test.** Đây đúng là những gì xảy ra khi mở lại app, nên nó là cách duy
    /// nhất để kiểm tra số dư còn nguyên sau khi mở lại và recovery không cộng thưởng lần hai.)
    internal static func resetInstanceForTesting() {
        shared?.updatesTask?.cancel()
        shared?.updatesTask = nil
        shared = nil
    }

    private init(products: [TNConsumableProduct]) {
        self.products = products

        // Restore balances: the Keychain is the source of truth, with a one-time
        // migration from a UserDefaults-only earlier build.
        for currency in Set(products.map(\.currency)) {
            let key = tnBalanceKeyPrefix + currency
            if let stored = TNIdentity.loadFromKeychain(account: key), let value = Int(stored) {
                balances[currency] = max(0, value)
            } else {
                let legacy = max(0, UserDefaults.standard.integer(forKey: key))
                balances[currency] = legacy
                if legacy > 0 {
                    TNIdentity.saveToKeychain(account: key, value: "\(legacy)")
                    TNLog.debug("[Consumable] Migrated the '\(currency)' balance into the Keychain.")
                }
            }
        }

        // 1. Credit anything left unfinished by a previous run: a crash or a dropped
        //    connection between the payment and the grant must not cost the user coins.
        Task { [weak self] in
            await self?.recoverUnfinishedTransactions()
        }

        // 2. Watch for transactions arriving on their own — a pending Ask-to-Buy approval,
        //    or a purchase made on another device.
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await self?.process(transaction)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Transaction Recovery

    private nonisolated func isProcessed(_ transactionId: UInt64) -> Bool {
        let list = UserDefaults.standard.stringArray(forKey: tnProcessedTxListKey) ?? []
        return list.contains("\(transactionId)")
    }

    private nonisolated func markProcessed(_ transactionId: UInt64) {
        let key = "\(transactionId)"
        var list = UserDefaults.standard.stringArray(forKey: tnProcessedTxListKey) ?? []
        guard !list.contains(key) else { return }
        list.append(key)
        // A bounded ring buffer: unbounded growth would eventually bloat the plist,
        // and a transaction 200 purchases ago can no longer be unfinished.
        if list.count > tnMaxProcessedTxHistory {
            list.removeFirst(list.count - tnMaxProcessedTxHistory)
        }
        UserDefaults.standard.set(list, forKey: tnProcessedTxListKey)
    }

    private func recoverUnfinishedTransactions() async {
        for await result in StoreKit.Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            await process(transaction)
        }
        TNLog.debug("[Consumable] Unfinished transaction recovery complete.")
    }

    /// Credits a transaction exactly once, then finishes it.
    /// (Cộng tiền cho một giao dịch đúng một lần, rồi hoàn tất giao dịch.)
    ///
    /// The order matters: credit first, mark second, finish last. Finishing before the
    /// credit is persisted would lose the purchase if the app died in between.
    /// (Thứ tự rất quan trọng: cộng tiền trước, ghi dấu sau, hoàn tất cuối cùng. Nếu hoàn tất
    /// trước khi số dư được lưu, giao dịch sẽ mất nếu app tắt giữa hai bước.)
    private func process(_ transaction: StoreKit.Transaction) async {
        guard let product = products.first(where: { $0.id == transaction.productID }) else {
            TNLog.verbose("[Consumable] Ignoring \(transaction.productID): not a configured consumable.")
            return
        }

        if isProcessed(transaction.id) {
            TNLog.debug("[Consumable] Transaction \(transaction.id) for \(transaction.productID) was already credited; finishing it only.")
            await transaction.finish()
            return
        }

        if transaction.revocationDate != nil {
            TNLog.warn("[Consumable] Transaction \(transaction.id) for \(transaction.productID) was refunded; not crediting.")
            markProcessed(transaction.id)
            await transaction.finish()
            return
        }

        addBalance(product.reward, for: product.currency)
        markProcessed(transaction.id)
        await transaction.finish()

        TNLog.info("[Consumable] Credited transaction \(transaction.id): +\(product.reward) \(product.currency) for \(product.id).")
    }

    // MARK: - Load Products

    /// Fire-and-forget variant of `loadProductsAsync()`.
    /// (Phiên bản "gọi rồi quên" của `loadProductsAsync()`.)
    public func loadProducts() {
        Task { await loadProductsAsync() }
    }

    /// Fetches the configured consumables from the App Store.
    /// (Lấy các consumable đã cấu hình từ App Store.)
    public func loadProductsAsync() async {
        isLoadingProducts = true
        loadError = nil
        defer { isLoadingProducts = false }

        let productIDs = Set(products.map(\.id))
        guard !productIDs.isEmpty else {
            loadError = NSLocalizedString("No products available.", comment: "")
            return
        }

        do {
            let fetched = try await Product.products(for: productIDs)
            storeProducts = fetched.sorted { $0.price < $1.price }

            if storeProducts.isEmpty {
                loadError = NSLocalizedString("No products available.", comment: "")
                TNLog.error("""
                [Consumable] The App Store returned 0 products for \(productIDs.sorted()). StoreKit needs either a \
                .storekit configuration file attached to the running scheme, or these product IDs live on App Store \
                Connect and the app runs on a real device signed in to a Sandbox Apple ID. A bare Simulator with no \
                StoreKit configuration returns nothing.
                """)
            } else {
                let missing = productIDs.subtracting(storeProducts.map(\.id))
                if !missing.isEmpty {
                    TNLog.warn("[Consumable] The App Store did not return \(missing.sorted()); those packs cannot be purchased.")
                }
                TNLog.info("[Consumable] Loaded \(storeProducts.count) product(s): \(storeProducts.map(\.id)).")
            }
        } catch {
            loadError = error.localizedDescription
            storeProducts = []
            TNLog.error("[Consumable] Loading products FAILED: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    /// Buys a consumable by product ID and returns the reward credited.
    /// (Mua một consumable theo product ID và trả về số lượng đã cộng.)
    @discardableResult
    public func purchaseAsync(productId: String) async throws -> Int {
        guard let consumable = products.first(where: { $0.id == productId }) else {
            TNLog.error("[Consumable] '\(productId)' was never passed to configure(products:). Configured: \(products.map(\.id)).")
            throw ConsumableError.productNotConfigured(productId)
        }

        guard let storeProduct = storeProducts.first(where: { $0.id == productId }) else {
            TNLog.error("""
            [Consumable] '\(productId)' is configured but the App Store never returned it, so there is nothing to buy. \
            Call loadProducts() first, then check the product exists in the .storekit configuration file attached to \
            the scheme, or on App Store Connect. Loaded so far: \(storeProducts.map(\.id)). \
            Last load error: \(loadError ?? "none").
            """)
            throw ConsumableError.productNotLoaded(productId)
        }

        isPurchasing = true
        defer { isPurchasing = false }

        TNLog.info("[Consumable] Purchasing \(productId)…")

        let result: Product.PurchaseResult
        do {
            result = try await storeProduct.purchase()
        } catch {
            TNLog.error("[Consumable] Purchase of \(productId) FAILED: \(error.localizedDescription)")
            throw error
        }

        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                TNLog.error("[Consumable] Purchase of \(productId) returned an UNVERIFIED transaction; no balance credited.")
                throw ConsumableError.verificationFailed
            }
            await process(transaction)
            return consumable.reward

        case .userCancelled:
            TNLog.info("[Consumable] Purchase of \(productId) cancelled by the user.")
            throw ConsumableError.userCancelled

        case .pending:
            TNLog.info("[Consumable] Purchase of \(productId) is pending approval (Ask to Buy); the balance is credited once approved.")
            throw ConsumableError.purchasePending

        @unknown default:
            TNLog.error("[Consumable] Purchase of \(productId) returned an unknown StoreKit result.")
            throw ConsumableError.unknown
        }
    }

    /// Buys a consumable by StoreKit `Product`.
    /// (Mua một consumable bằng `Product` của StoreKit.)
    @discardableResult
    public func purchaseAsync(product: Product) async throws -> Int {
        try await purchaseAsync(productId: product.id)
    }

    /// Completion-handler variant, always called on the main actor.
    /// (Bản dùng completion handler, luôn gọi lại trên main actor.)
    public func purchase(productId: String, completion: @escaping (Result<Int, Error>) -> Void) {
        Task { @MainActor in
            do {
                completion(.success(try await purchaseAsync(productId: productId)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Completion-handler variant taking a StoreKit `Product`.
    /// (Bản dùng completion handler, nhận `Product` của StoreKit.)
    public func purchase(product: Product, completion: @escaping (Result<Int, Error>) -> Void) {
        purchase(productId: product.id, completion: completion)
    }

    // MARK: - Balances

    /// The current balance for a currency.
    /// (Số dư hiện tại của một loại tiền.)
    public func balance(for currency: String) -> Int {
        balances[currency] ?? 0
    }

    /// `true` when the balance covers `amount`.
    /// (`true` khi số dư đủ cho `amount`.)
    public func canAfford(_ amount: Int, currency: String) -> Bool {
        guard amount >= 0 else { return false }
        return balance(for: currency) >= amount
    }

    /// Credits a positive amount and persists it.
    /// (Cộng một số lượng dương và lưu lại.)
    public func addBalance(_ amount: Int, for currency: String) {
        guard amount > 0 else { return }
        let current = balances[currency] ?? 0
        // Saturate instead of trapping: an overflow here would crash the app over a
        // number no real player reaches.
        let (sum, overflow) = current.addingReportingOverflow(amount)
        let newBalance = overflow ? Int.max : sum
        balances[currency] = newBalance
        persist(newBalance, for: currency)
        TNLog.debug("[Consumable] +\(amount) \(currency) → \(newBalance).")
    }

    /// Debits a positive amount. Returns `false` when the amount is invalid or the
    /// balance is insufficient — nothing is deducted in that case.
    /// (Trừ một số lượng dương. Trả về `false` khi số lượng không hợp lệ hoặc không đủ số dư —
    /// khi đó không trừ gì cả.)
    @discardableResult
    public func deductBalance(_ amount: Int, for currency: String) -> Bool {
        guard amount > 0 else { return false }
        let current = balances[currency] ?? 0
        guard current >= amount else { return false }
        let newBalance = current - amount
        balances[currency] = newBalance
        persist(newBalance, for: currency)
        TNLog.debug("[Consumable] -\(amount) \(currency) → \(newBalance).")
        return true
    }

    /// Overwrites a balance — use when syncing from your own server.
    /// (Ghi đè số dư — dùng khi đồng bộ từ server của bạn.)
    public func setBalance(_ amount: Int, for currency: String) {
        let clamped = max(0, amount)
        balances[currency] = clamped
        persist(clamped, for: currency)
        TNLog.debug("[Consumable] '\(currency)' set to \(clamped).")
    }

    private func persist(_ amount: Int, for currency: String) {
        let key = tnBalanceKeyPrefix + currency
        UserDefaults.standard.set(amount, forKey: key)
        TNIdentity.saveToKeychain(account: key, value: "\(amount)")
    }

    // MARK: - Server-Authoritative Spending

    /// Asks your backend to authorise a spend. Return `true` only when the server
    /// committed it.
    /// (Yêu cầu backend của bạn cho phép một lần tiêu. Chỉ trả về `true` khi server đã ghi nhận.)
    public typealias SpendHandler = @MainActor (_ currency: String, _ amount: Int, _ reference: String?) async throws -> Bool

    /// Routes `spendAsync` through your server instead of the local balance.
    /// (Chuyển `spendAsync` qua server của bạn thay vì số dư cục bộ.)
    ///
    /// Install this when the balance must be authoritative — anything tradeable, anything
    /// that affects other users, anything worth cheating for. Without it, `spendAsync`
    /// falls back to the local ledger, which is convenient but device-trusting.
    /// (Hãy gắn handler này khi số dư cần là chuẩn — thứ có thể giao dịch, thứ ảnh hưởng người
    /// khác, thứ đáng để gian lận. Nếu không gắn, `spendAsync` dùng sổ cục bộ: tiện, nhưng tin
    /// vào thiết bị.)
    public func configureSpendHandler(_ handler: @escaping SpendHandler) {
        spendHandler = handler
        TNLog.info("[Consumable] A server-authoritative spend handler was installed.")
    }

    /// Spends from the balance: through your handler when one is installed, otherwise locally.
    /// (Tiêu từ số dư: qua handler của bạn nếu đã gắn, nếu không thì tiêu cục bộ.)
    ///
    /// - Parameter reference: An idempotency key or item ID your server can deduplicate on.
    ///   (Khoá idempotency hoặc ID vật phẩm để server của bạn chống trùng.)
    /// - Returns: `true` when the spend was committed.
    ///   (`true` khi đã trừ thành công.)
    @discardableResult
    public func spendAsync(_ amount: Int, currency: String, reference: String? = nil) async throws -> Bool {
        guard amount > 0 else { return false }

        guard let spendHandler else {
            return deductBalance(amount, for: currency)
        }

        guard canAfford(amount, currency: currency) else {
            TNLog.debug("[Consumable] Local balance says \(currency) cannot cover \(amount); not calling the server.")
            return false
        }

        let committed = try await spendHandler(currency, amount, reference)
        if committed {
            // The server is authoritative, so mirror its decision locally rather than
            // deducting twice.
            _ = deductBalance(amount, for: currency)
            TNLog.info("[Consumable] Server committed a spend of \(amount) \(currency) (ref: \(reference ?? "none")).")
        } else {
            TNLog.warn("[Consumable] The server refused a spend of \(amount) \(currency) (ref: \(reference ?? "none")); the local balance is unchanged.")
        }
        return committed
    }

    // MARK: - Helpers

    /// The configured definition for a product ID.
    /// (Định nghĩa đã cấu hình của một product ID.)
    public func consumableProduct(for productId: String) -> TNConsumableProduct? {
        products.first { $0.id == productId }
    }

    /// Every configured product that credits a given currency.
    /// (Mọi sản phẩm đã cấu hình cộng vào một loại tiền.)
    public func products(for currency: String) -> [TNConsumableProduct] {
        products.filter { $0.currency == currency }
    }

    /// The loaded StoreKit product for a configured product ID.
    /// (Sản phẩm StoreKit đã tải, theo product ID đã cấu hình.)
    public func storeProduct(for productId: String) -> Product? {
        storeProducts.first { $0.id == productId }
    }

    // MARK: - Errors

    /// What can go wrong buying a consumable.
    /// (Các lỗi có thể xảy ra khi mua consumable.)
    public enum ConsumableError: LocalizedError {
        case productNotConfigured(String)
        case productNotLoaded(String)
        case verificationFailed
        case userCancelled
        case purchasePending
        case unknown

        public var errorDescription: String? {
            switch self {
            case .productNotConfigured(let id):
                // (Sản phẩm '\(id)' chưa được cấu hình.)
                return "Product '\(id)' is not configured."
            case .productNotLoaded(let id):
                // (Sản phẩm '\(id)' chưa tải xong. Hãy gọi loadProducts() trước.)
                return "Product '\(id)' was not loaded from the App Store. Call loadProducts() first."
            case .verificationFailed:
                // (Xác minh giao dịch thất bại.)
                return NSLocalizedString("This purchase could not be verified with the App Store. Please contact support.", comment: "")
            case .userCancelled:
                // (Giao dịch đã bị huỷ.)
                return NSLocalizedString("Purchase was cancelled.", comment: "")
            case .purchasePending:
                // (Giao dịch đang chờ phê duyệt.)
                return NSLocalizedString("Your purchase is waiting for approval. You'll get access as soon as it's approved.", comment: "")
            case .unknown:
                // (Đã xảy ra lỗi không xác định.)
                return NSLocalizedString("Something went wrong with your purchase. Please try again.", comment: "")
            }
        }
    }
}
