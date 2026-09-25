import Foundation
import RevenueCat
import Combine

/// Typealias for developers accustomed to the "Virtual Currency" naming.
public typealias TNVirtualCurrencyManager = TNInAppCurrencyManager

// MARK: - TNInAppCurrencyManager

/// Manages RevenueCat In-App Currencies (Virtual Currencies) such as coins, gems, and credits.
/// (Quản lý tiền tệ trong ứng dụng / Virtual Currencies trên RevenueCat như coins, gems, credits.)
///
/// Features:
/// - Cloud-synced balance directly powered by RevenueCat's backend.
/// - Automatically refreshes when packages or subscriptions granting currencies are purchased/renewed.
/// - Client-side balance queries, cache invalidation, and spend/deduction delegates.
///
/// Usage:
/// ```swift
/// // 1. Access the singleton
/// let currencyManager = TNInAppCurrencyManager.shared
///
/// // 2. Fetch or refresh balances from RevenueCat
/// currencyManager.fetchCurrencies()
///
/// // 3. Observe in SwiftUI
/// @ObservedObject var currencies = TNInAppCurrencyManager.shared
/// Text("Coins: \(currencies.balance(for: "coins"))")
///
/// // 4. Check if user can afford
/// if TNInAppCurrencyManager.shared.canAfford(50, currency: "coins") { ... }
/// ```
public final class TNInAppCurrencyManager: ObservableObject {
    
    // MARK: - Singleton
    
    /// The shared singleton instance.
    public static let shared = TNInAppCurrencyManager()
    
    // MARK: - Published State
    
    /// The raw `VirtualCurrencies` container returned by RevenueCat.
    @Published public private(set) var rawCurrencies: VirtualCurrencies?
    
    /// Dictionary of all available virtual currencies keyed by currency code.
    /// (Danh sách virtual currencies theo mã tiền tệ, ví dụ "coins", "gems".)
    @Published public private(set) var currencies: [String: VirtualCurrency] = [:]
    
    /// Current balances keyed by currency code. E.g. `["coins": 500, "gems": 20]`.
    /// (Số dư hiện tại theo mã tiền tệ.)
    @Published public private(set) var balances: [String: Int] = [:]
    
    /// Whether currency balances are currently being fetched from RevenueCat.
    @Published public private(set) var isLoading: Bool = false
    
    /// Error message if loading or spending currency fails.
    @Published public var error: String?
    
    /// Timestamp of when the currency balances were last updated.
    @Published public private(set) var lastUpdated: Date?
    
    // MARK: - Spend Handler Type
    
    /// Closure signature for custom server-side spending / deductions by amount.
    /// - Parameters:
    ///   - code: The currency code (e.g. "coins").
    ///   - amount: Amount of currency to deduct.
    ///   - reference: Optional transaction reference ID.
    /// - Returns: `true` if deduction succeeded on server, `false` otherwise.
    public typealias SpendHandler = (_ code: String, _ amount: Int, _ reference: String?) async throws -> Bool
    
    /// Closure signature for secure item-based purchases where the server determines price and validates rights.
    /// - Parameters:
    ///   - itemId: The unique identifier of the item or action (e.g. "sung_vip", "hint").
    ///   - extraParams: Optional extra metadata dictionary.
    /// - Returns: `true` if server validated and deducted currency, `false` otherwise.
    public typealias ActionSpendHandler = (_ itemId: String, _ extraParams: [String: Any]?) async throws -> Bool
    
    private var customSpendHandler: SpendHandler?
    private var customActionSpendHandler: ActionSpendHandler?
    
    // MARK: - Initialization
    
    private init() {
        // Load cached currencies if available to prevent UI flicker
        if let cached = Purchases.shared.cachedVirtualCurrencies {
            self.rawCurrencies = cached
            self.currencies = cached.all
            var newBalances: [String: Int] = [:]
            for (code, item) in cached.all {
                newBalances[code] = item.balance
            }
            self.balances = newBalances
        }
    }
    
    // MARK: - Public Fetch Methods
    
