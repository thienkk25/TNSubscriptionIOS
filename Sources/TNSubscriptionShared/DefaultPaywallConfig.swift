import SwiftUI

// MARK: - DefaultPaywallConfig

/// Configuration for the built-in paywall — the same type in every engine.
/// (Cấu hình cho paywall có sẵn — cùng một kiểu ở mọi engine.)
///
/// Pass it to `TNSubscription.presentDefaultPaywall(from:config:)`, or to
/// `TNDefaultPaywallView(config:)` in SwiftUI. Every field has a sensible default, so you
/// only set what you want to change.
/// (Truyền vào `TNSubscription.presentDefaultPaywall(from:config:)`, hoặc
/// `TNDefaultPaywallView(config:)` trong SwiftUI. Mọi thuộc tính đều có giá trị mặc định hợp lý,
/// nên bạn chỉ cần đặt những gì muốn đổi.)
public struct DefaultPaywallConfig {

    /// A premium feature shown in the paywall's list.
    /// (Một tính năng premium hiển thị trong danh sách của paywall.)
    public struct Feature: Identifiable, Hashable {
        public var id: String { "\(icon)-\(title)-\(subtitle)" }

        /// An SF Symbols name, e.g. `"sparkles"`.
        /// (Tên SF Symbols, ví dụ `"sparkles"`.)
        public let icon: String
        public let title: String
        public let subtitle: String

