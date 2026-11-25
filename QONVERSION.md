# TNSubscriptionQonversion — the Qonversion-backed target (Target chạy trên Qonversion)

A fourth engine: subscriptions backed by **Qonversion** — server-validated entitlements,
cross-platform profiles and analytics. (Engine thứ tư: subscription chạy trên **Qonversion** — quyền
lợi được xác thực phía server, profile đa nền tảng và analytics.)

```swift
.product(name: "TNSubscriptionQonversion", package: "TNSubscriptionIOS")
```

The configuration is the same `TNSubscriptionConfig` as every other engine, and the entry point is
also available as `TNSubscription`. See README → "What is the same, what differs". (Cấu hình là cùng
một `TNSubscriptionConfig` như mọi engine khác, và điểm vào cũng có tên `TNSubscription`. Xem README,
mục "What is the same, what differs".)

---

## 1. Requirements (Yêu cầu)

Qonversion 6.x declares `swift-tools-version: 5.9` and iOS 13+, so it adds **no** toolchain
requirement of its own — the package as a whole still needs Xcode 26 because of Adapty.
(Qonversion 6.x khai báo `swift-tools-version: 5.9` và iOS 13+, nên **không** thêm yêu cầu toolchain
nào — cả package vẫn cần Xcode 26 vì Adapty.)

This target links **`QonversionNoIdfa`**, not the default `Qonversion` product. The default also
links an IDFA reader (AdSupport), which changes your App Store privacy answers; an app that wants
IDFA can add `QonversionIDFA` itself. (Target này link **`QonversionNoIdfa`**, không phải product
mặc định `Qonversion`. Bản mặc định link thêm phần đọc IDFA (AdSupport), làm thay đổi câu trả lời về
quyền riêng tư trên App Store; app nào cần IDFA thì tự thêm `QonversionIDFA`.)

---

## 2. Concept mapping (Bản đồ khái niệm)

| This package | Qonversion |
|---|---|
| `TNEntitlement.id` | entitlement ID in the dashboard (ID entitlement trên dashboard) |
| `TNEntitlement.productIDs` | **App Store** product IDs — offline fallback and the default offering |
| `TNOffering` / `currentOfferingIdentifier` | **declared in code** — Qonversion has deprecated its offerings |
| `TNPackage` | `Qonversion.Product` to buy + StoreKit 2 `Product` to display and price |
| `TNCustomerInfo` | `Qonversion.checkEntitlements()` |
| `observerMode: true` | `launchMode: .analytics` |

---

## 3. Setup (Cấu hình)

```swift
import TNSubscriptionQonversion

TNSubscription.configure(config: TNSubscriptionConfig(
    apiKey: "your-qonversion-project-key",
    entitlements: [
        // `id` must match the Qonversion entitlement ID exactly, including case.
        // (`id` phải khớp chính xác ID entitlement trên Qonversion, kể cả hoa/thường.)
        TNEntitlement(id: "premium", productIDs: ["com.app.weekly", "com.app.yearly"]),
    ],
    offerings: [
        TNOffering(identifier: "main", productIDs: ["com.app.weekly", "com.app.yearly"]),
    ],
    currentOfferingIdentifier: "main"
))
```

- **`apiKey`** — the Qonversion **project key**. (Project key của Qonversion.)
- **`offerings`** — optional. Leave it out and a `"default"` offering is built from every
  `productIDs`. (Không bắt buộc. Bỏ trống thì offering `"default"` được dựng từ mọi `productIDs`.)
- **Product IDs are App Store IDs**, not Qonversion's own product IDs. Every product you sell must
  also exist in the Qonversion dashboard with that App Store ID, or it cannot be bought and is left
  off the paywall with a warning. (**Product ID là ID App Store**, không phải product ID riêng của
  Qonversion. Mọi sản phẩm bạn bán phải có trên dashboard Qonversion với đúng ID App Store đó, nếu
  không thì không mua được và bị loại khỏi paywall kèm cảnh báo.)
- `enableBackendIdentitySync` and `attachAppAccountToken` are ignored here, with a warning at
  `configure`. (`enableBackendIdentitySync` và `attachAppAccountToken` bị bỏ qua ở đây, kèm cảnh báo.)

---

## 4. Offerings come from your code (Offering lấy từ code của bạn)

