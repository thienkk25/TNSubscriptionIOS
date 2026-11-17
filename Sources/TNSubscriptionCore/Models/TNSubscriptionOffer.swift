import Foundation
import StoreKit

// MARK: - TNIntroEligibilityStatus

/// Whether the user may claim a product's introductory offer / free trial.
/// (Người dùng có đủ điều kiện nhận ưu đãi người mới / dùng thử miễn phí hay không.)
///
/// StoreKit 2 answers this exactly, per **subscription group**, from the Apple ID's own
/// purchase history — no server call and no vendor SDK involved.
/// (StoreKit 2 trả lời chính xác câu hỏi này theo từng **subscription group**, dựa trên
/// lịch sử mua của Apple ID — không cần gọi server, không cần SDK của bên thứ ba.)
public enum TNIntroEligibilityStatus: String, Hashable, Sendable {
    /// Eligibility has not been determined yet (products still loading).
    /// (Chưa xác định được — sản phẩm vẫn đang tải.)
    case unknown
    /// The user may claim the introductory offer.
    /// (Người dùng đủ điều kiện nhận ưu đãi người mới.)
    case eligible
    /// The user has already used the introductory offer for this subscription group.
    /// (Người dùng đã dùng ưu đãi người mới của group này rồi.)
    case ineligible
    /// This product has no introductory offer configured in App Store Connect.
    /// (Sản phẩm này không có ưu đãi người mới nào được cấu hình trên App Store Connect.)
    case noIntroOfferExists
}

// MARK: - TNOfferPaymentMode

/// How an offer charges the user.
/// (Cách ưu đãi thu phí người dùng.)
public enum TNOfferPaymentMode: String, Hashable, Sendable {
    /// Free for the offer period.
    /// (Miễn phí trong thời gian ưu đãi.)
    case freeTrial
    /// A reduced price charged once up front for the whole offer period.
    /// (Trả trước một lần với giá giảm cho toàn bộ thời gian ưu đãi.)
    case payUpFront
    /// A reduced price charged each period, for a number of periods.
    /// (Trả giá giảm theo từng kỳ, trong một số kỳ nhất định.)
    case payAsYouGo

    init?(_ mode: Product.SubscriptionOffer.PaymentMode) {
        switch mode {
        case .freeTrial: self = .freeTrial
        case .payUpFront: self = .payUpFront
        case .payAsYouGo: self = .payAsYouGo
        default: return nil
        }
    }
}

// MARK: - TNOfferType

/// Which kind of discount an offer is.
/// (Loại ưu đãi.)
public enum TNOfferType: String, Hashable, Sendable {
    /// For users who never subscribed in this group. Applied automatically by StoreKit.
    /// (Dành cho người chưa từng đăng ký trong group này. StoreKit tự áp dụng.)
    case introductory
    /// For existing or lapsed subscribers. **Requires a server-signed signature.**
    /// (Dành cho người đang/đã từng đăng ký. **Bắt buộc có chữ ký từ server.**)
    case promotional
    /// Redeemed by the user through Apple's Offer Code sheet.
    /// (Người dùng tự nhập qua bảng Offer Code của Apple.)
    case offerCode
    /// iOS 18+: targets users who cancelled, surfaced by Apple itself.
    /// (iOS 18+: nhắm tới người đã huỷ, do Apple tự hiển thị.)
    case winBack
}

// MARK: - TNSubscriptionOffer

/// A discount available on a subscription product.
/// (Một ưu đãi giảm giá áp dụng cho sản phẩm subscription.)
///
/// The local replacement for RevenueCat's `StoreProductDiscount`, wrapping
/// `Product.SubscriptionOffer`.
/// (Bản thay thế cục bộ cho `StoreProductDiscount` của RevenueCat, bọc quanh
/// `Product.SubscriptionOffer`.)
public struct TNSubscriptionOffer: Identifiable, Hashable, Sendable {

