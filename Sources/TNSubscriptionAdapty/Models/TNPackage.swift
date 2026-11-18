import Foundation
import StoreKit
import Adapty

// MARK: - TNPackageType

/// The billing shape of a package, inferred from the StoreKit subscription period.
/// (Hình thức thanh toán của gói, suy ra từ kỳ hạn subscription của StoreKit.)
///
/// Derived from the product itself rather than from a dashboard label, so it always matches
/// what App Store Connect actually sells.
/// (Suy ra từ chính sản phẩm thay vì từ nhãn trên dashboard, nên luôn khớp với những gì App Store
/// Connect thật sự đang bán.)
public enum TNPackageType: String, Hashable, Sendable, CaseIterable {
    case lifetime
    case annual
    case sixMonth
    case threeMonth
    case twoMonth
    case monthly
    case weekly
    /// A subscription whose period is none of the standard ones (e.g. 10 days).
    /// (Subscription có kỳ hạn không thuộc các mốc chuẩn, ví dụ 10 ngày.)
    case custom
    /// A consumable or a product whose type could not be determined.
    /// (Consumable, hoặc sản phẩm không xác định được loại.)
    case unknown

    /// Display order when sorting is requested: longest commitment first.
    /// (Thứ tự hiển thị khi cần sắp xếp: kỳ hạn dài nhất trước.)
    public var sortOrder: Int {
        switch self {
        case .lifetime: return 0
        case .annual: return 1
        case .sixMonth: return 2
        case .threeMonth: return 3
        case .twoMonth: return 4
        case .monthly: return 5
        case .weekly: return 6
        case .custom: return 7
        case .unknown: return 8
        }
    }

    /// A localised plan name, or `nil` for the types that have no sensible fixed name.
    /// (Tên gói đã dịch, hoặc `nil` với các loại không có tên cố định hợp lý.)
    public var localizedName: String? {
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

    /// Infers the package type from a StoreKit product.
    /// (Suy ra loại gói từ một sản phẩm StoreKit.)
    public static func inferred(from product: Product) -> TNPackageType {
        switch product.type {
        case .nonConsumable: return .lifetime
        case .consumable: return .unknown
        default: break
        }
        guard let period = product.subscription?.subscriptionPeriod else { return .unknown }
        return inferred(unitDays: period.unit.tn_days, value: period.value)
    }

    /// Infers the package type from a period expressed as a unit (in days) and a count.
    /// (Suy ra loại gói từ một kỳ hạn biểu diễn bằng đơn vị (theo ngày) và số lượng.)
    ///
    /// Split out from `inferred(from:)` so the mapping is unit-testable: StoreKit offers no way
    /// to construct a `Product` outside a StoreKit test session.
    /// (Tách riêng khỏi `inferred(from:)` để phần mapping unit-test được: StoreKit không có cách
    /// tạo `Product` bên ngoài một StoreKit test session.)
    static func inferred(unitDays: Int, value: Int) -> TNPackageType {
        switch (unitDays, value) {
        case (1, 7), (7, 1): return .weekly
        case (30, 1): return .monthly
        case (30, 2): return .twoMonth
        case (30, 3): return .threeMonth
        case (30, 6): return .sixMonth
        case (365, 1), (1, 365), (30, 12): return .annual
        default: return .custom
        }
    }
}

extension Product.SubscriptionPeriod.Unit {
    /// A stable day count per unit, used only to classify periods — not for date maths.
    /// (Số ngày cố định cho mỗi đơn vị, chỉ dùng để phân loại kỳ hạn — không dùng tính ngày.)
    var tn_days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .year: return 365
        @unknown default: return 0
        }
    }
}

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
    public var pricePerMonth: Decimal? {
        guard let period = product.subscription?.subscriptionPeriod,
              let months = period.monthsFraction,
              months.numerator > 0 else { return nil }
        // price / (n/d) == price * d / n: integer-backed operands and a single division.
        // See `monthsFraction` for why this must not go through Double.
        return product.price * Decimal(months.denominator) / Decimal(months.numerator)
    }

    /// `pricePerMonth` formatted in the product's own currency.
    /// (`pricePerMonth` đã định dạng theo tiền tệ của sản phẩm.)
    public var localizedPricePerMonth: String? {
        guard let perMonth = pricePerMonth else { return nil }
        return product.priceFormatStyle.format(perMonth)
    }

    /// The percentage saved versus a reference package, rounded down. `nil` when either has no
    /// period or this one is not cheaper.
    /// (Phần trăm tiết kiệm so với một gói tham chiếu, làm tròn xuống. `nil` khi một trong hai
    /// không có kỳ hạn, hoặc gói này không rẻ hơn.)
    public func savingsPercentage(comparedTo other: TNPackage) -> Int? {
        guard let mine = pricePerMonth, let theirs = other.pricePerMonth else { return nil }
        return Self.savingsPercentage(perMonth: mine, comparedTo: theirs)
    }

    /// The savings maths on plain numbers, so it can be unit-tested without a `Product`.
    /// (Phần tính tiết kiệm trên số thuần, để unit-test được mà không cần `Product`.)
    ///
    /// Computed in `Double` on purpose: chaining a second `Decimal` division onto an
    /// already-divided value overflows the 38-digit mantissa into `nan`, which then reads as a
    /// silent "SAVE 0%".
    /// (Cố ý tính bằng `Double`: thêm một phép chia `Decimal` thứ hai lên giá trị đã chia sẽ làm
    /// tràn mantissa 38 chữ số thành `nan`, đọc ra thành "SAVE 0%" mà không báo gì.)
    static func savingsPercentage(perMonth mine: Decimal, comparedTo theirs: Decimal) -> Int? {
        let mineValue = Double(truncating: mine as NSDecimalNumber)
        let theirsValue = Double(truncating: theirs as NSDecimalNumber)
        guard theirsValue > 0, mineValue.isFinite, theirsValue.isFinite, mineValue < theirsValue else { return nil }
        let percentage = (theirsValue - mineValue) / theirsValue * 100
        guard percentage.isFinite else { return nil }
        return Int(percentage.rounded(.down))
    }
}