    /// Fetches virtual currencies from RevenueCat asynchronously.
    ///
    /// - Parameter forceRefresh: If `true`, invalidates the local cache before fetching.
    /// - Returns: The updated `VirtualCurrencies` object.
    @discardableResult
    @MainActor
    public func fetchCurrenciesAsync(forceRefresh: Bool = false) async throws -> VirtualCurrencies {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        if forceRefresh {
            Purchases.shared.invalidateVirtualCurrenciesCache()
        }
        
        do {
            let result = try await Purchases.shared.virtualCurrencies()
            self.apply(currencies: result)
            self.lastUpdated = Date()
            return result
        } catch {
            self.error = error.localizedDescription
            // Fallback to cached data if network failed
            if let cached = Purchases.shared.cachedVirtualCurrencies {
                self.apply(currencies: cached)
            }
            throw error
        }
    }
    
    /// Fetches virtual currencies with completion handler (callback-based / UIKit friendly).
    ///
    /// - Parameters:
    ///   - forceRefresh: If `true`, invalidates the local cache before fetching.
    ///   - completion: Optional callback returning Result with VirtualCurrencies or Error.
    public func fetchCurrencies(forceRefresh: Bool = false, completion: ((Result<VirtualCurrencies, Error>) -> Void)? = nil) {
        Task {
            do {
                let currencies = try await fetchCurrenciesAsync(forceRefresh: forceRefresh)
                await MainActor.run {
                    completion?(.success(currencies))
                }
            } catch {
                await MainActor.run {
                    completion?(.failure(error))
                }
            }
        }
    }
    
    /// Invalidates the local virtual currencies cache.
    /// Next fetch will query RevenueCat's servers directly.
    public func invalidateCache() {
        Purchases.shared.invalidateVirtualCurrenciesCache()
    }
    
    // MARK: - Balance Queries
    
    /// Returns the current balance for a currency code (e.g. "coins"). Returns `0` if not found.
    /// (Lấy số dư hiện tại theo mã tiền. Trả về `0` nếu không tìm thấy.)
    ///
    /// ```swift
    /// let coinCount = TNInAppCurrencyManager.shared.balance(for: "coins")
    /// ```
    public func balance(for code: String) -> Int {
        balances[code] ?? currencies[code]?.balance ?? 0
    }
    
    /// Returns the `VirtualCurrency` object for a currency code, which includes name, balance, and server description.
    /// (Lấy đối tượng `VirtualCurrency` bao gồm tên, số dư, và mô tả từ server.)
    public func currency(for code: String) -> VirtualCurrency? {
        currencies[code]
    }
    
    /// Checks whether the user has at least the required amount of currency.
    /// (Kiểm tra xem người dùng có đủ số dư hay không.)
    ///
    /// ```swift
    /// if TNInAppCurrencyManager.shared.canAfford(100, currency: "gems") {
    ///     // Proceed with unlock
    /// }
    /// ```
    public func canAfford(_ amount: Int, currency code: String) -> Bool {
        balance(for: code) >= amount
    }
    
    // MARK: - Spending & Deductions
    
    /// Configures a custom spend handler to execute currency deductions via your backend or proxy.
    /// (Cấu hình handler để thực hiện trừ tiền qua backend hoặc proxy của bạn.)
    ///
    /// RevenueCat requires spending virtual currencies to be authenticated server-side or via API proxy.
    public func configureSpendHandler(_ handler: @escaping SpendHandler) {
        self.customSpendHandler = handler
    }
    
