# TNSubscriptionAdapty — the Adapty-backed target (Target chạy trên Adapty)

A third target in this package: subscriptions backed by **Adapty** — access levels,
dashboard placements with A/B testing, server-signed promotional offers and cross-platform
profiles. (Target thứ ba của package: subscription chạy trên **Adapty** — access level,
placement trên dashboard có A/B test, promotional offer ký phía server và profile đa nền tảng.)

```swift
// Pick ONE (Chọn MỘT trong ba):
.product(name: "TNSubscriptionAdapty", package: "TNSubscriptionIOS")  // + Adapty
.product(name: "TNSubscriptionIOS",    package: "TNSubscriptionIOS")  // + RevenueCat
.product(name: "TNSubscriptionCore",   package: "TNSubscriptionIOS")  // Apple only
```

The other two targets were **not modified**. Each target links exactly one billing SDK.
(Hai target còn lại **không bị sửa**. Mỗi target chỉ link đúng một SDK thanh toán.)

---

## 1. Requirement: Xcode 26+ (Yêu cầu: Xcode 26+)

This target depends on **Adapty 4.x**, which declares `swift-tools-version: 6.2`. SwiftPM
resolves a package's **whole** dependency graph, so from this release on, resolving the package
needs Xcode 26+ — for all three targets, not just this one. (Target này phụ thuộc **Adapty 4.x**,
khai báo `swift-tools-version: 6.2`. SwiftPM resolve **toàn bộ** dependency graph, nên từ bản này
việc resolve package cần Xcode 26+ — cho cả ba target, không riêng target này.)

That costs shipping apps nothing: App Store Connect has only accepted builds made with
Xcode 26 / the iOS 26 SDK since **28 April 2026**. The one place it bit was this repo's CI,
which has moved from `macos-15` (Xcode 16.4) to `macos-26`. (Điều này không ảnh hưởng app đang
phát hành: App Store Connect chỉ nhận build từ Xcode 26 / iOS 26 SDK kể từ **28/04/2026**. Chỗ duy
nhất bị ảnh hưởng là CI của repo, đã chuyển từ `macos-15` (Xcode 16.4) sang `macos-26`.)

Adapty 3.x (`swift-tools-version: 6.0`) would still resolve on Xcode 16, but it is the previous
major and its paywall API (`getPaywall`) was replaced by `getFlow` in 4.x. (Adapty 3.x vẫn resolve
được trên Xcode 16, nhưng đó là bản major cũ và API paywall (`getPaywall`) đã bị thay bằng
`getFlow` ở 4.x.)

---

## 2. Concept mapping (Bản đồ khái niệm)

| This package | Adapty | RevenueCat | Core |
|---|---|---|---|
| `TNEntitlement.id` | **access level** ID | entitlement ID | local name |
| offering / `offeringIdentifier` | **placement** ID (`getFlow`) | offering ID | `TNOffering` in code |
| `TNPackage` | `AdaptyPaywallProduct` (+ `skProduct`) | `Package` | `StoreKit.Product` |
| `TNCustomerInfo` | `AdaptyProfile` | `CustomerInfo` | local transactions |
| `offer(for:)` | `subscriptionOffer` (one, pre-selected) | discounts | every offer |
| promotional offer signing | **Adapty server** | RevenueCat server | **your server** |

