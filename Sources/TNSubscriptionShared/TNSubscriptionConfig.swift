import Foundation

// MARK: - TNEntitlement

/// One entitlement and the StoreKit product IDs that grant it — the same type in every engine.
/// (Một quyền lợi và các product ID StoreKit cấp quyền đó — cùng một kiểu ở mọi engine.)
///
/// ```swift
/// TNEntitlement(id: "Premium", productIDs: ["com.app.weekly", "com.app.yearly"])
/// ```
///
/// What `id` names depends on the engine, and must match it **exactly**, including case:
/// (`id` trỏ tới gì tuỳ engine, và phải khớp **chính xác**, kể cả chữ hoa/thường:)
///
/// | Engine | `id` is | `productIDs` are used for |
/// |---|---|---|
/// | `TNSubscriptionIOS` | RevenueCat entitlement ID | StoreKit-first unlock, offline |
/// | `TNSubscriptionAdapty` | Adapty access level ID | offline fallback |
/// | `TNSubscriptionCore` | your own name | everything — they are the only mapping |
public struct TNEntitlement: Hashable, Sendable {
    /// The entitlement ID. (ID của quyền lợi.)
    public let id: String

    /// StoreKit product IDs that grant this entitlement.
    /// (Các product ID StoreKit cấp quyền lợi này.)
    public let productIDs: Set<String>

    public init(id: String, productIDs: Set<String> = []) {
        self.id = id
        self.productIDs = productIDs
    }
}

// MARK: - TNOffering

/// An ordered group of products for a paywall, declared in code.
/// (Một nhóm sản phẩm có thứ tự cho paywall, khai báo trong code.)
///
/// Only `TNSubscriptionCore` reads these: RevenueCat and Adapty serve offerings from their
/// dashboards, and those engines log a warning if you pass any.
/// (Chỉ `TNSubscriptionCore` đọc phần này: RevenueCat và Adapty lấy offering từ dashboard của họ,
/// và hai engine đó sẽ ghi cảnh báo nếu bạn truyền vào.)
public struct TNOffering: Hashable, Sendable {
    /// The offering identifier, e.g. `"default"`, `"sale"`. (ID của offering.)
    public let identifier: String

    /// The product IDs in this offering. (Các product ID trong offering.)
    public let productIDs: [String]

    /// Keep the declared order instead of sorting longest-period-first.
    /// (Giữ thứ tự đã khai báo thay vì sắp xếp kỳ hạn dài nhất trước.)
    public let preserveOrder: Bool

    /// Free-form metadata, e.g. a headline. (Metadata tự do, ví dụ tiêu đề.)
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

/// The one configuration type, identical across all three engines.
/// (Kiểu cấu hình duy nhất, giống hệt nhau ở cả ba engine.)
///
/// Switching engine means changing the `import` — this value does not change:
/// (Đổi engine nghĩa là đổi `import` — giá trị này không đổi:)
///
/// ```swift
/// import TNSubscriptionAdapty   // or TNSubscriptionIOS, or TNSubscriptionCore
///
/// TNSubscription.configure(config: TNSubscriptionConfig(
///     apiKey: "public_live_xxxxx",
///     entitlements: [TNEntitlement(id: "premium", productIDs: ["com.app.weekly", "com.app.yearly"])],
///     currentOfferingIdentifier: "main"
/// ))
/// ```
///
/// Every engine accepts every field. A field an engine cannot use is ignored, and the engine
/// logs a warning naming it at `configure` — so a setting never silently does nothing.
/// (Mọi engine đều nhận mọi trường. Trường nào engine không dùng được sẽ bị bỏ qua, và engine ghi
/// cảnh báo nêu rõ tên trường đó lúc `configure` — để không có thiết lập nào âm thầm vô tác dụng.)
///
/// | Field | RevenueCat | Adapty | Core |
/// |---|---|---|---|
/// | `apiKey` | ✅ `appl_…` | ✅ `public_live_…` | — |
/// | `entitlements` | ✅ | ✅ | ✅ |
/// | `offerings` | — dashboard | — dashboard | ✅ |
/// | `currentOfferingIdentifier` | ✅ offering ID | ✅ placement ID | ✅ |
/// | `customerUserId` | ✅ | ✅ | — |
/// | `isIAPEnabled` | ✅ | ✅ | ✅ |
/// | `enableBackendIdentitySync` | ✅ | — | — |
/// | `observerMode` | — | ✅ | — |
/// | `attachAppAccountToken` | — | ✅ | ✅ |
/// | `offlineStoreKitFallback` | always on | ✅ | always on |
/// | `logLevel` | ✅ | ✅ | ✅ |
public struct TNSubscriptionConfig: Sendable {

    /// The vendor SDK key. RevenueCat: `appl_…`. Adapty: `public_live_…`. Core: unused.
    /// (Key SDK của nhà cung cấp. RevenueCat: `appl_…`. Adapty: `public_live_…`. Core: không dùng.)
    public let apiKey: String

