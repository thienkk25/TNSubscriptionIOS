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
    
    /// Tracks whether `TNInAppCurrencyManager.shared` has been accessed by the host app.
    internal private(set) static var isInitialized = false
    
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
    private static let localOffsetKeyPrefix = "tn_rc_currency_offset_"
    
    // MARK: - Initialization
    
    private init() {
        Self.isInitialized = true
        // Load cached currencies if RevenueCat is already configured to prevent UI flicker
        guard Purchases.isConfigured else { return }
        if let cached = Purchases.shared.cachedVirtualCurrencies {
            self.rawCurrencies = cached
            self.currencies = cached.all
            var newBalances: [String: Int] = [:]
            for (code, item) in cached.all {
                let offset = Self.loadLocalOffset(for: code)
                newBalances[code] = max(0, item.balance + offset)
            }
            self.balances = newBalances
        }
    }
    
    // MARK: - Persistent Local Offset Helpers (Serverless / No-Backend Support)
    
    private static func loadLocalOffset(for code: String) -> Int {
        let key = localOffsetKeyPrefix + code
        if let keychainStr = TNSubscriptionIOS.loadFromKeychain(account: key), let val = Int(keychainStr) {
            return val
        }
        if UserDefaults.standard.object(forKey: key) != nil {
            let saved = UserDefaults.standard.integer(forKey: key)
            TNSubscriptionIOS.saveToKeychain(account: key, value: "\(saved)")
            return saved
        }
        return 0
    }
    
    private static func saveLocalOffset(_ offset: Int, for code: String) {
        let key = localOffsetKeyPrefix + code
        UserDefaults.standard.set(offset, forKey: key)
        TNSubscriptionIOS.saveToKeychain(account: key, value: "\(offset)")
    }
    
    private func serverBalance(for code: String) -> Int {
        currencies[code]?.balance ?? 0
    }
    
    // MARK: - Public Fetch Methods
    
    /// Fetches virtual currencies from RevenueCat asynchronously.
    ///
    /// - Parameter forceRefresh: If `true`, invalidates the local cache before fetching.
    /// - Returns: The updated `VirtualCurrencies` object.
    @discardableResult
    @MainActor
    public func fetchCurrenciesAsync(forceRefresh: Bool = false) async throws -> VirtualCurrencies {
        guard Purchases.isConfigured else {
            throw CurrencyError.sdkNotConfigured
        }
        
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
        Task { @MainActor in
            do {
                let currencies = try await fetchCurrenciesAsync(forceRefresh: forceRefresh)
                completion?(.success(currencies))
            } catch {
                completion?(.failure(error))
            }
        }
    }
    
    /// Invalidates the local virtual currencies cache.
    /// Next fetch will query RevenueCat's servers directly.
    public func invalidateCache() {
        guard Purchases.isConfigured else { return }
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
        if let mem = balances[code] {
            return mem
        }
        let srv = serverBalance(for: code)
        let offset = Self.loadLocalOffset(for: code)
        return max(0, srv + offset)
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
        guard amount >= 0 else { return false }
        return balance(for: code) >= amount
    }
    
    // MARK: - Spending & Deductions (Serverless & Backend Modes)
    
    /// Configures an optional custom spend handler to execute currency deductions via your backend or proxy.
    /// If not configured, `spend(...)` automatically operates in Serverless Mode (persisting deductions in Keychain).
    /// (Cấu hình handler tùy chọn để trừ tiền qua backend. Nếu không cấu hình, `spend(...)` tự động hoạt động ở chế độ Không Backend — lưu vào Keychain.)
    public func configureSpendHandler(_ handler: @escaping SpendHandler) {
        self.customSpendHandler = handler
    }
    
    /// Deducts currency asynchronously.
    /// - If a backend `SpendHandler` is configured, delegates to the server and refreshes from RevenueCat.
    /// - If **no backend handler** is configured (Serverless project), automatically deducts and persists in Keychain.
    @MainActor
    @discardableResult
    public func spendAsync(
        code: String,
        amount: Int,
        reference: String? = nil
    ) async throws -> Int {
        guard amount > 0 else {
            throw CurrencyError.invalidAmount
        }
        
        guard canAfford(amount, currency: code) else {
            throw CurrencyError.insufficientBalance(current: balance(for: code), required: amount)
        }
        
        // Serverless / No-Backend fallback: persist deduction locally in Keychain
        guard let handler = customSpendHandler else {
            guard deductLocalBalance(amount, for: code) else {
                throw CurrencyError.insufficientBalance(current: balance(for: code), required: amount)
            }
            return balance(for: code)
        }
        
        do {
            let success = try await handler(code, amount, reference)
            guard success else {
                let err = CurrencyError.spendFailed("Server rejected currency deduction transaction.")
                self.error = err.localizedDescription
                throw err
            }
            let freshCurrencies = try await self.fetchCurrenciesAsync(forceRefresh: true)
            let offset = Self.loadLocalOffset(for: code)
            let rawServer = freshCurrencies[code]?.balance ?? self.serverBalance(for: code)
            return max(0, rawServer + offset)
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }
    
    /// Deducts currency (automatically uses Keychain persistence if no backend handler is configured, or delegates to server if configured).
    /// (Trừ tiền: tự động lưu bền vững vào Keychain nếu dự án không có backend, hoặc gọi server nếu đã cấu hình spend handler.)
    ///
    /// - Parameters:
    ///   - code: The currency code (e.g. "coins").
    ///   - amount: The amount to deduct (must be positive).
    ///   - reference: Optional unique transaction reference ID.
    ///   - completion: Callback with Result containing new balance or Error (guaranteed on `@MainActor`).
    public func spend(
        code: String,
        amount: Int,
        reference: String? = nil,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        Task { @MainActor in
            do {
                let newBalance = try await spendAsync(code: code, amount: amount, reference: reference)
                completion(.success(newBalance))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    /// Deducts a positive balance locally and persists the adjustment in Keychain & UserDefaults.
    /// Ideal for apps **without a backend**: survives `fetchCurrencies()` refreshes, app restarts, and reinstalls.
    /// (Trừ số dư cục bộ và lưu bền vững vào Keychain. Dành cho dự án **không có backend**: không bị mất khi gọi `fetchCurrencies()`, tắt app hay cài lại app.)
    ///
    /// - Parameters:
    ///   - amount: Positive amount to deduct.
    ///   - code: Currency code (e.g. "coins").
    /// - Returns: `true` if deduction succeeded, `false` if amount <= 0 or balance was insufficient.
    @discardableResult
    @MainActor
    public func deductLocalBalance(_ amount: Int, for code: String) -> Bool {
        guard amount > 0 else { return false }
        let current = balance(for: code)
        guard current >= amount else { return false }
        let newBalance = current - amount
        balances[code] = newBalance
        
        let currentOffset = Self.loadLocalOffset(for: code)
        Self.saveLocalOffset(currentOffset - amount, for: code)
        return true
    }
    
    /// Adds a positive bonus balance locally and persists the adjustment in Keychain & UserDefaults.
    /// Useful for serverless apps granting rewards (e.g. daily check-in, rewarded ads).
    /// (Cộng thêm số dư cục bộ và lưu vào Keychain — dùng cho app không có backend khi thưởng đăng nhập, xem quảng cáo...)
    @MainActor
    public func addLocalBalance(_ amount: Int, for code: String) {
        guard amount > 0 else { return }
        let current = balance(for: code)
        let (newBalance, overflow) = current.addingReportingOverflow(amount)
        let safeBalance = overflow ? Int.max : newBalance
        balances[code] = safeBalance
        
        let currentOffset = Self.loadLocalOffset(for: code)
        let (newOffset, offsetOverflow) = currentOffset.addingReportingOverflow(amount)
        Self.saveLocalOffset(offsetOverflow ? Int.max : newOffset, for: code)
    }
    
    /// Resets any local Keychain balance adjustments for a specific currency code back to zero.
    @MainActor
    public func resetLocalAdjustments(for code: String) {
        Self.saveLocalOffset(0, for: code)
        balances[code] = serverBalance(for: code)
    }
    
    /// Async helper to spend currency through your backend API or proxy gateway.
    /// Automatically attaches client identity headers (`X-Client-Id`, `X-Device-Id`, `X-User-Id`) and `Idempotency-Key`.
    @MainActor
    @discardableResult
    public func spendViaProxyAsync(
        proxyEndpoint: URL,
        apiKey: String,
        code: String,
        amount: Int,
        userId: String? = nil,
        idempotencyKey: String = UUID().uuidString
    ) async throws -> Int {
        guard amount > 0 else {
            throw CurrencyError.invalidAmount
        }
        
        guard amount <= 2_000_000_000 else {
            throw CurrencyError.amountExceedsLimit(2_000_000_000)
        }
        
        guard canAfford(amount, currency: code) else {
            throw CurrencyError.insufficientBalance(current: balance(for: code), required: amount)
        }
        
        var request = URLRequest(url: proxyEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.applyTNIdentityHeaders(userId: userId)
        
        let body: [String: Any] = [
            "currency_code": code,
            "amount": amount,
            "adjustments": [code: -abs(amount)],
            "client_id": TNSubscriptionIOS.clientId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
            let err = CurrencyError.spendFailed("HTTP status \(statusCode)")
            self.error = err.localizedDescription
            throw err
        }
        
        _ = try await self.fetchCurrenciesAsync(forceRefresh: true)
        return self.balance(for: code)
    }
    
    /// Helper to spend currency through your backend API or proxy gateway.
    /// Automatically attaches client identity headers (`X-Client-Id`, `X-Device-Id`, etc.) and `Idempotency-Key`.
    ///
    /// - Parameters:
    ///   - proxyEndpoint: URL of the spend endpoint on your server or API proxy.
    ///   - apiKey: Your app API key.
    ///   - code: Currency code to spend.
    ///   - amount: Amount to spend.
    ///   - userId: Optional user ID if logged in.
    ///   - idempotencyKey: Optional UUID key for retry safety. Defaults to a new UUID.
    ///   - completion: Callback returning new balance or error (guaranteed on `@MainActor`).
    public func spendViaProxy(
        proxyEndpoint: URL,
        apiKey: String,
        code: String,
        amount: Int,
        userId: String? = nil,
        idempotencyKey: String = UUID().uuidString,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        Task { @MainActor in
            do {
                let newBalance = try await spendViaProxyAsync(
                    proxyEndpoint: proxyEndpoint,
                    apiKey: apiKey,
                    code: code,
                    amount: amount,
                    userId: userId,
                    idempotencyKey: idempotencyKey
                )
                completion(.success(newBalance))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Secure Item-Based Purchases (RevenueCat Security Best Practice)
    
    /// Configures a custom handler for item-based purchases where backend validates and deducts the price.
    /// (Cấu hình handler mua item an toàn: Backend tự tra bảng giá và trừ tiền, Client không tự gửi giá).
    public func configureActionSpendHandler(_ handler: @escaping ActionSpendHandler) {
        self.customActionSpendHandler = handler
    }
    
    /// Securely purchases an item asynchronously through the configured action spend handler.
    @MainActor
    @discardableResult
    public func purchaseItemAsync(
        itemId: String,
        extraParams: [String: Any]? = nil
    ) async throws -> [String: Int] {
        guard let handler = customActionSpendHandler else {
            throw CurrencyError.noSpendHandlerConfigured
        }
        
        do {
            let success = try await handler(itemId, extraParams)
            guard success else {
                let err = CurrencyError.spendFailed("Backend rejected item purchase transaction.")
                self.error = err.localizedDescription
                throw err
            }
            let fresh = try await self.fetchCurrenciesAsync(forceRefresh: true)
            var updated: [String: Int] = [:]
            for (k, v) in fresh.all { updated[k] = v.balance }
            return updated
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }
    
    /// Securely purchases an item through the configured action spend handler.
    ///
    /// - Parameters:
    ///   - itemId: The item ID or action (e.g. "sung_vip", "hint").
    ///   - extraParams: Optional metadata to pass to backend.
    ///   - completion: Callback returning updated balances dictionary or Error (guaranteed on `@MainActor`).
    public func purchaseItem(
        itemId: String,
        extraParams: [String: Any]? = nil,
        completion: @escaping (Result<[String: Int], Error>) -> Void
    ) {
        Task { @MainActor in
            do {
                let updated = try await purchaseItemAsync(itemId: itemId, extraParams: extraParams)
                completion(.success(updated))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    /// Securely purchases an in-app virtual item asynchronously via your backend API or proxy gateway.
    @MainActor
    @discardableResult
    public func purchaseItemViaProxyAsync(
        proxyEndpoint: URL,
        apiKey: String,
        itemId: String,
        extraParams: [String: Any]? = nil,
        userId: String? = nil,
        idempotencyKey: String = UUID().uuidString
    ) async throws -> [String: Int] {
        var request = URLRequest(url: proxyEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.applyTNIdentityHeaders(userId: userId)
        
        var body: [String: Any] = [
            "item_id": itemId,
            "client_id": TNSubscriptionIOS.clientId
        ]
        if let extra = extraParams {
            body.merge(extra) { (_, new) in new }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
            let err = CurrencyError.spendFailed("HTTP status \(statusCode)")
            self.error = err.localizedDescription
            throw err
        }
        
        let currencies = try await self.fetchCurrenciesAsync(forceRefresh: true)
        var map: [String: Int] = [:]
        for (k, v) in currencies.all { map[k] = v.balance }
        return map
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
    ///   - idempotencyKey: Optional UUID key for retry safety. Defaults to a new UUID.
    ///   - completion: Callback returning updated balances map `[currencyCode: balance]` or error (guaranteed on `@MainActor`).
    public func purchaseItemViaProxy(
        proxyEndpoint: URL,
        apiKey: String,
        itemId: String,
        extraParams: [String: Any]? = nil,
        userId: String? = nil,
        idempotencyKey: String = UUID().uuidString,
        completion: @escaping (Result<[String: Int], Error>) -> Void
    ) {
        Task { @MainActor in
            do {
                let updated = try await purchaseItemViaProxyAsync(
                    proxyEndpoint: proxyEndpoint,
                    apiKey: apiKey,
                    itemId: itemId,
                    extraParams: extraParams,
                    userId: userId,
                    idempotencyKey: idempotencyKey
                )
                completion(.success(updated))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Internal State Application
    
    @MainActor
    internal func apply(currencies result: VirtualCurrencies) {
        self.rawCurrencies = result
        self.currencies = result.all
        
        var newBalances: [String: Int] = [:]
        for (code, item) in result.all {
            let offset = Self.loadLocalOffset(for: code)
            newBalances[code] = max(0, item.balance + offset)
        }
        self.balances = newBalances
    }
    
    /// Triggered by `TNSubscriptionIOS` when a purchase or restore succeeds.
    internal func handlePurchaseOrRestoreSuccess() {
        guard Purchases.isConfigured else { return }
        Task {
            try? await fetchCurrenciesAsync(forceRefresh: true)
        }
    }
    
    // MARK: - Errors
    
    public enum CurrencyError: LocalizedError {
        case sdkNotConfigured
        case invalidAmount
        case amountExceedsLimit(Int)
        case insufficientBalance(current: Int, required: Int)
        case noSpendHandlerConfigured
        case spendFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .sdkNotConfigured:
                return "RevenueCat SDK has not been configured yet. Call TNSubscriptionIOS.configure(...) first."
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