    /// The offer identifier from App Store Connect. `nil` for introductory offers,
    /// which Apple allows only one of per subscription group.
    /// (ID của ưu đãi trên App Store Connect. `nil` với ưu đãi người mới, vì Apple chỉ
    /// cho phép một ưu đãi người mới cho mỗi subscription group.)
    public let offerIdentifier: String?

    /// The product this offer belongs to.
    /// (Sản phẩm mà ưu đãi này thuộc về.)
    public let productIdentifier: String

    /// Which kind of discount this is.
    /// (Loại ưu đãi.)
    public let type: TNOfferType

    /// How the user is charged during the offer.
    /// (Cách thu phí trong thời gian ưu đãi.)
    public let paymentMode: TNOfferPaymentMode

    /// The offer price. `0` for a free trial.
    /// (Giá của ưu đãi. Bằng `0` nếu là dùng thử miễn phí.)
    public let price: Decimal

    /// The offer price formatted in the store's currency (e.g. `"$0.99"`).
    /// (Giá ưu đãi đã định dạng theo tiền tệ của store, ví dụ `"0,99 $"`.)
    public let localizedPriceString: String

    /// The length of one offer period.
    /// (Độ dài của một kỳ ưu đãi.)
    public let period: Product.SubscriptionPeriod

    /// How many times the offer period repeats (always `1` except for `payAsYouGo`).
    /// (Số kỳ ưu đãi được lặp lại — luôn là `1`, trừ trường hợp `payAsYouGo`.)
    public let periodCount: Int

    /// The underlying StoreKit offer, in case you need a field this struct does not expose.
    /// (Đối tượng StoreKit gốc, dùng khi bạn cần một thuộc tính mà struct này chưa expose.)
    public let storeKitOffer: Product.SubscriptionOffer

    public var id: String { "\(productIdentifier):\(type.rawValue):\(offerIdentifier ?? "intro")" }

    /// A localised summary such as `"3 Days Free Trial"` or `"$0.99 for 1 Month"`.
    /// (Mô tả đã dịch, ví dụ `"Dùng thử miễn phí 3 Ngày"` hoặc `"0,99 $ trong 1 Tháng"`.)
    public var localizedSummary: String {
        let periodText = period.localizedDescription(numberOfPeriods: periodCount)
        switch paymentMode {
        case .freeTrial:
            return String(format: NSLocalizedString("%@ Free Trial", comment: ""), periodText)
        case .payAsYouGo, .payUpFront:
            return String(format: NSLocalizedString("%@ for %@", comment: ""), localizedPriceString, periodText)
        }
    }

    init?(storeKitOffer: Product.SubscriptionOffer, product: Product) {
        guard let paymentMode = TNOfferPaymentMode(storeKitOffer.paymentMode) else { return nil }

        // Note: there is no `.code` case here. An offer code is not configured on the
        // product — it only ever appears on a *transaction*, after the user redeems it.
        let resolvedType: TNOfferType
        switch storeKitOffer.type {
        case .introductory:
            resolvedType = .introductory
        case .promotional:
            resolvedType = .promotional
        default:
            if #available(iOS 18.0, *), storeKitOffer.type == .winBack {
                resolvedType = .winBack
            } else {
                return nil
            }
        }