    /// The entitlements this app sells. (Các quyền lợi app này bán.)
    public let entitlements: [TNEntitlement]

    /// Paywall offerings declared in code — read by `TNSubscriptionCore` only. When empty, Core
    /// synthesises a `"default"` offering from every product ID.
    /// (Các offering khai báo trong code — chỉ `TNSubscriptionCore` đọc. Nếu để trống, Core tự sinh
    /// offering `"default"` từ mọi product ID.)
    public let offerings: [TNOffering]

    /// The offering shown when a paywall does not name one. RevenueCat: an offering ID (`nil` uses
    /// the dashboard's *current* offering). Adapty: a **placement ID**. Core: a `TNOffering` ID.
    /// (Offering hiển thị khi paywall không chỉ định. RevenueCat: offering ID (`nil` dùng offering
    /// *current* trên dashboard). Adapty: **placement ID**. Core: ID của `TNOffering`.)
    public let currentOfferingIdentifier: String?

    /// Your own user ID, to tie the vendor profile to an account. `nil` keeps the user anonymous.
    /// (User ID của bạn, để gắn profile của nhà cung cấp với một tài khoản. `nil` giữ ẩn danh.)
    public let customerUserId: String?

    /// `false` unlocks everything with no purchase and skips the vendor SDK. Never ship it.
    /// (`false` mở khoá mọi thứ không cần mua và bỏ qua SDK của nhà cung cấp. Đừng phát hành như vậy.)
    public let isIAPEnabled: Bool

    /// RevenueCat only: sync the Keychain `client_id` to RevenueCat at launch, for apps with
    /// their own backend or proxy.
    /// (Chỉ RevenueCat: đồng bộ `client_id` trong Keychain lên RevenueCat khi khởi động, cho app có
    /// backend hoặc proxy riêng.)
    public let enableBackendIdentitySync: Bool

    /// Adapty only: observe purchases made by your own StoreKit code instead of making them.
    /// (Chỉ Adapty: quan sát giao dịch do code StoreKit của bạn thực hiện thay vì tự thực hiện.)
    public let observerMode: Bool

    /// Send the Keychain `client_id` as StoreKit's `appAccountToken`, so App Store Server
    /// Notifications can be attributed to the user. Adapty and Core.
    /// (Gửi `client_id` trong Keychain làm `appAccountToken` của StoreKit, để App Store Server
    /// Notifications quy được về người dùng. Adapty và Core.)
    public let attachAppAccountToken: Bool

    /// When the vendor server is unreachable, unlock from Apple's local transactions. Only Adapty
    /// lets you turn this off; RevenueCat and Core always use local StoreKit.
    /// (Khi không kết nối được server của nhà cung cấp, mở khoá từ giao dịch cục bộ của Apple. Chỉ
    /// Adapty cho phép tắt; RevenueCat và Core luôn dùng StoreKit cục bộ.)
    public let offlineStoreKitFallback: Bool

    /// Diagnostic verbosity, for this package and the vendor SDK.
    /// (Mức độ log, cho package này và SDK của nhà cung cấp.)
    public let logLevel: TNLogLevel

    // MARK: Derived

    /// Every product ID across all entitlements. (Mọi product ID trong tất cả quyền lợi.)
    public var allProductIDs: Set<String> {
        entitlements.reduce(into: Set<String>()) { $0.formUnion($1.productIDs) }
    }

    /// Every entitlement ID. (Mọi ID quyền lợi.)
    public var allEntitlementIDs: [String] {
        entitlements.map(\.id)
    }

    /// `offerings` as given, or a synthesised `"default"` offering when none were declared.
    /// (`offerings` như đã khai báo, hoặc offering `"default"` tự sinh nếu chưa khai báo.)
    public var resolvedOfferings: [TNOffering] {
        guard offerings.isEmpty else { return offerings }
        let ids = allProductIDs.sorted()
        guard !ids.isEmpty else { return [] }
        return [TNOffering(identifier: "default", productIDs: ids)]
    }

    /// Every product ID that must be loaded: entitlement products plus offering-only ones.
    /// (Mọi product ID cần tải: sản phẩm của quyền lợi cộng sản phẩm chỉ có trong offering.)
    public var allLoadableProductIDs: Set<String> {
        resolvedOfferings.reduce(into: allProductIDs) { $0.formUnion($1.productIDs) }
    }

    // MARK: Init