Qonversion has deprecated its own offerings: *"Manage paywall products with Remote Config
instead."* So unlike RevenueCat and Adapty, this engine does not fetch offerings from a dashboard.
It reads `TNOffering` from the config — exactly as `TNSubscriptionCore` does. (Qonversion đã
deprecated offering của họ, khuyên chuyển sang Remote Config. Vì vậy khác với RevenueCat và Adapty,
engine này không lấy offering từ dashboard. Nó đọc `TNOffering` trong config — y như
`TNSubscriptionCore`.)

To change the paywall without an app update, put the product IDs in a Qonversion **Remote Config**
payload and pass them in at runtime: (Để đổi paywall mà không cần cập nhật app, đặt product ID vào
payload **Remote Config** của Qonversion rồi truyền vào lúc runtime:)

```swift
// Remote Config payload, for example: {"products": ["com.app.weekly", "com.app.yearly"]}
let remoteConfig = try await Qonversion.shared().remoteConfig()
if let ids = remoteConfig.payload?["products"] as? [String] {
    await TNSubscription.shared.updateOfferings(
        [TNOffering(identifier: "remote", productIDs: ids)],
        current: "remote"
    )
}
```

The payload's shape is yours to choose; the package does not assume one. (Hình dạng payload do bạn
quyết định; package không áp đặt hình dạng nào.)

---

## 5. How it decides access (Cách xác định quyền truy cập)

1. **Warm start** — an unexpired cached result unlocks synchronously at launch. (Kết quả cache còn
   hạn mở khoá ngay khi khởi động.)
2. **Qonversion** — `checkEntitlements()`, the authoritative and cross-platform answer.
   (`checkEntitlements()`, câu trả lời chuẩn và đa nền tảng.)
3. **Offline fallback** — when Qonversion cannot be reached, Apple's verified local
   `Transaction.currentEntitlements`, mapped through `TNEntitlement.productIDs`. `customerInfo.source`
   says which answered. Turn it off with `offlineStoreKitFallback: false`. (Khi không kết nối được
   Qonversion, dùng giao dịch cục bộ của Apple. `customerInfo.source` cho biết nguồn nào đã trả lời.)
4. **A network error never locks an unlocked user.** (Lỗi mạng không bao giờ khoá người đang được mở khoá.)

Qonversion reports which **Qonversion** product granted an entitlement; the engine maps it to the
**App Store** ID, so `currentPlanProductID` and the paywall's "CURRENT" badge compare like with like.
(Qonversion báo product **Qonversion** nào đã cấp quyền; engine đổi nó sang ID **App Store**, để
`currentPlanProductID` và nhãn "CURRENT" trên paywall so sánh đúng loại ID.)

Qonversion no longer has a general "entitlements changed" listener, so renewals, refunds and
purchases from other devices are picked up through StoreKit's `Transaction.updates`. Ask-to-Buy and
SCA approvals arrive through Qonversion's deferred-purchases listener, which the engine installs.
(Qonversion không còn listener "quyền lợi thay đổi" chung, nên gia hạn, hoàn tiền và giao dịch từ
máy khác được nhận qua `Transaction.updates` của StoreKit. Việc duyệt Ask-to-Buy và SCA đến qua
listener deferred-purchases của Qonversion, do engine tự gắn.)

---

## 6. Design decisions worth flagging (Quyết định thiết kế đáng nói)

**Two products per package.** Qonversion still exposes only StoreKit 1's `SKProduct`. The engine
fetches the StoreKit 2 `Product` separately by App Store ID and uses it for display, price per month
and intro-offer eligibility — the same code as the other engines, including the fixed price maths —
while the purchase goes through `Qonversion.Product`. (**Hai sản phẩm cho mỗi gói.** Qonversion vẫn
chỉ cung cấp `SKProduct` của StoreKit 1. Engine tải riêng `Product` của StoreKit 2 theo ID App Store
để hiển thị, tính giá theo tháng và kiểm tra ưu đãi người mới — cùng code với các engine khác — còn
giao dịch mua đi qua `Qonversion.Product`.)

**The deferred-purchases listener is held strongly.** Qonversion keeps only a weak reference to it;
without the engine retaining it, it would be released at once and an Ask-to-Buy approval would go
unnoticed until the next launch. (**Listener deferred-purchases được giữ dạng strong.** Qonversion chỉ
giữ tham chiếu weak; nếu engine không giữ thì nó bị giải phóng ngay, và việc duyệt Ask-to-Buy sẽ không
được ghi nhận cho tới lần mở app sau.)