**The configuration is one shared type, not a copy.** `TNSubscriptionConfig`, `TNEntitlement`,
`TNOffering`, `TNLogLevel`, `DefaultPaywallConfig` and `TNConsumableProduct` live in
`TNSubscriptionShared`, re-exported by every engine, so they cannot differ. Every engine also
exposes `TNSubscription` as an alias of its entry point. Code that uses only the shared config and
the common API switches engine by changing only the `import` — see
[README → "What is the same, what differs"](README.md#what-is-the-same-what-differs-cái-gì-giống-cái-gì-khác).
The model types are **not** shared: `TNPackage`, `TNCustomerInfo` and `TNSubscriptionOffer` here are
Adapty's own, and the RevenueCat engine uses RevenueCat's `Package` and `CustomerInfo`, so a custom
paywall that lists packages must be rewritten when moving here from RevenueCat. Import one engine per
app. (**Cấu hình là một kiểu dùng chung, không
phải bản sao.** Các kiểu cấu hình nằm trong `TNSubscriptionShared`, được mọi engine re-export, nên
không thể khác nhau. Mọi engine cũng có `TNSubscription` làm alias cho điểm vào. Code chỉ dùng config
chung và phần API chung thì đổi engine chỉ cần đổi `import`. Các kiểu model thì **không** dùng chung:
`TNPackage`, `TNCustomerInfo`, `TNSubscriptionOffer` ở đây là của riêng Adapty, còn engine RevenueCat
dùng `Package` và `CustomerInfo` của RevenueCat — nên paywall tự viết có liệt kê gói phải viết lại khi
chuyển từ RevenueCat sang. Mỗi app chỉ import một engine.)

---

## 3. Setup (Cấu hình)

```swift
import TNSubscriptionAdapty

TNSubscription.configure(config: TNSubscriptionConfig(
    apiKey: "public_live_xxxxxxxx.xxxxxxxxxxxxxxxxxxxx",
    entitlements: [
        // `id` must match the Adapty access level EXACTLY — the default is lowercase "premium".
        // (`id` phải khớp CHÍNH XÁC access level trên Adapty — mặc định là "premium" viết thường.)
        TNEntitlement(id: "premium", productIDs: ["com.app.weekly", "com.app.yearly"]),
    ],
    currentOfferingIdentifier: "main"   // an Adapty placement ID
))
```

- **`apiKey`** — the *public* SDK key, `public_live_…`. (Key SDK *public*, dạng `public_live_…`.)
- **`productIDs`** — not needed online; they power the offline fallback (§5).
  (Không cần khi online; chúng phục vụ phương án offline — xem §5.)
- **`currentOfferingIdentifier`** — for Adapty, the **placement ID** a paywall shows when it does
  not name one. Same field as the other engines; only what it names differs. (Với Adapty, đây là
  **placement ID** mà paywall hiển thị khi không chỉ định. Cùng trường với các engine khác; chỉ khác
  ở thứ mà nó trỏ tới.)
- The convenience initialiser defaults `entitlementId` to `"Premium"` in every engine, but Adapty's
  default access level is lowercase `"premium"` — pass it explicitly. (Initializer tiện lợi mặc định
  `entitlementId` là `"Premium"` ở mọi engine, nhưng access level mặc định của Adapty là `"premium"`
  viết thường — hãy truyền tường minh.)
- `offerings:` and `enableBackendIdentitySync:` are ignored here, with a warning at `configure`.
  (`offerings:` và `enableBackendIdentitySync:` bị bỏ qua ở đây, kèm cảnh báo lúc `configure`.)

---

## 4. Usage (Cách dùng)

Everything the other engines have works the same way. (Mọi thứ có ở các engine khác đều dùng y
như vậy.)

```swift
TNSubscriptionAdapty.shared.isPremium
TNSubscriptionAdapty.shared.hasEntitlement("premium")
TNSubscriptionAdapty.presentDefaultPaywall(from: vc,
    config: DefaultPaywallConfig(offeringIdentifier: "onboarding"))   // a placement ID
try await TNSubscriptionAdapty.shared.purchaseAsync(package: package)
try await TNSubscriptionAdapty.shared.restorePurchasesAsync()
```

Adapty-specific additions (Phần bổ sung riêng cho Adapty):

```swift
// Identity — merges anonymous purchases into the account. (Gộp giao dịch ẩn danh vào tài khoản.)
try await TNSubscriptionAdapty.shared.identify(userId)     // after login
try await TNSubscriptionAdapty.shared.logout()              // on logout

// A custom paywall MUST report its views, or A/B tests see zero.
// (Paywall tự viết BẮT BUỘC phải báo lượt xem, nếu không A/B test thấy bằng 0.)
await TNSubscriptionAdapty.shared.logPaywallShown()

// The single offer Adapty chose for this user — intro, promotional or win-back.
// (Ưu đãi duy nhất Adapty chọn cho người dùng này — người mới, promotional hoặc win-back.)
TNSubscriptionAdapty.shared.offer(for: package)

// Remote config from the dashboard, and the A/B variation a package was served under.
// (Remote config từ dashboard, và biến thể A/B mà gói được hiển thị.)
TNSubscriptionAdapty.shared.currentOfferingMetadata["headline"]
package.variationId
```

---

## 5. How it decides access (Cách xác định quyền truy cập)

1. **Warm start** — at launch, an unexpired cached result unlocks synchronously, so a paying user
   never sees a paywall flash. (Khi khởi động, kết quả cache còn hạn mở khoá ngay, để người đã trả
   tiền không thấy paywall nhoáng lên.)
2. **Adapty profile** — the authoritative answer. It sees purchases from every platform and grants
   made in the dashboard. (Câu trả lời chuẩn. Nó thấy giao dịch từ mọi nền tảng và quyền cấp từ
   dashboard.)
3. **Offline fallback** — if Adapty cannot be reached, Apple's verified local
   `Transaction.currentEntitlements`, mapped through `TNEntitlement.productIDs`.
   `customerInfo.source` says which path answered. (Nếu không kết nối được Adapty, dùng
   `Transaction.currentEntitlements` cục bộ đã xác minh của Apple, map qua `TNEntitlement.productIDs`.
   `customerInfo.source` cho biết đường nào đã trả lời.)
4. **A network error never locks an unlocked user.** With the fallback off, the last known state
   is kept. (**Lỗi mạng không bao giờ khoá người đang được mở khoá.** Khi tắt phương án dự phòng,
   trạng thái đã biết gần nhất được giữ nguyên.)

Profile changes — renewals, refunds, dashboard grants — arrive through `AdaptyDelegate` and update
the published state on their own. (Thay đổi profile — gia hạn, hoàn tiền, quyền cấp từ dashboard —
đến qua `AdaptyDelegate` và tự cập nhật state.)

---

## 6. How it differs from the other engines (Khác các engine khác thế nào)

- **One pre-selected offer, no signer.** Adapty returns the single best offer this user is
  eligible for — win-back → promotional → introductory — and `makePurchase` applies it, signing
  promotional offers on Adapty's server. Core needs your own backend signer for that.
  (**Một ưu đãi chọn sẵn, không cần signer.** Adapty trả về ưu đãi tốt nhất mà người dùng đủ điều
  kiện — win-back → promotional → người mới — và `makePurchase` tự áp dụng, ký promotional offer
  trên server của Adapty. Core thì cần signer ở backend của bạn.)
- **Dashboard order is kept.** Packages are not re-sorted, because the order is part of what an
  Adapty A/B test varies. (**Giữ thứ tự của dashboard.** Gói không bị sắp xếp lại, vì thứ tự là một
  phần mà A/B test của Adapty thay đổi.)
- **Cross-platform stores.** `TNEntitlementInfo.store` can be `.playStore`, `.web` or
  `.promotional`, not only `.appStore`. (**Store đa nền tảng.** `store` có thể là `.playStore`,
  `.web` hoặc `.promotional`, không chỉ `.appStore`.)
- **Adapty's own logs** follow `TNSubscriptionAdapty.logLevel` and `logHandler`, so one switch
  silences both. (**Log của chính Adapty** cũng theo `logLevel` và `logHandler`, nên một công tắc
  tắt được cả hai.)

---

## 7. Migration (Chuyển đổi)

### From RevenueCat (`TNSubscriptionIOS`) (Từ RevenueCat)

1. Swap the product and the `import`. (Đổi product và `import`.)
2. Replace the `appl_…` key with Adapty's `public_live_…` key. Pasting the old key is caught at
   launch with an explicit message. (Thay key `appl_…` bằng key `public_live_…` của Adapty. Dán nhầm
   key cũ sẽ bị bắt ngay khi khởi động với thông báo rõ ràng.)
3. **Check entitlement ID case.** RevenueCat projects often use `"Premium"`; Adapty's default is
   `"premium"`. A mismatch is logged, but unlocks nothing. (**Kiểm tra chữ hoa/thường của ID.**
   Dự án RevenueCat hay dùng `"Premium"`; mặc định của Adapty là `"premium"`. Sai lệch sẽ được ghi
   log, nhưng không mở khoá được gì.)
4. RevenueCat offering IDs become Adapty placement IDs. (Offering ID của RevenueCat thành placement
   ID của Adapty.)
5. **Consumable balances carry over**: this target reads the same Keychain keys and dedup list as
   the RevenueCat target. (**Số dư consumable được giữ nguyên**: target này đọc cùng Keychain key và
   danh sách chống trùng với target RevenueCat.)
6. **Rewrite custom paywall code that touches packages.** RevenueCat's `Package` becomes `TNPackage`
   (`package.storeProduct.localizedPriceString` → `package.localizedPriceString`), `CustomerInfo`
   becomes `TNCustomerInfo`, and `introOffer(for:)` returns `TNSubscriptionOffer` instead of
   `StoreProductDiscount`. The built-in paywall and the common API need no change.
   (**Viết lại code paywall tự viết có đụng tới gói.** `Package` của RevenueCat thành `TNPackage`,
   `CustomerInfo` thành `TNCustomerInfo`, và `introOffer(for:)` trả về `TNSubscriptionOffer` thay vì
   `StoreProductDiscount`. Paywall có sẵn và phần API chung không cần sửa gì.)
7. `TNInAppCurrencyManager` (RevenueCat cloud currency) has no Adapty equivalent. Those balances
   live on RevenueCat's servers, not on the device, so export them to your own backend first, then
   use `TNConsumableManager` with `configureSpendHandler(_:)` against that backend.
   (`TNInAppCurrencyManager` không có tương đương bên Adapty. Các số dư đó nằm trên server của
   RevenueCat chứ không nằm trên máy, nên phải xuất chúng sang backend của bạn trước, rồi dùng
   `TNConsumableManager` cùng `configureSpendHandler(_:)` với backend đó.)

### From `TNSubscriptionCore` (Từ Core)

Add `apiKey:` to the same config. `offerings:` can stay but is ignored with a warning — recreate
them as Adapty placements. Drop `configurePromotionalOfferSigner`: Adapty signs. Consumable balances
are migrated once from Core's keys. (Thêm `apiKey:` vào cùng config đó. `offerings:` để nguyên cũng
được nhưng sẽ bị bỏ qua kèm cảnh báo — hãy tạo lại thành placement trên Adapty. Bỏ
`configurePromotionalOfferSigner`: Adapty tự ký. Số dư consumable được migrate một lần từ key của
Core.)