    /// The full initialiser. Parameter order matches 1.2.0, so existing RevenueCat and Core
    /// call sites compile unchanged.
    /// (Initializer đầy đủ. Thứ tự tham số khớp với 1.2.0, nên code RevenueCat và Core đang có vẫn
    /// compile mà không phải sửa.)
    public init(
        apiKey: String = "",
        entitlements: [TNEntitlement],
        offerings: [TNOffering] = [],
        currentOfferingIdentifier: String? = nil,
        customerUserId: String? = nil,
        isIAPEnabled: Bool = true,
        enableBackendIdentitySync: Bool = false,
        observerMode: Bool = false,
        attachAppAccountToken: Bool = false,
        offlineStoreKitFallback: Bool = true,
        logLevel: TNLogLevel = .default
    ) {
        self.apiKey = apiKey
        self.entitlements = entitlements
        self.offerings = offerings
        self.currentOfferingIdentifier = currentOfferingIdentifier
        self.customerUserId = customerUserId
        self.isIAPEnabled = isIAPEnabled
        self.enableBackendIdentitySync = enableBackendIdentitySync
        self.observerMode = observerMode
        self.attachAppAccountToken = attachAppAccountToken
        self.offlineStoreKitFallback = offlineStoreKitFallback
        self.logLevel = logLevel
    }

    /// Convenience initialiser for a single entitlement.
    /// (Initializer tiện lợi cho trường hợp chỉ có một quyền lợi.)
    ///
    /// The default ID is `"Premium"`, as in 1.2.0. Adapty's own default access level is lowercase
    /// `"premium"`, so Adapty apps should pass `entitlementId:` explicitly.
    /// (ID mặc định là `"Premium"`, như ở 1.2.0. Access level mặc định của Adapty là `"premium"` viết
    /// thường, nên app dùng Adapty nên truyền `entitlementId:` tường minh.)
    public init(
        apiKey: String = "",
        entitlementId: String = "Premium",
        productIDs: Set<String>,
        offerings: [TNOffering] = [],
        currentOfferingIdentifier: String? = nil,
        customerUserId: String? = nil,
        isIAPEnabled: Bool = true,
        enableBackendIdentitySync: Bool = false,
        observerMode: Bool = false,
        attachAppAccountToken: Bool = false,
        offlineStoreKitFallback: Bool = true,
        logLevel: TNLogLevel = .default
    ) {
        self.init(
            apiKey: apiKey,
            entitlements: [TNEntitlement(id: entitlementId, productIDs: productIDs)],
            offerings: offerings,
            currentOfferingIdentifier: currentOfferingIdentifier,
            customerUserId: customerUserId,
            isIAPEnabled: isIAPEnabled,
            enableBackendIdentitySync: enableBackendIdentitySync,
            observerMode: observerMode,
            attachAppAccountToken: attachAppAccountToken,
            offlineStoreKitFallback: offlineStoreKitFallback,
            logLevel: logLevel
        )
    }
}

// MARK: - Engine Support

/// Which engine is reading the config. (Engine nào đang đọc config.)
package enum TNEngineKind: Sendable {
    case revenueCat, adapty, storeKit

    package var displayName: String {
        switch self {
        case .revenueCat: return "TNSubscriptionIOS (RevenueCat)"
        case .adapty: return "TNSubscriptionAdapty (Adapty)"
        case .storeKit: return "TNSubscriptionCore (StoreKit 2)"
        }
    }
}

extension TNSubscriptionConfig {

    /// Settings this config sets that `engine` cannot honour, as readable warnings.
    /// (Các thiết lập trong config mà `engine` không áp dụng được, dưới dạng cảnh báo dễ đọc.)
    ///
    /// Only non-default values are reported, so a config written for one engine produces no noise
    /// on another unless it actually relies on something that engine lacks.
    /// (Chỉ báo các giá trị khác mặc định, nên một config viết cho engine này sẽ không gây nhiễu ở
    /// engine khác trừ khi nó thực sự dựa vào thứ engine đó không có.)
    package func ignoredSettings(for engine: TNEngineKind) -> [String] {
        var ignored: [String] = []
        let name = engine.displayName
        let hasKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        switch engine {
        case .storeKit:
            if hasKey { ignored.append("apiKey is ignored by \(name): it talks only to Apple.") }
            if customerUserId != nil { ignored.append("customerUserId is ignored by \(name): there is no vendor profile to identify.") }
            if enableBackendIdentitySync { ignored.append("enableBackendIdentitySync is ignored by \(name): it is a RevenueCat feature.") }
            if observerMode { ignored.append("observerMode is ignored by \(name): it is an Adapty feature.") }
            if !offlineStoreKitFallback { ignored.append("offlineStoreKitFallback = false is ignored by \(name): local StoreKit is its only source.") }
        case .revenueCat:
            if !offerings.isEmpty { ignored.append("offerings are ignored by \(name): offerings come from the RevenueCat dashboard.") }
            if observerMode { ignored.append("observerMode is ignored by \(name): it is an Adapty feature.") }
            if attachAppAccountToken { ignored.append("attachAppAccountToken is ignored by \(name).") }
            if !offlineStoreKitFallback { ignored.append("offlineStoreKitFallback = false is ignored by \(name): it always checks local StoreKit first.") }
        case .adapty:
            if !offerings.isEmpty { ignored.append("offerings are ignored by \(name): offerings are Adapty placements, configured in the dashboard.") }
            if enableBackendIdentitySync { ignored.append("enableBackendIdentitySync is ignored by \(name): it is a RevenueCat feature.") }
        }
        return ignored
    }
}