**A key from another vendor never reaches Qonversion.** The SDK does not validate project keys, so a
pasted RevenueCat or Adapty key would only surface as failed requests. It is caught at `configure`.
(**Key của nhà cung cấp khác không bao giờ tới Qonversion.** SDK không kiểm tra project key, nên key
RevenueCat hay Adapty dán nhầm chỉ lộ ra dưới dạng request lỗi. Nó được chặn ngay lúc `configure`.)

**No activation race.** `Qonversion.initWithConfig` is synchronous, so unlike Adapty there is nothing
to wait for before using it. (**Không có race khi kích hoạt.** `Qonversion.initWithConfig` chạy đồng
bộ, nên khác Adapty, không phải chờ gì trước khi dùng.)

---

## 7. Migration (Chuyển đổi)

From RevenueCat or Adapty (Từ RevenueCat hoặc Adapty):

1. Swap the product and the `import`. (Đổi product và `import`.)
2. Put the Qonversion project key in `apiKey`. (Đặt project key của Qonversion vào `apiKey`.)
3. **Declare your offerings** with `TNOffering` — dashboard offerings and placements do not carry
   over. (**Khai báo offering** bằng `TNOffering` — offering và placement trên dashboard không được
   mang sang.)
4. Check entitlement ID case against the Qonversion dashboard. (Kiểm tra chữ hoa/thường của ID.)
5. Consumable balances carry over: every engine uses the same Keychain keys and dedup list.
   (Số dư consumable được giữ nguyên: mọi engine dùng cùng Keychain key và danh sách chống trùng.)
6. From RevenueCat, rewrite custom paywall code that uses `Package` / `CustomerInfo`. (Từ RevenueCat,
   viết lại code paywall tự viết có dùng `Package` / `CustomerInfo`.)

---

## 8. Known limits (Giới hạn đã biết)

- **Promotional offers are not supported.** Qonversion's promotional offers go through StoreKit 1
  discounts (`getPromotionalOffer(for:discount:)`), which this engine does not wrap. Introductory
  offers and offer codes work. (**Chưa hỗ trợ promotional offer.** Promotional offer của Qonversion đi
  qua discount của StoreKit 1, engine này chưa bọc. Ưu đãi người mới và offer code vẫn hoạt động.)
- **Qonversion's no-code paywalls (NoCodes) are not documented here yet.** The module is linked by
  `QonversionNoIdfa`, but its use alongside this engine has not been verified. (**Paywall không cần
  code của Qonversion (NoCodes) chưa có tài liệu ở đây.** Module đã được link, nhưng việc dùng nó cùng
  engine này chưa được kiểm chứng.)
- **`periodType` is an approximation.** Qonversion reports when a trial started, not whether the
  current period is the trial; a trial that has not renewed is reported as `.trial`, and `.intro` is
  never reported. (**`periodType` là ước lượng.** Lần dùng thử chưa gia hạn được báo là `.trial`, và
  `.intro` không bao giờ được báo.)
- **`isSandbox` is `nil` and `.revoked` is never reported** on the Qonversion path, because its
  entitlements do not carry them. (**`isSandbox` là `nil` và `.revoked` không bao giờ được báo** ở
  luồng Qonversion, vì entitlement của nó không chứa các thông tin này.)
- **Consumables and transaction finishing** — same exposure as the RevenueCat and Adapty targets.
  (**Consumable và việc hoàn tất giao dịch** — rủi ro giống target RevenueCat và Adapty.)
- **Not tested against a live Qonversion project**; that needs a project key and network.
  (**Chưa test với dự án Qonversion thật**; cần project key và mạng.)

---

## 9. Tests (Kiểm thử)

```bash
xcodebuild test -scheme TNSubscriptionIOS-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TNSubscriptionQonversionTests
```

The engine contract (`TNEngineContractTests`, identical to the other three engines' except for its
`import`), plus the mapping rules — store source, renew intent, billing issues, trial detection,
ownership, project-key checks — and behaviour with no reachable Qonversion: another vendor's key is
never launched, offerings and `identify` fail readably, IAP-off unlocks everything, and the warm start
honours expiry. (Test contract — giống hệt ba engine kia trừ dòng `import` — cùng các quy tắc mapping
và hành vi khi không kết nối được Qonversion.)