Purchases themselves are never lost on any switch: the source of truth is the Apple ID. Until
Adapty has seen a user's existing App Store history, the offline fallback (§5) still unlocks them
from Apple's local transactions, and `restorePurchasesAsync()` sends that history to Adapty.
(Giao dịch không bao giờ mất khi đổi: nguồn chân lý là Apple ID. Trong lúc Adapty chưa thấy lịch
sử App Store sẵn có của người dùng, phương án offline (§5) vẫn mở khoá cho họ từ giao dịch cục bộ
của Apple, và `restorePurchasesAsync()` sẽ gửi lịch sử đó lên Adapty.)

---

## 8. Design decisions worth flagging (Quyết định thiết kế đáng nói)

**A bad API key is stopped before it reaches Adapty.** Adapty validates its key with an `assert`
(`count >= 41 && starts(with: "public_live")`), which **crashes every Debug build** on a typo. The
key is checked first; on failure Adapty is never activated, entitlements fall back to local
StoreKit and purchases throw `.notActivated`. Secret keys and RevenueCat keys get their own
messages. (**Key sai bị chặn trước khi tới Adapty.** Adapty kiểm tra key bằng `assert`, nên một
lỗi gõ phím sẽ **crash mọi bản build Debug**. Key được kiểm tra trước; nếu sai thì Adapty không
được kích hoạt, quyền lợi dùng StoreKit cục bộ và mua sẽ throw `.notActivated`.)

