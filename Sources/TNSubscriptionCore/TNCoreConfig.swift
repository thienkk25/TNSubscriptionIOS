import Foundation

// MARK: - TNEntitlement

/// A single entitlement definition with its associated StoreKit Product IDs.
///
/// In the RevenueCat-backed target an entitlement is a dashboard concept and the SDK
/// tells you whether it is active. Here there is no dashboard: an entitlement is purely
/// a **local grouping of product IDs**, and it is active when the Apple ID owns a
/// verified, unexpired transaction for any product in the set.
/// (Ở target dùng RevenueCat, entitlement là khái niệm trên dashboard và SDK cho bạn biết nó
/// có đang hoạt động không. Ở đây không có dashboard: entitlement chỉ đơn giản là **một nhóm
/// product ID cục bộ**, và nó hoạt động khi Apple ID sở hữu một giao dịch đã xác minh, còn hạn,
/// của bất kỳ sản phẩm nào trong nhóm.)
///
/// ```swift
/// TNEntitlement(id: "Premium", productIDs: ["com.app.weekly", "com.app.yearly"])
/// TNEntitlement(id: "Sale", productIDs: ["com.app.sale_yearly"])
/// ```
public struct TNEntitlement: Hashable, Sendable {
    /// The entitlement identifier (e.g. "Premium"). Chosen by you; nothing has to match a server.
    /// (ID của quyền lợi, ví dụ "Premium". Bạn tự chọn; không cần khớp với bất cứ server nào.)
    public let id: String

    /// The set of StoreKit Product IDs that grant this entitlement.
    /// (Tập các Product ID của StoreKit cấp quyền lợi này.)
    public let productIDs: Set<String>

    public init(id: String, productIDs: Set<String>) {
        self.id = id
        self.productIDs = productIDs
    }
}

// MARK: - TNOffering

/// An ordered group of products to display on a paywall.
///
/// This is the local replacement for a RevenueCat Offering. Because there is no dashboard,
/// offerings are declared in code (or swapped at runtime via
/// `TNSubscriptionCore.shared.updateOfferings(_:current:)` once you fetch them from your
/// own backend / remote config).
/// (Đây là bản thay thế cục bộ cho Offering của RevenueCat. Vì không có dashboard, offering được
/// khai báo trong code — hoặc đổi lúc runtime qua `TNSubscriptionCore.shared.updateOfferings(_:current:)`
/// sau khi bạn lấy chúng từ backend / remote config của mình.)
///
/// ```swift
/// TNOffering(identifier: "default", productIDs: ["com.app.weekly", "com.app.yearly"])
/// TNOffering(identifier: "sale",    productIDs: ["com.app.sale_yearly"])
/// ```
public struct TNOffering: Hashable, Sendable {
    /// The offering identifier (e.g. `"default"`, `"sale"`, `"black_friday"`).
    /// (ID của offering, ví dụ `"default"`, `"sale"`, `"black_friday"`.)
    public let identifier: String

    /// The product IDs in this offering. Display order is derived from the
    /// subscription period unless `preserveOrder` is `true`.
    /// (Các product ID trong offering này. Thứ tự hiển thị suy ra từ kỳ hạn subscription,
    /// trừ khi `preserveOrder` là `true`.)
    public let productIDs: [String]

    /// When `true`, packages are shown in exactly the order given here instead of being
    /// sorted longest-period-first. Defaults to `false`.
    /// (Nếu `true`, các gói hiển thị đúng theo thứ tự khai báo ở đây thay vì sắp xếp kỳ hạn
    /// dài nhất trước. Mặc định `false`.)
    public let preserveOrder: Bool

    /// Free-form metadata, e.g. a headline or a badge label for your paywall.
    /// (Metadata tự do, ví dụ tiêu đề hoặc nhãn badge cho paywall của bạn.)
    public let metadata: [String: String]

    public init(
        identifier: String,
        productIDs: [String],
        preserveOrder: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.productIDs = productIDs
        self.preserveOrder = preserveOrder
        self.metadata = metadata
    }
}

// MARK: - TNSubscriptionConfig

/// Configuration for the TNSubscriptionCore engine.
///
/// Host apps must call `TNSubscriptionCore.configure(config:)` before using any functionality.
///
/// Compared with the RevenueCat-backed target there is **no `apiKey`**: this engine talks only
/// to Apple, so there is nothing to authenticate against.
/// (So với target dùng RevenueCat, ở đây **không có `apiKey`**: engine này chỉ nói chuyện với
/// Apple, nên không có gì cần xác thực.)
///
/// ```swift
/// TNSubscriptionCore.configure(config: TNSubscriptionConfig(
///     entitlements: [
///         TNEntitlement(id: "Premium", productIDs: ["com.app.weekly", "com.app.monthly", "com.app.yearly"]),
///         TNEntitlement(id: "Sale", productIDs: ["com.app.sale_yearly"]),
///     ]
/// ))
/// ```
public struct TNSubscriptionConfig: Sendable {

    /// The entitlements this app sells, each mapped to its StoreKit product IDs.
    /// (Các quyền lợi app này bán, mỗi quyền lợi gắn với các product ID StoreKit của nó.)
    public let entitlements: [TNEntitlement]

