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
        
        // Load saved balances from UserDefaults
        // (Load số dư đã lưu từ UserDefaults)
        let currencies = Set(products.map(\.currency))
        for currency in currencies {
            let saved = UserDefaults.standard.integer(forKey: Self.balanceKeyPrefix + currency)
            balances[currency] = saved
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
    
    /// Key prefix for tracking which transactions have been credited.
    /// (Prefix key để theo dõi giao dịch nào đã được cộng tiền.)
    private static let processedTxKeyPrefix = "tn_consumable_tx_"
    
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
        let txKey = Self.processedTxKeyPrefix + "\(transaction.id)"
        if UserDefaults.standard.bool(forKey: txKey) {
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
        UserDefaults.standard.set(true, forKey: txKey)
        
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
    
    @MainActor
    private func loadProductsAsync() async {
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
    
    /// Purchases a consumable product by product ID.
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
        guard let config = products.first(where: { $0.id == productId }) else {
            completion(.failure(ConsumableError.productNotConfigured(productId)))
            return
        }
        
        guard let storeProduct = storeProducts.first(where: { $0.id == productId }) else {
            completion(.failure(ConsumableError.productNotLoaded(productId)))
            return
        }
        
        Task {
            await MainActor.run { isPurchasing = true }
            defer { Task { @MainActor in self.isPurchasing = false } }
            
            do {
                let result = try await storeProduct.purchase()
                
                switch result {
                case .success(let verification):
                    guard case .verified(let transaction) = verification else {
                        completion(.failure(ConsumableError.verificationFailed))
                        return
                    }
                    
                    // Credit balance + mark as processed + finish transaction
                    // (Cộng số dư + đánh dấu đã xử lý + kết thúc giao dịch)
                    // Uses processTransaction for dedup safety — if app crashes here,
                    // recoverUnfinishedTransactions() will handle it on next launch.
                    // (Dùng processTransaction để chống trùng — nếu app crash ở đây,
                    //  recoverUnfinishedTransactions() sẽ xử lý khi mở lại.)
                    await processTransaction(transaction)
                    
                    completion(.success(config.reward))
                    
                case .userCancelled:
                    completion(.failure(ConsumableError.userCancelled))
                    
                case .pending:
                    completion(.failure(ConsumableError.purchasePending))
                    
                @unknown default:
                    completion(.failure(ConsumableError.unknown))
                }
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
    
    /// Adds amount to a currency balance. Automatically persists to UserDefaults.
    /// (Cộng số lượng vào số dư. Tự động lưu vào UserDefaults.)
    ///
    /// ```swift
    /// TNConsumableManager.shared.addBalance(100, for: "coins")
    /// ```
    @MainActor
    public func addBalance(_ amount: Int, for currency: String) {
        let current = balances[currency] ?? 0
        let newBalance = current + amount
        balances[currency] = newBalance
        persistBalance(newBalance, for: currency)
        
        #if DEBUG
        print("[TNConsumable] +\(amount) \(currency) → balance: \(newBalance)")
        #endif
    }
    
    /// Deducts amount from a currency balance. Returns `false` if insufficient balance.
    /// (Trừ số lượng từ số dư. Trả về `false` nếu không đủ số dư.)
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
    
    /// Sets the balance for a currency to a specific value. Use for server sync.
    /// (Đặt số dư cho loại tiền thành giá trị cụ thể. Dùng khi sync với server.)
    @MainActor
    public func setBalance(_ amount: Int, for currency: String) {
        balances[currency] = amount
        persistBalance(amount, for: currency)
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
        balance(for: currency) >= amount
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
        UserDefaults.standard.set(amount, forKey: Self.balanceKeyPrefix + currency)
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