**Activation and the first resolve run as two tasks.** `resolveEntitlement()` awaits activation;
running the first resolve inside the activation task made it await itself — a deadlock that left
the state on `.unknown` forever and the paywall spinner turning. The test suite caught it before
release. (**Kích hoạt và lần xác định đầu tiên chạy thành hai task.** Chạy resolve bên trong task
kích hoạt khiến nó tự chờ chính mình — một deadlock làm trạng thái kẹt ở `.unknown` mãi mãi và
spinner paywall quay không ngừng. Bộ test đã bắt được trước khi phát hành.)

**Paywall views are logged.** `TNDefaultPaywallView` calls `Adapty.logShowFlow` once per flow per
session. Without it, every A/B test on that placement has a zero denominator. (**Lượt xem paywall
được ghi nhận.** Thiếu nó thì mọi A/B test trên placement đó có mẫu số bằng 0.)

**The two 1.2.0 fixes are carried over**: lifetime grants are cached as `Date.distantFuture`
(not `NSNull`), and per-month prices use exact integer fractions (no `Decimal` overflow to `nan`).
(**Hai bản sửa của 1.2.0 được mang sang**: quyền vĩnh viễn cache bằng `Date.distantFuture`, và giá
theo tháng dùng phân số nguyên chính xác.)

