import Foundation
import StoreKit
import Adapty

// `TNPackageType`, the price maths and the period helpers live in TNSubscriptionShared.
// (`TNPackageType`, phần tính giá và helper kỳ hạn nằm trong TNSubscriptionShared.)

// MARK: - TNPackage

/// A purchasable plan from an Adapty placement.
/// (Một gói có thể mua, lấy từ một placement của Adapty.)
///
/// Wraps `AdaptyPaywallProduct`, which in turn exposes the real `StoreKit.Product` — so the
/// price maths here is identical to the other two engines.
/// (Bọc `AdaptyPaywallProduct`, vốn expose `StoreKit.Product` thật — nên phần tính giá ở đây
/// giống hệt hai engine còn lại.)
public struct TNPackage: Identifiable, Hashable, Sendable {

    /// `"<placement>:<productID>"`, unique even when one product appears in two placements.
    /// (`"<placement>:<productID>"`, vẫn duy nhất khi một sản phẩm xuất hiện ở hai placement.)
    public let identifier: String

    /// The placement this package came from.
    /// (Placement mà gói này thuộc về.)
    public let offeringIdentifier: String

    /// The billing shape, inferred from the StoreKit subscription period.
    /// (Hình thức thanh toán, suy ra từ kỳ hạn subscription của StoreKit.)
    public let packageType: TNPackageType

    /// The Adapty product. Pass it to Adapty APIs directly when you need something this
    /// wrapper does not expose.
    /// (Sản phẩm Adapty. Truyền thẳng vào API của Adapty khi cần thứ mà wrapper này chưa expose.)
    public let adaptyProduct: AdaptyPaywallProduct

    public var id: String { identifier }

    /// The underlying StoreKit 2 product.
    /// (Sản phẩm StoreKit 2 bên dưới.)
    public var product: Product { adaptyProduct.skProduct }

    /// Alias for `product`, so paywall code reads the same as in the other engines.
    /// (Bí danh của `product`, để code paywall đọc giống như ở các engine khác.)
    public var storeProduct: Product { product }

    /// The StoreKit product identifier.
    /// (Product identifier của StoreKit.)
    public var productIdentifier: String { adaptyProduct.vendorProductId }

    /// The store-localised price, e.g. `"$49.99"`.
    /// (Giá do store cung cấp, đã định dạng, ví dụ `"1.090.000 ₫"`.)
    public var localizedPriceString: String { adaptyProduct.localizedPrice }

    /// The store-localised product name.
    /// (Tên sản phẩm do store cung cấp, đã dịch.)
    public var localizedTitle: String { adaptyProduct.localizedTitle }

    /// The store-localised product description.
    /// (Mô tả sản phẩm do store cung cấp, đã dịch.)
    public var localizedDescription: String { adaptyProduct.localizedDescription }

    /// `true` when this product is an auto-renewable subscription.
    /// (`true` khi sản phẩm này là subscription tự động gia hạn.)
    public var isSubscription: Bool { product.subscription != nil }

    /// The Adapty A/B-test variation this package was served under — log it with your own
    /// analytics to attribute a purchase to the variant that drove it.
    /// (Biến thể A/B test mà gói này được hiển thị — ghi lại trong analytics của bạn để quy một
    /// giao dịch về đúng biến thể đã tạo ra nó.)
    public var variationId: String { adaptyProduct.variationId }

    public init(offeringIdentifier: String, adaptyProduct: AdaptyPaywallProduct) {
        self.offeringIdentifier = offeringIdentifier
        self.adaptyProduct = adaptyProduct
        self.packageType = .inferred(from: adaptyProduct.skProduct)
        self.identifier = "\(offeringIdentifier):\(adaptyProduct.vendorProductId)"
    }

    public static func == (lhs: TNPackage, rhs: TNPackage) -> Bool {
        lhs.identifier == rhs.identifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    // MARK: - Price Maths

    /// The price normalised to one month. `nil` for products with no period.
    /// (Giá quy về một tháng. `nil` với sản phẩm không có kỳ hạn.)
    public var pricePerMonth: Decimal? { TNPriceMath.pricePerMonth(of: product) }

    /// `pricePerMonth` formatted in the product's own currency.
    /// (`pricePerMonth` đã định dạng theo tiền tệ của sản phẩm.)
    public var localizedPricePerMonth: String? { TNPriceMath.localizedPricePerMonth(of: product) }

    /// The percentage saved versus a reference package, rounded down. `nil` when either has no
    /// period or this one is not cheaper.
    /// (Phần trăm tiết kiệm so với một gói tham chiếu, làm tròn xuống. `nil` khi một trong hai
    /// không có kỳ hạn, hoặc gói này không rẻ hơn.)
    public func savingsPercentage(comparedTo other: TNPackage) -> Int? {
        guard let mine = pricePerMonth, let theirs = other.pricePerMonth else { return nil }
        return TNPriceMath.savingsPercentage(perMonth: mine, comparedTo: theirs)
    }
}
