import Foundation
import StoreKit

// `TNPackageType`, the price maths and the period helpers live in TNSubscriptionShared.
// (`TNPackageType`, phần tính giá và helper kỳ hạn nằm trong TNSubscriptionShared.)

// MARK: - TNPackage

/// A purchasable plan shown on a paywall: a StoreKit `Product` plus the offering context.
///
/// This is the local replacement for RevenueCat's `Package`. The underlying
/// `StoreKit.Product` is exposed as `product` (and as `storeProduct`, for symmetry with
/// the RevenueCat-backed target) so nothing about StoreKit is hidden from you.
/// (Đây là bản thay thế cục bộ cho `Package` của RevenueCat. `StoreKit.Product` bên dưới được
/// expose qua `product` — và qua `storeProduct` để giống target dùng RevenueCat — nên không
/// có phần nào của StoreKit bị che khỏi bạn.)
public struct TNPackage: Identifiable, Hashable, Sendable {

    /// A stable identifier for this package: `"<offering>:<productID>"`.
    /// Unique even when the same product appears in two offerings.
    /// (ID ổn định của gói này: `"<offering>:<productID>"`. Vẫn duy nhất khi cùng một sản phẩm
    /// xuất hiện ở hai offering khác nhau.)
    public let identifier: String

    /// The identifier of the offering this package came from.
    /// (ID của offering mà gói này thuộc về.)
    public let offeringIdentifier: String

    /// The billing shape, inferred from the StoreKit subscription period.
    /// (Hình thức thanh toán, suy ra từ kỳ hạn subscription của StoreKit.)
    public let packageType: TNPackageType

    /// The underlying StoreKit 2 product.
    /// (Sản phẩm StoreKit 2 bên dưới.)
    public let product: Product

    public var id: String { identifier }

    /// Alias for `product`, so paywall code reads the same as in the RevenueCat-backed target.
    /// (Bí danh của `product`, để code paywall đọc giống như ở target dùng RevenueCat.)
    public var storeProduct: Product { product }

    /// The StoreKit product identifier.
    /// (Product identifier của StoreKit.)
    public var productIdentifier: String { product.id }

    /// The store-localised price, already formatted in the user's currency (e.g. `"$49.99"`).
    /// (Giá do store cung cấp, đã định dạng theo tiền tệ của người dùng, ví dụ `"1.090.000 ₫"`.)
    public var localizedPriceString: String { product.displayPrice }

    /// The store-localised product name.
    /// (Tên sản phẩm do store cung cấp, đã dịch.)
    public var localizedTitle: String { product.displayName }

    /// The store-localised product description.
    /// (Mô tả sản phẩm do store cung cấp, đã dịch.)
    public var localizedDescription: String { product.description }

    /// `true` when this product is an auto-renewable subscription.
    /// (`true` khi sản phẩm này là subscription tự động gia hạn.)
    public var isSubscription: Bool { product.subscription != nil }

    public init(
        offeringIdentifier: String,
        product: Product,
        packageType: TNPackageType? = nil
    ) {
        self.offeringIdentifier = offeringIdentifier
        self.product = product
        self.packageType = packageType ?? .inferred(from: product)
        self.identifier = "\(offeringIdentifier):\(product.id)"
    }

    // MARK: - Price Maths

    /// The price normalised to one month, for an honest "per month" comparison across plans.
    /// `nil` for lifetime / consumable products, which have no period.
    /// (Giá quy về một tháng, để so sánh "mỗi tháng" giữa các gói một cách trung thực.
    /// `nil` với sản phẩm vĩnh viễn / consumable vì chúng không có kỳ hạn.)
    public var pricePerMonth: Decimal? { TNPriceMath.pricePerMonth(of: product) }

    /// `pricePerMonth` formatted in the product's own currency, e.g. `"$4.16"`.
    /// (`pricePerMonth` đã định dạng theo tiền tệ của sản phẩm, ví dụ `"90.800 ₫"`.)
    public var localizedPricePerMonth: String? { TNPriceMath.localizedPricePerMonth(of: product) }

    /// The percentage saved versus a reference package, rounded down (e.g. `40` for "save 40%").
    /// Returns `nil` when either package has no period, or when this one is not cheaper.
    /// (Phần trăm tiết kiệm so với một gói tham chiếu, làm tròn xuống — ví dụ `40` nghĩa là
    /// "tiết kiệm 40%". Trả về `nil` khi một trong hai gói không có kỳ hạn, hoặc khi gói này
    /// không rẻ hơn.)
    public func savingsPercentage(comparedTo other: TNPackage) -> Int? {
        guard let mine = pricePerMonth, let theirs = other.pricePerMonth else { return nil }
        return TNPriceMath.savingsPercentage(perMonth: mine, comparedTo: theirs)
    }
}