    /// Paywall offerings. When empty, a single offering named `"default"` is synthesised
    /// from every configured product ID, so a minimal config still drives the built-in paywall.
    /// (Các offering cho paywall. Nếu để trống, một offering tên `"default"` sẽ được tự sinh từ
    /// toàn bộ product ID đã cấu hình, nên một config tối giản vẫn chạy được paywall có sẵn.)
    public let offerings: [TNOffering]

    /// The offering shown when no explicit identifier is requested.
    /// When `nil`, the first entry of `offerings` (or the synthesised `"default"`) is used.
    /// (Offering được hiển thị khi không chỉ định ID cụ thể. Nếu `nil`, dùng phần tử đầu của
    /// `offerings` — hoặc offering `"default"` được tự sinh.)
    public let currentOfferingIdentifier: String?

    /// Set to `false` to unlock everything without any purchase — e.g. for a free/enterprise
    /// build, or while in-app purchases are not yet approved. Defaults to `true`.
    /// (Đặt `false` để mở khoá mọi thứ mà không cần mua — ví dụ bản free/enterprise, hoặc khi
    /// in-app purchase chưa được duyệt. Mặc định `true`.)
    public let isIAPEnabled: Bool

    /// When `true`, each purchase carries `clientId` as the StoreKit `appAccountToken`, which
    /// is echoed back in App Store Server Notifications and lets your backend tie a transaction
    /// to a user without any vendor SDK. Requires `clientId` to be a valid UUID (it is, by default).
    /// Defaults to `false`.
    /// (Nếu `true`, mỗi giao dịch sẽ mang `clientId` làm `appAccountToken` của StoreKit. Giá trị này
    /// được Apple gửi lại trong App Store Server Notifications, giúp backend của bạn gắn giao dịch
    /// với một user mà không cần SDK bên thứ ba. Yêu cầu `clientId` là UUID hợp lệ — mặc định là vậy.
    /// Mặc định `false`.)
    public let attachAppAccountToken: Bool

    /// Diagnostic verbosity. Defaults to `.info` in DEBUG builds and `.error` in Release builds.
    /// (Mức độ log. Mặc định `.info` khi build DEBUG và `.error` khi build Release.)
    public let logLevel: TNLogLevel

    /// Every product ID across all configured entitlements.
    /// (Mọi product ID trong tất cả quyền lợi đã cấu hình.)
    public var allProductIDs: Set<String> {
        entitlements.reduce(into: Set<String>()) { $0.formUnion($1.productIDs) }
    }

    /// Every configured entitlement ID.
    /// (Mọi ID quyền lợi đã cấu hình.)
    public var allEntitlementIDs: [String] {
        entitlements.map(\.id)
    }

    /// Every product ID the engine needs to load from the App Store: the entitlement
    /// products plus anything referenced only by an offering.
    /// (Mọi product ID engine cần tải từ App Store: sản phẩm của các quyền lợi, cộng thêm những
    /// sản phẩm chỉ được một offering tham chiếu tới.)
    public var allLoadableProductIDs: Set<String> {
        var ids = allProductIDs
        for offering in resolvedOfferings {
            ids.formUnion(offering.productIDs)
        }
        return ids
    }

    /// `offerings` as given, or a synthesised `"default"` offering when none were declared.
    /// (`offerings` như đã khai báo, hoặc một offering `"default"` tự sinh nếu chưa khai báo gì.)
    public var resolvedOfferings: [TNOffering] {
        guard offerings.isEmpty else { return offerings }
        let ids = allProductIDs.sorted()
        guard !ids.isEmpty else { return [] }
        return [TNOffering(identifier: "default", productIDs: ids)]
    }

    public init(
        entitlements: [TNEntitlement],
        offerings: [TNOffering] = [],
        currentOfferingIdentifier: String? = nil,
        isIAPEnabled: Bool = true,
        attachAppAccountToken: Bool = false,
        logLevel: TNLogLevel = .default
    ) {
        self.entitlements = entitlements
        self.offerings = offerings
        self.currentOfferingIdentifier = currentOfferingIdentifier
        self.isIAPEnabled = isIAPEnabled
        self.attachAppAccountToken = attachAppAccountToken
        self.logLevel = logLevel
    }

    /// Convenience initialiser for the single-entitlement case.
    /// (Khởi tạo tiện lợi cho trường hợp chỉ có một quyền lợi.)
    ///
    /// ```swift
    /// TNSubscriptionConfig(entitlementId: "Premium", productIDs: ["com.app.weekly", "com.app.yearly"])
    /// ```
    public init(
        entitlementId: String = "Premium",
        productIDs: Set<String>,
        offerings: [TNOffering] = [],
        currentOfferingIdentifier: String? = nil,
        isIAPEnabled: Bool = true,
        attachAppAccountToken: Bool = false,
        logLevel: TNLogLevel = .default
    ) {
        self.init(
            entitlements: [TNEntitlement(id: entitlementId, productIDs: productIDs)],
            offerings: offerings,
            currentOfferingIdentifier: currentOfferingIdentifier,
            isIAPEnabled: isIAPEnabled,
            attachAppAccountToken: attachAppAccountToken,
            logLevel: logLevel
        )
    }
}