        public init(icon: String, title: String, subtitle: String) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
        }
    }

    // MARK: - Content & Targeting

    /// The app name shown above the headline.
    /// (Tên app hiển thị phía trên tiêu đề.)
    public var appName: String

    /// The premium features listed to the user.
    /// (Danh sách tính năng premium hiển thị cho người dùng.)
    public var features: [Feature]

    /// Which offering to display. RevenueCat: an offering ID. Adapty: a **placement ID**. Core: a
    /// `TNOffering` ID. `nil` uses `TNSubscriptionConfig.currentOfferingIdentifier`.
    /// (Hiển thị offering nào. RevenueCat: offering ID. Adapty: **placement ID**. Core: ID của
    /// `TNOffering`. `nil` dùng `TNSubscriptionConfig.currentOfferingIdentifier`.)
    public var offeringIdentifier: String?

    /// Which entitlement this paywall unlocks (e.g. `"Sale"`). `nil` checks `isPremium`,
    /// i.e. any active entitlement.
    /// (Paywall này mở khoá quyền lợi nào, ví dụ `"Sale"`. `nil` sẽ kiểm tra `isPremium`,
    /// tức bất kỳ quyền lợi nào đang hoạt động.)
    public var entitlementId: String?

    /// Show the "Redeem Code" button, which opens Apple's native Offer Code sheet.
    /// Defaults to `true`.
    /// (Hiện nút "Nhập mã", mở bảng Offer Code của Apple. Mặc định `true`.)
    public var showRedeemCodeButton: Bool

    /// Show a "Save X%" badge on the cheapest-per-month plan. Defaults to `true`.
    /// (Hiện nhãn "Tiết kiệm X%" trên gói rẻ nhất tính theo tháng. Mặc định `true`.)
    public var showSavingsBadge: Bool

    /// Show the per-month equivalent price under each plan. Defaults to `true`.
    /// (Hiện giá quy đổi theo tháng dưới mỗi gói. Mặc định `true`.)
    public var showPricePerMonth: Bool

    /// Privacy Policy URL. `nil` hides the link.
    /// (URL Chính sách bảo mật. `nil` sẽ ẩn liên kết.)
    ///
    /// App Review expects both this and `termsURL` on a screen that sells a subscription.
    /// (App Review yêu cầu có cả cái này và `termsURL` trên màn hình bán subscription.)
    public var privacyURL: URL?

    /// Terms of Use URL. `nil` hides the link.
    /// (URL Điều khoản sử dụng. `nil` sẽ ẩn liên kết.)
    public var termsURL: URL?

    // MARK: - Theme

    /// Primary accent colour (buttons, highlights).
    /// (Màu nhấn chính — nút, điểm nhấn.)
    public var accentColor: Color

    /// Secondary colour (badges, the active-plan indicator).
    /// (Màu phụ — nhãn, chỉ báo gói đang dùng.)
    public var secondaryColor: Color

    /// Screen background colour.
    /// (Màu nền của màn hình.)
    public var backgroundColor: Color

    /// Primary text colour.
    /// (Màu chữ chính.)
    public var textPrimaryColor: Color

    /// Secondary text colour.
    /// (Màu chữ phụ.)
    public var textSecondaryColor: Color

    /// Muted text colour (legal disclaimers, footnotes).
    /// (Màu chữ mờ — điều khoản, chú thích.)
    public var textMutedColor: Color

    /// Card background colour.
    /// (Màu nền thẻ.)
    public var cardColor: Color

    /// Card background in the selected state.
    /// (Màu nền thẻ khi được chọn.)
    public var cardLightColor: Color

    /// Gradient for the CTA button and the crown icon.
    /// (Gradient cho nút CTA và icon vương miện.)
    public var premiumGradient: LinearGradient

    /// Preferred colour scheme. `nil` follows the system.
    /// (Giao diện sáng/tối ưu tiên. `nil` sẽ theo hệ thống.)
    public var preferredColorScheme: ColorScheme?

    // MARK: - Init

    public init(
        appName: String = "Premium",
        features: [Feature] = [
            Feature(icon: "sparkles", title: NSLocalizedString("Feature One", comment: ""), subtitle: NSLocalizedString("Unlock unlimited access to Feature One", comment: "")),
            Feature(icon: "bolt.fill", title: NSLocalizedString("Feature Two", comment: ""), subtitle: NSLocalizedString("Get 10x faster processing times", comment: "")),
            Feature(icon: "cloud.fill", title: NSLocalizedString("Feature Three", comment: ""), subtitle: NSLocalizedString("Sync data seamlessly in the cloud", comment: ""))
        ],
        offeringIdentifier: String? = nil,
        entitlementId: String? = nil,
        showRedeemCodeButton: Bool = true,
        showSavingsBadge: Bool = true,
        showPricePerMonth: Bool = true,
        privacyURL: URL? = nil,
        termsURL: URL? = nil,
        accentColor: Color = .cyan,
        secondaryColor: Color = .purple,
        backgroundColor: Color = .black,
        textPrimaryColor: Color = .white,
        textSecondaryColor: Color = .gray,
        textMutedColor: Color = Color.gray.opacity(0.7),
        cardColor: Color = Color(red: 0.1, green: 0.1, blue: 0.1),
        cardLightColor: Color = Color(red: 0.15, green: 0.15, blue: 0.15),
        premiumGradient: LinearGradient = LinearGradient(
            colors: [Color(red: 0.83, green: 0.69, blue: 0.22), Color(red: 0.64, green: 0.49, blue: 0.23)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        preferredColorScheme: ColorScheme? = .dark
    ) {
        self.appName = appName
        self.features = features
        self.offeringIdentifier = offeringIdentifier
        self.entitlementId = entitlementId
        self.showRedeemCodeButton = showRedeemCodeButton
        self.showSavingsBadge = showSavingsBadge
        self.showPricePerMonth = showPricePerMonth
        self.privacyURL = privacyURL
        self.termsURL = termsURL
        self.accentColor = accentColor
        self.secondaryColor = secondaryColor
        self.backgroundColor = backgroundColor
        self.textPrimaryColor = textPrimaryColor
        self.textSecondaryColor = textSecondaryColor
        self.textMutedColor = textMutedColor
        self.cardColor = cardColor
        self.cardLightColor = cardLightColor
        self.premiumGradient = premiumGradient
        self.preferredColorScheme = preferredColorScheme
    }
}
