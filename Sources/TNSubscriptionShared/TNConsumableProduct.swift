import Foundation

// MARK: - TNConsumableProduct

/// A consumable product and the reward it credits — the same type in every engine.
/// (Một sản phẩm consumable và phần thưởng nó cộng — cùng một kiểu ở mọi engine.)
///
/// ```swift
/// TNConsumableProduct(id: "com.app.100coins", reward: 100, currency: "coins")
/// ```
public struct TNConsumableProduct: Hashable, Sendable {
    /// The StoreKit product ID. (Product ID của StoreKit.)
    public let id: String

    /// How much of `currency` a purchase credits. (Số lượng `currency` mỗi lần mua được cộng.)
    public let reward: Int

    /// The currency bucket, e.g. `"coins"`. (Loại tiền, ví dụ `"coins"`.)
    public let currency: String

    public init(id: String, reward: Int, currency: String) {
        self.id = id
        self.reward = reward
        self.currency = currency
    }
}