// MARK: - Period Helpers

extension Product.SubscriptionPeriod {

    /// The period length in months, as an exact integer fraction.
    /// (Độ dài kỳ hạn tính theo tháng, dưới dạng phân số nguyên chính xác.)
    ///
    /// A fraction rather than a `Double`: `Decimal(7.0/30.0)` carries a full binary-precision
    /// mantissa, and a later `Decimal` division on it silently overflows into `nan`.
    /// (Phân số thay vì `Double`: `Decimal(7.0/30.0)` mang mantissa ở độ chính xác nhị phân đầy
    /// đủ, và một phép chia `Decimal` sau đó sẽ âm thầm tràn thành `nan`.)
    var monthsFraction: (numerator: Int, denominator: Int)? {
        switch unit {
        case .day: return (value, 30)
        case .week: return (value * 7, 30)
        case .month: return (value, 1)
        case .year: return (value * 12, 1)
        @unknown default: return nil
        }
    }
}

// MARK: - Localised Period

/// Formats a period such as `"3 Days"` or `"1 Month"`.
/// (Định dạng một kỳ hạn, ví dụ `"3 Ngày"` hoặc `"1 Tháng"`.)
enum TNPeriodFormatter {

    enum Unit { case day, week, month, year }

    static func string(unit: Unit, count: Int) -> String {
        let total = max(1, count)
        switch unit {
        case .day:
            return total == 1 ? NSLocalizedString("1 Day", comment: "")
                : String(format: NSLocalizedString("%d Days", comment: ""), total)
        case .week:
            return total == 1 ? NSLocalizedString("1 Week", comment: "")
                : String(format: NSLocalizedString("%d Weeks", comment: ""), total)
        case .month:
            return total == 1 ? NSLocalizedString("1 Month", comment: "")
                : String(format: NSLocalizedString("%d Months", comment: ""), total)
        case .year:
            return total == 1 ? NSLocalizedString("1 Year", comment: "")
                : String(format: NSLocalizedString("%d Years", comment: ""), total)
        }
    }
}