    /// Deducts currency by delegating to the configured server spend handler, then refreshes the balance.
    /// (Trừ tiền thông qua server spend handler đã cấu hình, sau đó tự động làm mới số dư.)
    ///
    /// - Parameters:
    ///   - code: The currency code (e.g. "coins").
    ///   - amount: The amount to deduct (must be positive).
    ///   - reference: Optional unique transaction reference ID.
    ///   - completion: Callback with Result containing new balance or Error.
    public func spend(
        code: String,
        amount: Int,
        reference: String? = nil,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        guard amount > 0 else {
            completion(.failure(CurrencyError.invalidAmount))
            return
        }
        
        guard canAfford(amount, currency: code) else {
            completion(.failure(CurrencyError.insufficientBalance(current: balance(for: code), required: amount)))
            return
        }
        
        guard let handler = customSpendHandler else {
            completion(.failure(CurrencyError.noSpendHandlerConfigured))
            return
        }
        
        Task {
            do {
                let success = try await handler(code, amount, reference)
                if success {
                    // Invalidate cache and fetch fresh balance from RevenueCat
                    let freshCurrencies = try await self.fetchCurrenciesAsync(forceRefresh: true)
                    let newBalance = freshCurrencies[code]?.balance ?? self.balance(for: code)
                    await MainActor.run {
                        completion(.success(newBalance))
                    }
                } else {
                    await MainActor.run {
                        completion(.failure(CurrencyError.spendFailed("Server rejected currency deduction transaction.")))
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Optimistically deducts balance locally for immediate UI update or offline gameplay.
    /// Note: Does not sync to RevenueCat cloud directly (cloud balance requires server/proxy transaction).
    ///
    /// - Parameters:
    ///   - amount: Amount to deduct.
    ///   - code: Currency code (e.g. "coins").
    /// - Returns: `true` if deduction succeeded locally, `false` if balance was insufficient.
    @discardableResult
    @MainActor
    public func deductLocalBalance(_ amount: Int, for code: String) -> Bool {
        let current = balance(for: code)
        guard current >= amount else { return false }
        let newBalance = current - amount
        balances[code] = newBalance
        return true
    }
    
    /// Helper to spend currency through your backend API or proxy gateway.
    /// Automatically attaches client identity headers (`X-Client-Id`, `X-Device-Id`, etc.).
    ///
    /// - Parameters:
    ///   - proxyEndpoint: URL of the spend endpoint on your server or API proxy.
    ///   - apiKey: Your app API key.
    ///   - code: Currency code to spend.
    ///   - amount: Amount to spend.
    ///   - userId: Optional user ID if logged in.
    ///   - completion: Callback returning new balance or error.
    public func spendViaProxy(
        proxyEndpoint: URL,
        apiKey: String,
        code: String,
        amount: Int,
        userId: String? = nil,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        guard amount > 0 else {
            completion(.failure(CurrencyError.invalidAmount))
            return
        }
        
        guard amount <= 2_000_000_000 else {
            completion(.failure(CurrencyError.amountExceedsLimit(2_000_000_000)))
            return
        }
        
        guard canAfford(amount, currency: code) else {
            completion(.failure(CurrencyError.insufficientBalance(current: balance(for: code), required: amount)))
            return
        }
        
        var request = URLRequest(url: proxyEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        // Idempotency-Key for exactly-once execution (RevenueCat Best Practice)
        request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        
        // Standard Client Identity Headers (X-Client-Id, X-Device-Id, X-User-Id)
        request.setValue(TNSubscriptionIOS.clientId, forHTTPHeaderField: "X-Client-Id")
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            request.setValue(vendorId, forHTTPHeaderField: "X-Device-Id")
        }
        if let uid = userId {
            request.setValue(uid, forHTTPHeaderField: "X-User-Id")
        }
        
        // Payload matching RevenueCat adjustments schema + convenience fields
        let body: [String: Any] = [
            "currency_code": code,
            "amount": amount,
            "adjustments": [code: -abs(amount)],
            "client_id": TNSubscriptionIOS.clientId
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 500
                DispatchQueue.main.async {
                    completion(.failure(CurrencyError.spendFailed("HTTP status \(code)")))
                }
                return
            }
            
            // Server deduction confirmed, refresh from RevenueCat
            self.fetchCurrencies(forceRefresh: true) { result in
                switch result {
                case .success:
                    completion(.success(self.balance(for: code)))
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }.resume()
    }
    
    // MARK: - Secure Item-Based Purchases (RevenueCat Security Best Practice)
    
    /// Configures a custom handler for item-based purchases where backend validates and deducts the price.
    /// (Cấu hình handler mua item an toàn: Backend tự tra bảng giá và trừ tiền, Client không tự gửi giá).
    public func configureActionSpendHandler(_ handler: @escaping ActionSpendHandler) {
        self.customActionSpendHandler = handler
    }
    
    /// Securely purchases an item through the configured action spend handler.
    ///
    /// - Parameters:
    ///   - itemId: The item ID or action (e.g. "sung_vip", "hint").
    ///   - extraParams: Optional metadata to pass to backend.
    ///   - completion: Callback returning updated balances dictionary or Error.
    public func purchaseItem(
        itemId: String,
        extraParams: [String: Any]? = nil,
        completion: @escaping (Result<[String: Int], Error>) -> Void
    ) {
        guard let handler = customActionSpendHandler else {
            completion(.failure(CurrencyError.noSpendHandlerConfigured))
            return
        }
        
        Task {
            do {
                let success = try await handler(itemId, extraParams)
                if success {
                    let fresh = try await self.fetchCurrenciesAsync(forceRefresh: true)
                    var updated: [String: Int] = [:]
                    for (k, v) in fresh.all { updated[k] = v.balance }
                    await MainActor.run { completion(.success(updated)) }
                } else {
                    await MainActor.run {
                        completion(.failure(CurrencyError.spendFailed("Backend rejected item purchase transaction.")))
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Securely purchases an in-app virtual item via your backend API or proxy gateway.
    /// Following RevenueCat security guidelines: the client ONLY sends `itemId` (or action),
    /// and the backend determines the price and executes the deduction.
    ///
    /// - Parameters:
    ///   - proxyEndpoint: URL of the spend/purchase endpoint on your server or API proxy.
    ///   - apiKey: Your app API key.
    ///   - itemId: Unique ID of the virtual item to purchase (e.g. "sung_vip", "hint").
    ///   - extraParams: Optional extra parameters to send in JSON body.
    ///   - userId: Optional user ID if logged in.
    ///   - completion: Callback returning updated balances map `[currencyCode: balance]` or error.
    public func purchaseItemViaProxy(
        proxyEndpoint: URL,
        apiKey: String,
        itemId: String,
        extraParams: [String: Any]? = nil,
        userId: String? = nil,
        completion: @escaping (Result<[String: Int], Error>) -> Void
    ) {
        var request = URLRequest(url: proxyEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        // Idempotency-Key for exactly-once execution (RevenueCat Best Practice)
        request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        
        // Standard Client Identity Headers (X-Client-Id, X-Device-Id, X-User-Id)
        request.setValue(TNSubscriptionIOS.clientId, forHTTPHeaderField: "X-Client-Id")
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            request.setValue(vendorId, forHTTPHeaderField: "X-Device-Id")
        }
        if let uid = userId {
            request.setValue(uid, forHTTPHeaderField: "X-User-Id")
        }
        
        var body: [String: Any] = [
            "item_id": itemId,
            "client_id": TNSubscriptionIOS.clientId
        ]
        if let extra = extraParams {
            body.merge(extra) { (_, new) in new }
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 500
                DispatchQueue.main.async {
                    completion(.failure(CurrencyError.spendFailed("HTTP status \(code)")))
                }
                return
            }
            
            // Server deduction confirmed, refresh from RevenueCat
            self.fetchCurrencies(forceRefresh: true) { result in
                switch result {
                case .success(let currencies):
                    var map: [String: Int] = [:]
                    for (k, v) in currencies.all { map[k] = v.balance }
                    completion(.success(map))
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }.resume()
    }
    
    // MARK: - Internal State Application
    
    @MainActor
    internal func apply(currencies result: VirtualCurrencies) {
        self.rawCurrencies = result
        self.currencies = result.all
        
        var newBalances: [String: Int] = [:]
        for (code, item) in result.all {
            newBalances[code] = item.balance
        }
        self.balances = newBalances
    }
    
    /// Triggered by `TNSubscriptionIOS` when a purchase or restore succeeds.
    internal func handlePurchaseOrRestoreSuccess() {
        Task {
            try? await fetchCurrenciesAsync(forceRefresh: true)
        }
    }
    
    // MARK: - Errors
    
    public enum CurrencyError: LocalizedError {
        case invalidAmount
        case amountExceedsLimit(Int)
        case insufficientBalance(current: Int, required: Int)
        case noSpendHandlerConfigured
        case spendFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .invalidAmount:
                return "Spend amount must be greater than zero."
            case .amountExceedsLimit(let limit):
                return "Amount exceeds the maximum limit of \(limit)."
            case .insufficientBalance(let current, let required):
                return "Insufficient balance: requires \(required), but user only has \(current)."
            case .noSpendHandlerConfigured:
                return "No spend handler configured. Configure a spend handler via `TNInAppCurrencyManager.shared.configureSpendHandler(...)` or use `spendViaProxy(...)`."
            case .spendFailed(let reason):
                return "Spend failed: \(reason)"
            }
        }
    }
}