        self.storeKitOffer = storeKitOffer
        self.productIdentifier = product.id
        self.offerIdentifier = storeKitOffer.id
        self.type = resolvedType
        self.paymentMode = paymentMode
        self.price = storeKitOffer.price
        self.localizedPriceString = storeKitOffer.displayPrice
        self.period = storeKitOffer.period
        self.periodCount = storeKitOffer.periodCount
    }

    public static func == (lhs: TNSubscriptionOffer, rhs: TNSubscriptionOffer) -> Bool {
        lhs.id == rhs.id && lhs.price == rhs.price
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Promotional Offer Signing

/// Everything your server needs in order to sign a promotional offer.
/// (Tất cả thông tin server của bạn cần để ký một promotional offer.)
///
/// Apple requires promotional offers to be signed with your **Subscription Key (.p8)**.
/// That private key must never ship inside the app, so this engine cannot sign on its own —
/// it hands you this request and expects a signature back.
/// (Apple yêu cầu promotional offer phải được ký bằng **Subscription Key (.p8)** của bạn.
/// Private key đó tuyệt đối không được nhúng trong app, nên engine này không thể tự ký —
/// nó đưa cho bạn request này và chờ nhận lại chữ ký.)
public struct TNPromotionalOfferSignatureRequest: Hashable, Sendable {
    /// The app's bundle ID.
    /// (Bundle ID của app.)
    public let bundleIdentifier: String
    /// The product the offer applies to.
    /// (Sản phẩm mà ưu đãi áp dụng cho.)
    public let productIdentifier: String
    /// The offer identifier from App Store Connect.
    /// (ID của ưu đãi trên App Store Connect.)
    public let offerIdentifier: String
    /// The persistent client ID, to pass as Apple's `applicationUsername`.
    /// (Client ID cố định, dùng làm `applicationUsername` của Apple.)
    public let applicationUsername: String

    public init(
        bundleIdentifier: String,
        productIdentifier: String,
        offerIdentifier: String,
        applicationUsername: String
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.productIdentifier = productIdentifier
        self.offerIdentifier = offerIdentifier
        self.applicationUsername = applicationUsername
    }
}

/// The signature your server returns for a promotional offer.
/// (Chữ ký mà server của bạn trả về cho một promotional offer.)
///
/// Generate it as described in Apple's "Generating a signature for promotional offers":
/// sign `appBundleID + '\u{2063}' + keyID + '\u{2063}' + productID + '\u{2063}' + offerID +
/// '\u{2063}' + applicationUsername + '\u{2063}' + nonce + '\u{2063}' + timestamp`
/// with ECDSA-SHA256 using your .p8 subscription key.
/// (Tạo chữ ký theo tài liệu "Generating a signature for promotional offers" của Apple:
/// ký chuỗi trên bằng ECDSA-SHA256 với .p8 subscription key của bạn.)
public struct TNPromotionalOfferSignature: Hashable, Sendable {
    /// The key ID of the .p8 subscription key used to sign.
    /// (Key ID của .p8 subscription key dùng để ký.)
    public let keyID: String
    /// The nonce your server generated, lowercase UUID.
    /// (Nonce do server sinh ra, dạng UUID chữ thường.)
    public let nonce: UUID
    /// The Unix timestamp in **milliseconds** used in the signed payload.
    /// (Unix timestamp tính theo **milliseconds**, dùng trong payload đã ký.)
    public let timestamp: Int
    /// The raw ECDSA-SHA256 signature bytes.
    /// (Chuỗi byte chữ ký ECDSA-SHA256.)
    public let signature: Data

    public init(keyID: String, nonce: UUID, timestamp: Int, signature: Data) {
        self.keyID = keyID
        self.nonce = nonce
        self.timestamp = timestamp
        self.signature = signature
    }

    /// Convenience initialiser for a Base64-encoded signature, which is how most
    /// backends return it over JSON.
    /// (Khởi tạo tiện lợi cho chữ ký dạng Base64 — cách phần lớn backend trả về qua JSON.)
    public init?(keyID: String, nonce: String, timestamp: Int, base64Signature: String) {
        guard let nonceUUID = UUID(uuidString: nonce),
              let data = Data(base64Encoded: base64Signature) else { return nil }
        self.init(keyID: keyID, nonce: nonceUUID, timestamp: timestamp, signature: data)
    }
}

/// Asks your backend to sign a promotional offer.
/// (Yêu cầu backend của bạn ký một promotional offer.)
public typealias TNPromotionalOfferSigner = @Sendable (TNPromotionalOfferSignatureRequest) async throws -> TNPromotionalOfferSignature
