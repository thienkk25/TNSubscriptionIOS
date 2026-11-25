import Foundation
import StoreKit

// MARK: - TNPackageType

/// The billing shape of a package, inferred from the StoreKit subscription period.
/// (Dạng thanh toán của một gói, suy ra từ kỳ hạn subscription của StoreKit.)
///
/// RevenueCat gets this from the dashboard package identifier (`$rc_annual`, …). These engines
/// derive it from `Product.subscription.subscriptionPeriod`, so it always matches what App Store
/// Connect actually sells.
/// (RevenueCat lấy giá trị này từ package identifier trên dashboard (`$rc_annual`, …). Các engine
/// này suy ra nó từ `Product.subscription.subscriptionPeriod`, nên luôn khớp với những gì App Store
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
        return inferred(unitDays: period.unit.tnDays, value: period.value)
    }

    /// The period rule on plain numbers, so tests need no StoreKit product.
    /// (Quy tắc kỳ hạn trên số thuần, để test không cần sản phẩm StoreKit.)
    package static func inferred(unitDays: Int, value: Int) -> TNPackageType {
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

    /// A plan name guessed from a product ID, for when the StoreKit product is not loaded.
    /// Prefer the store's `product.displayName` whenever it is available.
    /// (Tên gói đoán từ product ID, dùng khi chưa tải được sản phẩm StoreKit. Hãy ưu tiên
    /// `product.displayName` của store khi có.)
    package static func displayName(forProductID productID: String) -> String {
        let lower = productID.lowercased()
        if lower.contains("week") { return NSLocalizedString("Weekly", comment: "") }
        if lower.contains("month") { return NSLocalizedString("Monthly", comment: "") }
        if lower.contains("year") || lower.contains("annual") { return NSLocalizedString("Yearly", comment: "") }
        if lower.contains("life") || lower.contains("forever") { return NSLocalizedString("Lifetime", comment: "") }
        return NSLocalizedString("Premium", comment: "")
    }
}

// MARK: - TNIntroEligibilityStatus

/// Whether the user may claim a product's introductory offer / free trial.
/// (Người dùng có đủ điều kiện nhận ưu đãi người mới / dùng thử miễn phí hay không.)
///
/// StoreKit 2 answers this exactly, per **subscription group**, from the Apple ID's own purchase
/// history.
/// (StoreKit 2 trả lời chính xác câu hỏi này theo từng **subscription group**, dựa trên lịch sử mua
/// của Apple ID.)
public enum TNIntroEligibilityStatus: String, Hashable, Sendable {
    /// Eligibility has not been determined yet (products still loading).
    /// (Chưa xác định được — sản phẩm vẫn đang tải.)
    case unknown
    /// The user may claim the introductory offer.
    /// (Người dùng đủ điều kiện nhận ưu đãi người mới.)
    case eligible
    /// Not eligible: the introductory offer for this subscription group was already used, or
    /// (with Adapty) a better offer such as a win-back takes precedence.
    /// (Không đủ điều kiện: đã dùng ưu đãi người mới của group này, hoặc — với Adapty — có ưu đãi tốt
    /// hơn như win-back được ưu tiên.)
    case ineligible
    /// This product has no introductory offer configured in App Store Connect.
    /// (Sản phẩm này không có ưu đãi người mới nào được cấu hình trên App Store Connect.)
    case noIntroOfferExists
}

// MARK: - Price Maths

/// Per-month price and savings, identical for every engine's `TNPackage`.
/// (Giá mỗi tháng và phần trăm tiết kiệm — giống nhau cho `TNPackage` của mọi engine.)
package enum TNPriceMath {

    /// The price normalised to one month; `nil` for products with no period.
    /// (Giá quy về một tháng; `nil` với sản phẩm không có kỳ hạn.)
    package static func pricePerMonth(of product: Product) -> Decimal? {
        guard let period = product.subscription?.subscriptionPeriod,
              let months = period.monthsFraction,
              months.numerator > 0 else { return nil }
        // price / (n/d) == price * d / n: integer-backed operands and a single division.
        // See `monthsFraction` for why this must not go through Double.
        return product.price * Decimal(months.denominator) / Decimal(months.numerator)
    }

    /// `pricePerMonth` formatted in the product's own currency.
    /// (`pricePerMonth` định dạng theo tiền tệ của sản phẩm.)
    package static func localizedPricePerMonth(of product: Product) -> String? {
        guard let perMonth = pricePerMonth(of: product) else { return nil }
        return product.priceFormatStyle.format(perMonth)
    }

    /// The percentage saved, rounded down; `nil` when this price is not cheaper.
    /// (Phần trăm tiết kiệm, làm tròn xuống; `nil` khi giá này không rẻ hơn.)
    package static func savingsPercentage(perMonth mine: Decimal, comparedTo theirs: Decimal) -> Int? {
        // Deliberately in Double: a percentage needs no decimal precision, and chaining a second
        // Decimal division on an already-divided value is what overflows the mantissa into `nan`
        // — which would surface as a silent "SAVE 0%" badge.
        let mineValue = Double(truncating: mine as NSDecimalNumber)
        let theirsValue = Double(truncating: theirs as NSDecimalNumber)
        guard theirsValue > 0, mineValue.isFinite, theirsValue.isFinite, mineValue < theirsValue else { return nil }
        let percentage = (theirsValue - mineValue) / theirsValue * 100
        guard percentage.isFinite else { return nil }
        return Int(percentage.rounded(.down))
    }

    /// The package with the lowest per-month price, or the first package when none has a period.
    /// (Gói có giá mỗi tháng thấp nhất, hoặc gói đầu tiên khi không gói nào có kỳ hạn.)
    package static func recommended<P>(_ packages: [P], pricePerMonth: (P) -> Decimal?) -> P? {
        let priced = packages.compactMap { package in pricePerMonth(package).map { (package, $0) } }
        guard let cheapest = priced.min(by: { $0.1 < $1.1 }) else { return packages.first }
        return cheapest.0
    }
}

// MARK: - Period Helpers

extension Product.SubscriptionPeriod.Unit {
    /// The unit in days (a month counts as 30). (Đơn vị tính theo ngày — một tháng tính 30 ngày.)
    package var tnDays: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .year: return 365
        @unknown default: return 0
        }
    }
}

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
    package var monthsFraction: (numerator: Int, denominator: Int)? {
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
        let count = value * max(1, numberOfPeriods)
        switch unit {
        case .day: return TNPeriodFormatter.string(unit: .day, count: count)
        case .week: return TNPeriodFormatter.string(unit: .week, count: count)
        case .month: return TNPeriodFormatter.string(unit: .month, count: count)
        case .year: return TNPeriodFormatter.string(unit: .year, count: count)
        @unknown default: return "\(max(1, count))"
        }
    }
}

// MARK: - TNPeriodFormatter

/// Localised period text, for StoreKit periods and for vendor period types alike.
/// (Chuỗi kỳ hạn đã dịch, dùng cho kỳ hạn StoreKit lẫn kiểu kỳ hạn của nhà cung cấp.)
package enum TNPeriodFormatter {

    package enum Unit { case day, week, month, year }

    package static func string(unit: Unit, count: Int) -> String {
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
