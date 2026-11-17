import Foundation
import StoreKit

// MARK: - TNPackageType

/// The billing shape of a package, inferred from the StoreKit subscription period.
///
/// RevenueCat gets this from the dashboard package identifier (`$rc_annual`, …).
/// Here it is derived from `Product.subscription.subscriptionPeriod`, so it always
/// matches what App Store Connect actually sells.
/// (RevenueCat lấy giá trị này từ package identifier trên dashboard (`$rc_annual`, …).
/// Ở đây nó được suy ra từ `Product.subscription.subscriptionPeriod`, nên luôn khớp với
/// những gì App Store Connect thật sự đang bán.)
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

    /// Display order on a paywall: longest commitment first.
    /// (Thứ tự hiển thị trên paywall: kỳ hạn dài nhất trước.)
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

    /// Infers the package type from a StoreKit product.
    /// (Suy ra loại gói từ một sản phẩm StoreKit.)
    public static func inferred(from product: Product) -> TNPackageType {
        switch product.type {
        case .nonConsumable:
            return .lifetime
        case .consumable:
            return .unknown
        default:
            break
        }

        guard let period = product.subscription?.subscriptionPeriod else { return .unknown }

        switch (period.unit, period.value) {
        case (.day, 7), (.week, 1):
            return .weekly
        case (.month, 1):
            return .monthly
        case (.month, 2):
            return .twoMonth
        case (.month, 3):
            return .threeMonth
        case (.month, 6):
            return .sixMonth
        case (.year, 1):
            return .annual
        case (.day, 365), (.month, 12):
            return .annual
        default:
            return .custom
        }
    }
}

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
    public var pricePerMonth: Decimal? {
        guard let period = product.subscription?.subscriptionPeriod,
              let months = period.monthsFraction,
              months.numerator > 0 else { return nil }
        // price / (numerator/denominator) == price * denominator / numerator, which keeps
        // every operand an integer-backed Decimal and needs only one division.
        return product.price * Decimal(months.denominator) / Decimal(months.numerator)
    }

    /// `pricePerMonth` formatted in the product's own currency, e.g. `"$4.16"`.
    /// (`pricePerMonth` đã định dạng theo tiền tệ của sản phẩm, ví dụ `"90.800 ₫"`.)
    public var localizedPricePerMonth: String? {
        guard let perMonth = pricePerMonth else { return nil }
        return product.priceFormatStyle.format(perMonth)
    }

    /// The percentage saved versus a reference package, rounded down (e.g. `40` for "save 40%").
    /// Returns `nil` when either package has no period, or when this one is not cheaper.
    /// (Phần trăm tiết kiệm so với một gói tham chiếu, làm tròn xuống — ví dụ `40` nghĩa là
    /// "tiết kiệm 40%". Trả về `nil` khi một trong hai gói không có kỳ hạn, hoặc khi gói này
    /// không rẻ hơn.)
    public func savingsPercentage(comparedTo other: TNPackage) -> Int? {
        guard let mine = pricePerMonth, let theirs = other.pricePerMonth else { return nil }
        // Deliberately in Double: a percentage needs no decimal precision, and chaining a
        // second Decimal division on an already-divided value is what overflows the mantissa
        // into `nan` — which would surface as a silent "SAVE 0%" badge.
        let mineValue = Double(truncating: mine as NSDecimalNumber)
        let theirsValue = Double(truncating: theirs as NSDecimalNumber)
        guard theirsValue > 0, mineValue.isFinite, theirsValue.isFinite else { return nil }
        guard mineValue < theirsValue else { return nil }
        let percentage = (theirsValue - mineValue) / theirsValue * 100
        guard percentage.isFinite else { return nil }
        return Int(percentage.rounded(.down))
    }
}

// MARK: - Period Helpers

extension Product.SubscriptionPeriod {

    /// The period length in months, as an exact integer fraction.
    /// Weeks and days are approximated (a month is treated as 30 days, a week as 7).
    /// (Độ dài kỳ hạn tính theo tháng, dưới dạng phân số nguyên chính xác.
    /// Tuần và ngày được tính xấp xỉ: một tháng coi như 30 ngày, một tuần là 7 ngày.)
    ///
    /// This returns a fraction rather than a `Double` on purpose. Going through
    /// `Decimal(Double)` produces a value with a huge mantissa — `7.0/30.0` becomes
    /// 0.2333…334 to full binary precision — and a later `Decimal` division on such a value
    /// overflows the 38-digit mantissa and silently yields `Decimal.nan`, which then reads
    /// as `0`. Keeping integers and dividing once avoids that entirely.
    /// (Hàm này trả về phân số thay vì `Double` là có chủ đích. Đi qua `Decimal(Double)` sinh
    /// ra giá trị có mantissa rất dài — `7.0/30.0` thành 0,2333…334 ở độ chính xác nhị phân
    /// đầy đủ — và một phép chia `Decimal` sau đó trên giá trị như vậy sẽ tràn mantissa 38 chữ
    /// số rồi âm thầm cho ra `Decimal.nan`, đọc ra thành `0`. Giữ số nguyên và chỉ chia một
    /// lần thì tránh được hẳn.)
    var monthsFraction: (numerator: Int, denominator: Int)? {
        switch unit {
        case .day: return (value, 30)
        case .week: return (value * 7, 30)
        case .month: return (value, 1)
        case .year: return (value * 12, 1)
        @unknown default: return nil
        }
    }

    /// A localised description such as `"3 Days"`, `"1 Week"`, `"1 Month"`.
    /// (Mô tả đã dịch, ví dụ `"3 Ngày"`, `"1 Tuần"`, `"1 Tháng"`.)
    /// - Parameter numberOfPeriods: How many times the period repeats (for `payAsYouGo` offers).
    ///   (Kỳ hạn lặp lại bao nhiêu lần — dùng cho ưu đãi `payAsYouGo`.)
    public func localizedDescription(numberOfPeriods: Int = 1) -> String {
        let totalUnits = max(1, value * max(1, numberOfPeriods))
        switch unit {
        case .day:
            return totalUnits == 1
                ? NSLocalizedString("1 Day", comment: "")
                : String(format: NSLocalizedString("%d Days", comment: ""), totalUnits)
        case .week:
            return totalUnits == 1
                ? NSLocalizedString("1 Week", comment: "")
                : String(format: NSLocalizedString("%d Weeks", comment: ""), totalUnits)
        case .month:
            return totalUnits == 1
                ? NSLocalizedString("1 Month", comment: "")
                : String(format: NSLocalizedString("%d Months", comment: ""), totalUnits)
        case .year:
            return totalUnits == 1
                ? NSLocalizedString("1 Year", comment: "")
                : String(format: NSLocalizedString("%d Years", comment: ""), totalUnits)
        @unknown default:
            return "\(totalUnits)"
        }
    }
}
