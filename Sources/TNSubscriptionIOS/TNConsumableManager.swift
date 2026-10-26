import Foundation
import StoreKit
import RevenueCat
import Combine

// MARK: - Consumable Product Configuration

/// A consumable product definition with reward amount.
/// (Định nghĩa sản phẩm consumable với số lượng reward.)
///
/// Example:
/// ```swift
/// TNConsumableProduct(id: "com.app.100coins", reward: 100, currency: "coins")
/// TNConsumableProduct(id: "com.app.500coins", reward: 500, currency: "coins")
/// TNConsumableProduct(id: "com.app.vip_badge", reward: 1, currency: "badges")
/// ```
public struct TNConsumableProduct {
    /// StoreKit Product ID (e.g. "com.yourapp.100coins").
    public let id: String
    
    /// Amount to add after purchase (e.g. 100 coins).
    /// (Số lượng cộng sau khi mua, ví dụ 100 coins.)
    public let reward: Int
    
    /// Currency type name (e.g. "coins", "gems", "credits").
    /// (Tên loại tiền, ví dụ "coins", "gems", "credits".)
    public let currency: String
    
    public init(id: String, reward: Int, currency: String) {
        self.id = id
        self.reward = reward
        self.currency = currency
    }
}

// MARK: - TNConsumableManager

/// Manages consumable in-app purchases and balance tracking.
/// (Quản lý mua consumable và theo dõi số dư.)
///
/// Usage:
/// ```swift
/// // 1. Configure with consumable products
/// TNConsumableManager.configure(products: [
///     TNConsumableProduct(id: "com.app.100coins", reward: 100, currency: "coins"),
///     TNConsumableProduct(id: "com.app.500coins", reward: 500, currency: "coins"),
/// ])
///
/// // 2. Load StoreKit products
/// manager.loadProducts()
///
/// // 3. Purchase
/// manager.purchase(productId: "com.app.100coins") { result in ... }
///
/// // 4. Check balance
/// let coins = TNConsumableManager.shared.balance(for: "coins")
///
/// // 5. Deduct balance
/// TNConsumableManager.shared.deductBalance(10, for: "coins")
/// ```
public final class TNConsumableManager: ObservableObject {
    
    // MARK: - Singleton
    
    /// The shared instance. Only available after `configure(...)` is called.
    /// (Instance duy nhất. Chỉ dùng được sau khi gọi `configure(...)`.)
    public private(set) static var shared: TNConsumableManager!
    
    // MARK: - Published State
    
    /// Available StoreKit products loaded from App Store.
    /// (Danh sách sản phẩm StoreKit đã load từ App Store.)
    @Published public var storeProducts: [Product] = []
    
    /// Whether products are currently loading.
    /// (Đang load sản phẩm hay không.)
    @Published public var isLoadingProducts = false
    
    /// Whether a purchase is currently in progress.
    /// (Đang xử lý mua hay không.)
    @Published public var isPurchasing = false
    
    /// Current balances for all currencies. Key = currency name, Value = amount.
    /// (Số dư hiện tại cho tất cả loại tiền. Key = tên tiền, Value = số lượng.)
    @Published public var balances: [String: Int] = [:]
    
    /// Error message if product loading fails.
    @Published public var loadError: String?
    
    // MARK: - Internal
    
    private let products: [TNConsumableProduct]
    private var updatesTask: Task<Void, Never>?
    private static let balanceKeyPrefix = "tn_consumable_balance_"
    
    // MARK: - Configure
    
    /// Configures the consumable manager. Call once at app launch after `TNSubscriptionIOS.configure(...)`.
    /// (Cấu hình consumable manager. Gọi 1 lần khi app khởi động sau `TNSubscriptionIOS.configure(...)`.)
    ///
    /// ```swift
    /// TNConsumableManager.configure(products: [
    ///     TNConsumableProduct(id: "com.app.100coins", reward: 100, currency: "coins"),
    ///     TNConsumableProduct(id: "com.app.500coins", reward: 500, currency: "coins"),
    ///     TNConsumableProduct(id: "com.app.vip_badge", reward: 1, currency: "badges"),
    /// ])
    /// ```
    public static func configure(products: [TNConsumableProduct]) {
        let instance = TNConsumableManager(products: products)
        shared = instance
    }
    