---

## 9. Known limits (Giới hạn đã biết)

- **AdaptyUI (the no-code Paywall Builder) is not wrapped.** This target ships the same SwiftUI
  paywall as the others. To show a Builder paywall, use `AdaptyUI` directly alongside it.
  (**AdaptyUI (Paywall Builder không cần code) chưa được bọc.** Target này dùng chung paywall SwiftUI
  với các target khác. Muốn dùng paywall Builder thì gọi `AdaptyUI` trực tiếp song song.)
- **Consumables and transaction finishing.** `TNConsumableManager` uses raw StoreKit, while
  Adapty finishes transactions automatically by default. If the app is killed between a payment
  and the credit, Adapty may finish the transaction before recovery reads it, and that one credit
  is lost. The RevenueCat target has the same exposure. (**Consumable và việc hoàn tất giao dịch.**
  `TNConsumableManager` dùng StoreKit thuần, còn Adapty mặc định tự hoàn tất giao dịch. Nếu app bị
  tắt giữa lúc thanh toán và lúc cộng thưởng, Adapty có thể hoàn tất giao dịch trước khi recovery
  đọc được, và lần cộng đó bị mất. Target RevenueCat cũng có rủi ro tương tự.)
- **`isSandbox` may be `nil`** and **`ownershipType` is `.unknown`** on the online path, because
  Adapty's access level does not report them. (**`isSandbox` có thể là `nil`** và **`ownershipType`
  là `.unknown`** ở luồng online, vì access level của Adapty không cung cấp chúng.)
- **No integration tests against a real Adapty project.** Those need a project key and network.
  (**Chưa có integration test với dự án Adapty thật.** Cần key dự án và mạng.)

---

## 10. Tests (Kiểm thử)

```bash
xcodebuild test -scheme TNSubscriptionIOS-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TNSubscriptionAdaptyTests
```

35 tests in 6 suites, including the engine contract (`TNEngineContractTests`), which proves this
engine exposes the same configuration and common API as the other two. (35 test trong 6 suite, gồm
cả test contract, chứng minh engine này có cùng cấu hình và API chung với hai engine kia.)

Adapty's models have no public initialisers and its calls need a real key, so the mapping rules
were pulled into pure functions and tested directly: API key classification, store / period /
issue mapping, intro eligibility from the selected offer, package-type inference, the savings
maths on the exact case that overflowed `Decimal`, log-level bridging — plus engine behaviour with
no reachable Adapty: a bad key neither crashes nor unlocks, placements and `identify` fail
readably, IAP-off unlocks all, and the warm start honours expiry.
(Model của Adapty không có initializer công khai và các lời gọi cần key thật, nên quy tắc mapping
được tách thành hàm thuần và kiểm thử trực tiếp — cộng thêm hành vi của engine khi không kết nối
được Adapty.)