    private init(products: [TNConsumableProduct]) {
        self.products = products
        
        // Load saved balances from Keychain (with fallback/migration from UserDefaults)
        // (Load số dư đã lưu từ Keychain, fallback/migrate từ UserDefaults)
        let currencies = Set(products.map(\.currency))
        for currency in currencies {
            let key = Self.balanceKeyPrefix + currency
            if let keychainStr = TNSubscriptionIOS.loadFromKeychain(account: key), let keychainVal = Int(keychainStr) {
                balances[currency] = max(0, keychainVal)
            } else {
                let saved = UserDefaults.standard.integer(forKey: key)
                let clamped = max(0, saved)
                balances[currency] = clamped
                if clamped > 0 {
                    TNSubscriptionIOS.saveToKeychain(account: key, value: "\(clamped)")
                }
            }
        }
        
        // 1. Recover unfinished transactions from previous sessions
        //    (Khôi phục giao dịch chưa hoàn thành từ phiên trước —
        //     xử lý trường hợp mạng chậm/app crash giữa chừng khi mua)
        Task {
            await recoverUnfinishedTransactions()
        }
        
        // 2. Listen for external StoreKit 2 transactions (e.g. pending purchases completing)
        //    (Lắng nghe giao dịch StoreKit 2 realtime, ví dụ giao dịch pending hoàn thành)
        updatesTask = Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await processTransaction(transaction)
            }
        }
    }
    
    deinit {
        updatesTask?.cancel()
    }
    
    // MARK: - Transaction Recovery
    
    /// Legacy key prefix for tracking which transactions have been credited.
    /// (Prefix key để theo dõi giao dịch nào đã được cộng tiền.)
    private static let processedTxKeyPrefix = "tn_consumable_tx_"
    
    /// Bounded ring-buffer key for tracking recent processed transaction IDs.
    private static let processedTxListKey = "tn_consumable_processed_tx_ids"
    private static let maxProcessedTxHistory = 200
    
    private func isTransactionProcessed(_ transactionId: UInt64) -> Bool {
        let txString = "\(transactionId)"
        let list = UserDefaults.standard.stringArray(forKey: Self.processedTxListKey) ?? []
        if list.contains(txString) {
            return true
        }
        // Check legacy per-transaction key and migrate if found
        let legacyKey = Self.processedTxKeyPrefix + txString
        if UserDefaults.standard.bool(forKey: legacyKey) {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            markTransactionProcessed(transactionId)
            return true
        }
        return false
    }
    
    private func markTransactionProcessed(_ transactionId: UInt64) {
        let txString = "\(transactionId)"
        var list = UserDefaults.standard.stringArray(forKey: Self.processedTxListKey) ?? []
        if !list.contains(txString) {
            list.append(txString)
            if list.count > Self.maxProcessedTxHistory {
                list.removeFirst(list.count - Self.maxProcessedTxHistory)
            }
            UserDefaults.standard.set(list, forKey: Self.processedTxListKey)
        }
    }
    
    /// Recovers any unfinished consumable transactions from previous sessions.
    /// Handles: network drops, app crash during purchase, pending approvals completing.
    /// (Khôi phục giao dịch consumable chưa hoàn thành từ phiên trước.
    ///  Xử lý: mất mạng, app crash khi mua, giao dịch pending được duyệt.)
    private func recoverUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            await processTransaction(transaction)
        }
        
        #if DEBUG
        print("[TNConsumable] Unfinished transaction recovery complete. (Khôi phục giao dịch chưa hoàn thành xong.)")
        #endif
    }
    
    /// Processes a single transaction: credits balance (with dedup) and finishes it.
    /// (Xử lý 1 giao dịch: cộng số dư (chống trùng) và kết thúc giao dịch.)
    private func processTransaction(_ transaction: StoreKit.Transaction) async {
        // Only process consumables that we configured
        // (Chỉ xử lý consumable đã config)
        guard let product = self.products.first(where: { $0.id == transaction.productID }) else {
            return
        }
        
        // Dedup: skip if this transaction was already credited
        // (Chống trùng: bỏ qua nếu giao dịch này đã được cộng tiền rồi)
        if isTransactionProcessed(transaction.id) {
            // Already processed, just finish
            // (Đã xử lý rồi, chỉ finish)
            await transaction.finish()
            return
        }
        
        // Credit balance (Cộng số dư)
        await MainActor.run {
            self.addBalance(product.reward, for: product.currency)
        }
        
        // Mark as processed (Đánh dấu đã xử lý)
        markTransactionProcessed(transaction.id)
        
        // Finish transaction (Kết thúc giao dịch)
        await transaction.finish()
        
        #if DEBUG
        print("[TNConsumable] Recovered transaction \(transaction.id): +\(product.reward) \(product.currency)")
        #endif
    }
    
    // MARK: - Load Products
    
    /// Loads StoreKit products from App Store.
    /// (Load sản phẩm StoreKit từ App Store.)
    public func loadProducts() {
        Task {
            await loadProductsAsync()
        }
    }
    
    /// Loads StoreKit products from App Store asynchronously.
    @MainActor
    public func loadProductsAsync() async {
        isLoadingProducts = true
        loadError = nil
        defer { isLoadingProducts = false }
        
        do {
            let productIDs = Set(products.map(\.id))
            let storeProducts = try await Product.products(for: productIDs)
            self.storeProducts = storeProducts.sorted { a, b in
                a.price < b.price
            }
            if self.storeProducts.isEmpty {
                loadError = NSLocalizedString("No products available.", comment: "")
            }
        } catch {
            loadError = error.localizedDescription
            storeProducts = []
        }
    }
    
    // MARK: - Purchase
    
    /// Purchases a consumable product by product ID using Swift Concurrency (`async/await`).
    @MainActor
    @discardableResult
    public func purchaseAsync(productId: String) async throws -> Int {
        guard let config = products.first(where: { $0.id == productId }) else {
            throw ConsumableError.productNotConfigured(productId)
        }
        
        guard let storeProduct = storeProducts.first(where: { $0.id == productId }) else {
            throw ConsumableError.productNotLoaded(productId)
        }
        
        isPurchasing = true
        defer { isPurchasing = false }
        
        let result = try await storeProduct.purchase()
        
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw ConsumableError.verificationFailed
            }
            await processTransaction(transaction)
            return config.reward
            
        case .userCancelled:
            throw ConsumableError.userCancelled
            
        case .pending:
            throw ConsumableError.purchasePending
            
        @unknown default:
            throw ConsumableError.unknown
        }
    }
    
    /// Purchases a consumable product by `Product` (StoreKit) using Swift Concurrency (`async/await`).
    @MainActor
    @discardableResult
    public func purchaseAsync(product: Product) async throws -> Int {
        try await purchaseAsync(productId: product.id)
    }
    
    /// Purchases a consumable product by product ID (completion callback is guaranteed to execute on `@MainActor`).
    /// (Mua sản phẩm consumable theo product ID.)
    ///
    /// ```swift
    /// TNConsumableManager.shared.purchase(productId: "com.app.100coins") { result in
    ///     switch result {
    ///     case .success(let reward):
    ///         print("Added \(reward) coins!")
    ///     case .failure(let error):
    ///         print("Purchase failed: \(error)")
    ///     }
    /// }
    /// ```
    public func purchase(productId: String, completion: @escaping (Result<Int, Error>) -> Void) {
        Task { @MainActor in
            do {
                let reward = try await purchaseAsync(productId: productId)
                completion(.success(reward))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    /// Purchases a consumable product by `Product` (StoreKit).
    /// (Mua sản phẩm consumable bằng `Product` StoreKit.)
    public func purchase(product: Product, completion: @escaping (Result<Int, Error>) -> Void) {
        purchase(productId: product.id, completion: completion)
    }
    
    // MARK: - Balance Management
    
    /// Returns the current balance for a currency.
    /// (Trả về số dư hiện tại cho loại tiền.)
    ///
    /// ```swift
    /// let coins = TNConsumableManager.shared.balance(for: "coins") // 350
    /// ```
    public func balance(for currency: String) -> Int {
        balances[currency] ?? 0
    }
    
    /// Adds a positive amount to a currency balance. Automatically persists to Keychain and UserDefaults.
    /// (Cộng số lượng dương vào số dư. Tự động lưu vào Keychain và UserDefaults.)
    ///
    /// ```swift
    /// TNConsumableManager.shared.addBalance(100, for: "coins")
    /// ```
    @MainActor
    public func addBalance(_ amount: Int, for currency: String) {
        guard amount > 0 else { return }
        let current = balances[currency] ?? 0
        let (newBalance, overflow) = current.addingReportingOverflow(amount)
        let safeBalance = overflow ? Int.max : newBalance
        balances[currency] = safeBalance
        persistBalance(safeBalance, for: currency)
        
        #if DEBUG
        print("[TNConsumable] +\(amount) \(currency) → balance: \(safeBalance)")
        #endif
    }
    
    /// Deducts a positive amount from a currency balance. Returns `false` if amount <= 0 or insufficient balance.
    /// (Trừ số lượng dương từ số dư. Trả về `false` nếu amount <= 0 hoặc không đủ số dư.)
    ///
    /// ```swift
    /// let success = TNConsumableManager.shared.deductBalance(10, for: "coins")
    /// if !success {
    ///     // Not enough coins (Không đủ coins)
    /// }
    /// ```
    @discardableResult
    @MainActor
    public func deductBalance(_ amount: Int, for currency: String) -> Bool {
        guard amount > 0 else { return false }
        let current = balances[currency] ?? 0
        guard current >= amount else { return false }
        
        let newBalance = current - amount
        balances[currency] = newBalance
        persistBalance(newBalance, for: currency)
        
        #if DEBUG
        print("[TNConsumable] -\(amount) \(currency) → balance: \(newBalance)")
        #endif
        
        return true
    }
    
    /// Sets the balance for a currency to a specific non-negative value. Use for server sync.
    /// (Đặt số dư cho loại tiền thành giá trị cụ thể không âm. Dùng khi sync với server.)
    @MainActor
    public func setBalance(_ amount: Int, for currency: String) {
        let clamped = max(0, amount)
        balances[currency] = clamped
        persistBalance(clamped, for: currency)
    }
    
    /// Checks if user has enough balance for a specific amount.
    /// (Kiểm tra user có đủ số dư cho số lượng cụ thể không.)
    ///
    /// ```swift
    /// if TNConsumableManager.shared.canAfford(10, currency: "coins") {
    ///     // Proceed (Tiến hành)
    /// }
    /// ```
    public func canAfford(_ amount: Int, currency: String) -> Bool {
        guard amount >= 0 else { return false }
        return balance(for: currency) >= amount
    }
    
    // MARK: - Helpers
    
    /// Returns the configured `TNConsumableProduct` for a product ID.
    /// (Trả về `TNConsumableProduct` đã config cho product ID.)
    public func consumableProduct(for productId: String) -> TNConsumableProduct? {
        products.first(where: { $0.id == productId })
    }
    
    /// Returns all configured products for a specific currency.
    /// (Trả về tất cả sản phẩm đã config cho loại tiền cụ thể.)
    public func products(for currency: String) -> [TNConsumableProduct] {
        products.filter { $0.currency == currency }
    }
    
    /// Returns the StoreKit `Product` for a configured product ID.
    /// (Trả về StoreKit `Product` cho product ID đã config.)
    public func storeProduct(for productId: String) -> Product? {
        storeProducts.first(where: { $0.id == productId })
    }
    
    // MARK: - Persistence
    
    private func persistBalance(_ amount: Int, for currency: String) {
        let key = Self.balanceKeyPrefix + currency
        UserDefaults.standard.set(amount, forKey: key)
        TNSubscriptionIOS.saveToKeychain(account: key, value: "\(amount)")
    }
    
    // MARK: - Errors
    
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
                return "Product '\(id)' is not configured."   // (Sản phẩm '\(id)' chưa được config.)"
            case .productNotLoaded(let id):
                return "Product '\(id)' not loaded from App Store. Call loadProducts() first."  // (Sản phẩm '\(id)' chưa load. Gọi loadProducts() trước.)
            case .verificationFailed:
                return "Transaction verification failed."   // (Xác minh giao dịch thất bại.)
            case .userCancelled:
                return "Purchase was cancelled."   // (Giao dịch đã bị hủy.)
            case .purchasePending:
                return "Purchase is pending approval."   // (Giao dịch đang chờ phê duyệt.)
            case .unknown:
                return "An unknown error occurred."  // (Đã xảy ra lỗi không xác định.)
            }
        }
    }
}
