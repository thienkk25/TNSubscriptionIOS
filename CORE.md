# TNSubscriptionCore — the Apple-only core target (Target core thuần Apple)

A second target in this package: **no RevenueCat, Apple StoreKit 2 only**. No API key, no
vendor SDK, no third-party network call. (Target thứ hai của package: **không phụ thuộc
RevenueCat, chỉ dùng Apple StoreKit 2**. Không API key, không SDK bên thứ ba, không một
request mạng nào tới nhà cung cấp nào.)

```swift
.package(url: "…/TNSubscriptionIOS.git", from: "…")

// Pick ONE (Chọn MỘT trong hai):
.product(name: "TNSubscriptionCore", package: "TNSubscriptionIOS")   // Apple only
.product(name: "TNSubscriptionIOS",  package: "TNSubscriptionIOS")   // + RevenueCat
```

---

## 1. Why a separate target, not a compile flag (Vì sao là target riêng, không phải flag)

`TNSubscriptionCore` declares **no `dependencies:`** in `Package.swift`. That is the core of
the design: a `#if canImport(RevenueCat)` would still pull RevenueCat into the binary, into
`PrivacyInfo`, and into App Store Connect. Two separate targets link only what the app picks.
(`TNSubscriptionCore` **không có `dependencies:`** trong `Package.swift`. Đó là điểm cốt lõi
của thiết kế: một `#if canImport(RevenueCat)` vẫn kéo RevenueCat vào binary, vào `PrivacyInfo`,
vào App Store Connect. Hai target riêng biệt thì app chỉ link đúng thứ nó chọn.)

The existing RevenueCat code was **not modified by a single line** — it still builds and
behaves exactly as before. (Code cũ dùng RevenueCat **không bị sửa một dòng nào** — vẫn build,
vẫn chạy như trước.)

---

## 2. Type mapping (Bản đồ chuyển đổi)

| RevenueCat | TNSubscriptionCore | Source of truth (Nguồn dữ liệu) |
|---|---|---|
| `Purchases.configure(apiKey:)` | *none (không có)* | — |
| `CustomerInfo` | `TNCustomerInfo` | `Transaction.currentEntitlements` |
| `EntitlementInfo` | `TNEntitlementInfo` | verified JWS transaction |
| `EntitlementInfos` | `TNEntitlementInfos` | same `all` / `active` / subscript |
| `Offerings` + dashboard | `[TNOffering]` declared in code | your own config |
| `Package` | `TNPackage` | wraps `StoreKit.Product` |
| `Package.packageType` | `TNPackageType` | inferred from `subscriptionPeriod` |
| `StoreProductDiscount` | `TNSubscriptionOffer` | `Product.SubscriptionOffer` |
| `IntroEligibilityStatus` | `TNIntroEligibilityStatus` | `subscription.isEligibleForIntroOffer` |
| `PromotionalOffer` (RC signs) | `TNPromotionalOfferSignature` (**you sign**) | your backend |
| `restorePurchases()` | `restorePurchasesAsync()` | `AppStore.sync()` |
| `VirtualCurrencies` (RC server) | local balances in `TNConsumableManager` | Keychain |
| `logLevel` → RC SDK | `logLevel` → this package only | `os.Logger` |

**The configuration is one shared type, not a copy.** `TNSubscriptionConfig`, `TNEntitlement`,
`TNOffering`, `TNLogLevel`, `DefaultPaywallConfig` and `TNConsumableProduct` live in the
`TNSubscriptionShared` module, which every engine re-exports — so they cannot differ between
engines. Every engine also exposes `TNSubscription` as an alias of its entry point. Code that uses
only the shared config and the common API switches engine by changing only the `import` — see
[README → "What is the same, what differs"](README.md#what-is-the-same-what-differs-cái-gì-giống-cái-gì-khác)
for exactly which APIs that covers.
(**Cấu hình là một kiểu dùng chung, không phải bản sao.** Các kiểu cấu hình nằm trong module
`TNSubscriptionShared`, được mọi engine re-export — nên không thể khác nhau giữa các engine. Mọi
engine cũng có `TNSubscription` làm alias cho điểm vào. Code chỉ dùng config chung và phần API chung
thì đổi engine chỉ cần đổi `import` — xem README, mục "What is the same, what differs", để biết chính
xác những API nào.)

What is **not** shared: the model types. `TNPackage`, `TNCustomerInfo` and `TNSubscriptionOffer` are
Core's own; the RevenueCat engine uses RevenueCat's `Package` and `CustomerInfo` instead. So a custom
paywall that lists packages must be rewritten when moving here from RevenueCat. Import only one engine
per app. (Phần **không** dùng chung: các kiểu model. `TNPackage`, `TNCustomerInfo`,
`TNSubscriptionOffer` là của riêng Core; engine RevenueCat dùng `Package` và `CustomerInfo` của
RevenueCat. Vì vậy paywall tự viết có liệt kê gói phải viết lại khi chuyển từ RevenueCat sang. Mỗi app
chỉ import một engine.)

---

## 3. Setup (Cấu hình)

```swift
import TNSubscriptionCore

TNSubscription.configure(config: TNSubscriptionConfig(
    entitlements: [
        TNEntitlement(id: "Premium", productIDs: ["com.app.weekly", "com.app.yearly"]),
        TNEntitlement(id: "Sale",    productIDs: ["com.app.sale_yearly"]),
    ],
    // Leave this out and a "default" offering is synthesised from every product ID above.
    // (Không khai báo thì một offering "default" được tự sinh từ mọi product ID ở trên.)
    offerings: [
        TNOffering(identifier: "default", productIDs: ["com.app.weekly", "com.app.yearly"]),
        TNOffering(identifier: "sale",    productIDs: ["com.app.sale_yearly"]),
    ],
    currentOfferingIdentifier: "default"
))
```

It is the same `TNSubscriptionConfig` every engine takes. Core reads `offerings:` (it has no
dashboard) and ignores `apiKey:` — passing one is harmless and logs a warning at `configure`, as
does any setting Core cannot honour. (Đây là cùng một `TNSubscriptionConfig` mà mọi engine nhận.
Core đọc `offerings:` vì không có dashboard, và bỏ qua `apiKey:` — truyền vào cũng không sao, chỉ
ghi một cảnh báo lúc `configure`, giống mọi thiết lập Core không áp dụng được.)

Swap offerings at runtime — A/B tests, a seasonal paywall — from your own remote config:
(Đổi offering lúc runtime — A/B test, paywall theo mùa — từ remote config của bạn:)

```swift
await TNSubscriptionCore.shared.updateOfferings([
    TNOffering(identifier: "bf2026", productIDs: ["com.app.bf_yearly"])
], current: "bf2026")
```

---

## 4. Usage (Cách dùng)

```swift
// State (Trạng thái)
TNSubscriptionCore.shared.isPremium
TNSubscriptionCore.shared.hasEntitlement("Sale")
TNSubscriptionCore.shared.entitlementState          // .unknown / .locked / .unlocked

// From a background context, no await needed (Từ background, không cần await)
TNSubscriptionCore.cachedIsPremium

// Paywall
TNSubscriptionCore.presentDefaultPaywall(from: vc)
TNSubscriptionCore.presentPaywall(from: vc) { MyPaywall() }

// Purchase / restore (Mua / phục hồi)
try await TNSubscriptionCore.shared.purchaseAsync(package: package)
try await TNSubscriptionCore.shared.restorePurchasesAsync()

// Apple's own sheets (Bảng hệ thống của Apple)
TNSubscriptionCore.shared.showManageSubscriptions()
TNSubscriptionCore.shared.presentOfferCodeRedemption()
await TNSubscriptionCore.shared.requestRefund(for: productID)
```

### `@MainActor`

`TNSubscriptionCore` is main-actor isolated — correct for an `ObservableObject`, and what
Swift 6 strict concurrency requires. This is the biggest call-site difference from the old
target: calling from a background context needs `await`, or read
`TNSubscriptionCore.cachedIsPremium`, a lock-protected `nonisolated` snapshot that needs no
`await`. (`TNSubscriptionCore` là `@MainActor` — đúng chuẩn cho `ObservableObject`, và là yêu
cầu của Swift 6 strict concurrency. Đây là khác biệt lớn nhất về call-site so với target cũ:
gọi từ background cần `await`, hoặc đọc `TNSubscriptionCore.cachedIsPremium` — snapshot bảo vệ
bằng lock, `nonisolated`, không cần `await`.)

---

## 5. What you gain (Được gì)

- **Offline unlocks.** `Transaction.currentEntitlements` reads the signed receipt on-device.
  No network, no server, no "verifying" limbo on a plane. (**Mở khoá offline.** Đọc từ receipt
  đã ký trên thiết bị. Không mạng, không server, không có khoảng "đang chờ xác minh".)
- **No third-party point of failure.** A vendor outage stops being one of your app's failure
  modes. (**Không có điểm chết bên thứ ba.** RC down không còn là một chế độ lỗi của app bạn.)
- **Verification is still verification.** StoreKit 2 checks the JWS signature back to Apple's
  root certificate, on-device. `.unverified` transactions are rejected (see
  `verified(_:context:)`). This is not a "less secure" build — it drops server-side receipt
  validation, not the cryptography. (**Xác minh vẫn là xác minh.** StoreKit 2 kiểm tra chữ ký
  JWS ngược về root cert của Apple, ngay trên thiết bị. Giao dịch `.unverified` bị từ chối.
  Đây không phải bản "kém an toàn hơn" — nó bỏ server validation, không bỏ cryptography.)
- **`willRenew`, grace period, billing retry** come from `Product.SubscriptionInfo.Status`, so
  the paywall can say "your payment failed" or "auto-renew is off" — what a paying user
  actually needs told. (**`willRenew`, grace period, billing retry** đến từ
  `Product.SubscriptionInfo.Status`, nên paywall báo được "thanh toán lỗi" / "đã tắt gia hạn" —
  thứ người đang trả tiền cần biết.)
- **Exact trial eligibility.** `isEligibleForIntroOffer` is Apple's own answer, per
  subscription group, so a "Start Free Trial" button never lies to a returning user.
  (**Điều kiện trial chính xác.** Là câu trả lời của Apple theo subscription group, nên nút
  "Dùng thử miễn phí" không nói sai với người quay lại.)
- **Smaller**: ~0 bytes of dependency, no third-party privacy manifest. (**Nhỏ hơn**: ~0 byte
  dependency, không privacy manifest của bên thứ ba.)

## 6. What you give up (Mất gì) — read this section carefully

These things **cannot** be done with Apple alone. There is no way around them. (Đây là những
thứ **không thể** làm chỉ với Apple. Không có cách lách.)

| What you lose | Why | What to do if you need it |
|---|---|---|
| **Cross-platform entitlements** (Quyền lợi đa nền tảng) | StoreKit only knows Apple transactions. An Android or web purchase is invisible here. | Your own backend, or keep RevenueCat. |
| **Dashboard offerings** (Offerings trên dashboard) | There is no dashboard. Offerings live in code. | `updateOfferings(_:current:)` + your remote config. |
| **Automatic promotional offers** (Promotional offer tự động) | Apple requires a signature from your `.p8` Subscription Key. That private key must **never** ship in the app. | `configurePromotionalOfferSigner(_:)` → your server signs. Introductory offers and offer codes need **nothing**. |
| **Server-side virtual currency** (Virtual currency phía server) | No Apple API equivalent exists. | Local balances (Keychain), or `configureSpendHandler(_:)` → your server. |
| **Analytics / cohorts / charts** | No backend is collecting anything. | App Store Connect, or your own analytics. |
| **Device-portable consumable balances** (Số dư consumable theo máy) | Balances live on the device, not on the user's account. | Keep the authoritative balance on your server. |
| **Subscription event webhooks** (Webhook sự kiện subscription) | There is no intermediary server. | App Store Server Notifications V2 (straight from Apple) + `attachAppAccountToken: true` to attribute a transaction to a user. |

Those last two rows are a good option if you already have a backend: Apple posts the webhooks
directly, and `appAccountToken` (taken from the Keychain `clientId`) tells your backend whose
transaction it is — covering most of what RevenueCat does, without RevenueCat. (Hai dòng cuối
là lựa chọn tốt nếu bạn đã có backend: Apple gửi webhook trực tiếp, và `appAccountToken` cho
backend biết giao dịch thuộc về ai — làm được gần hết việc RevenueCat làm, mà không cần
RevenueCat.)

---

## 7. Design decisions worth flagging (Quyết định thiết kế đáng nói)

**A warm-start cache that checks expiry.** RevenueCat has a synchronous `cachedCustomerInfo`;
StoreKit has no equivalent, so a cold start would flash the paywall at a paying user. The core
caches `[entitlementID: expiry]` and **only trusts unexpired entries** — stale data can never
revive a lapsed subscription. Stricter than a blindly trusted cache. (**Warm-start cache có
kiểm tra ngày hết hạn.** StoreKit không có gì tương đương `cachedCustomerInfo`, nên cold start
sẽ nhoáng paywall với người đã trả tiền. Core cache `[entitlementID: expiry]` và **chỉ tin các
bản ghi còn hạn** — dữ liệu cũ không "hồi sinh" được subscription đã hết.)

**`.unknown` is a real state.** Never show a paywall while `entitlementState == .unknown`; the
built-in paywall shows a spinner. This is the single most common cause of "a paying user still
sees the paywall". (**`.unknown` là một trạng thái thật.** Đừng hiện paywall khi
`entitlementState == .unknown`. Đây là nguyên nhân phổ biến nhất của "người đã mua vẫn thấy
paywall".)

**Consumables are not finished by the subscription manager.** `finishIfOurs(_:)` only finishes
`.autoRenewable` and `.nonConsumable`. Finishing a consumable before its reward is credited
loses the user's money with no way to recover it — `TNConsumableManager` finishes those itself,
after crediting. (**Consumable không bị subscription manager finish.** Finish một consumable
trước khi cộng thưởng là mất tiền của người dùng mà không lấy lại được.)

**Consumable crediting order:** credit the balance → mark processed → finish. Reverse it and
an app death between two steps loses the transaction. (**Thứ tự cộng thưởng consumable:** cộng
số dư → ghi dấu đã xử lý → finish. Đảo lại thì app tắt giữa hai bước là mất giao dịch.)

**A lifetime purchase beats a subscription** for the same entitlement: it never expires, so it
is the stronger grant. (**Lifetime thắng subscription** cho cùng một entitlement: không hết hạn
nên là quyền mạnh hơn.)

**"BEST VALUE" is computed, not assumed.** `recommendedPackage` picks the genuinely cheapest
**per month** rather than defaulting to the annual plan. The "SAVE X%" badge is derived from
the same per-month figure. (**"BEST VALUE" tính thật.** Chọn gói rẻ nhất **tính theo tháng**,
không mặc định gói năm.)

**`willRenew` defaults to `true` when unreadable.** Falsely telling a healthy subscriber they
are about to lapse is the worse error. (**`willRenew` mặc định `true` khi chưa đọc được.** Báo
sai "sắp hết hạn" cho một subscription đang khoẻ là lỗi tệ hơn.)

---

## 8. Migrating from `TNSubscriptionIOS` (Migrate từ `TNSubscriptionIOS`)

1. Swap the product in `Package.swift` / Xcode: `TNSubscriptionIOS` → `TNSubscriptionCore`.
2. `import TNSubscriptionIOS` → `import TNSubscriptionCore`.
3. The config stays as it is. Add `offerings:` if your paywall uses more than one; `apiKey:` can
   stay — it is ignored with a warning. (Config giữ nguyên. Thêm `offerings:` nếu paywall dùng nhiều
   hơn một; `apiKey:` để nguyên cũng được — sẽ bị bỏ qua kèm cảnh báo.)
4. Code written against `TNSubscription.shared` needs no change; `TNSubscriptionIOS.shared` becomes
   `TNSubscriptionCore.shared`. (Code viết theo `TNSubscription.shared` không cần sửa;
   `TNSubscriptionIOS.shared` thành `TNSubscriptionCore.shared`.)
5. `Package` → `TNPackage`, `CustomerInfo` → `TNCustomerInfo`.
6. Background call sites: add `await`, or switch to `TNSubscriptionCore.cachedIsPremium`.
7. If you use promotional offers: install `configurePromotionalOfferSigner(_:)`.
8. If you use RevenueCat virtual currencies: move to `configureSpendHandler(_:)` + your server.
9. Consumable balances (`TNConsumableManager`) carry over: since 1.4.0 every engine uses the same
   Keychain keys and dedup list. Balances written by Core 1.3.x under its old `tn_core_…` keys are
   migrated once, on first launch. (Số dư consumable được giữ nguyên: từ 1.4.0 mọi engine dùng cùng
   Keychain key và danh sách chống trùng. Số dư mà Core 1.3.x ghi dưới key cũ `tn_core_…` được migrate
   một lần, ở lần mở app đầu tiên.)

Existing purchases **lose nothing** in the switch: the source of truth is the Apple ID, not the
SDK. (Entitlement đã mua **không mất gì** khi đổi: nguồn chân lý là Apple ID, không phải SDK.)

---

## 9. Tests (Kiểm thử)

Two layers, because StoreKit forces the split. (Hai tầng, vì StoreKit buộc phải tách như vậy.)

### Unit tests — 34 tests, 9 suites (SwiftPM)

```bash
xcodebuild test -scheme TNSubscriptionIOS-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TNSubscriptionCoreTests
```

Pure value logic: config resolution, offering synthesis, package ordering, the concurrent
snapshot, offer-signature parsing, error messages, identity headers, log thresholds — plus the
engine contract (`TNEngineContractTests`), which proves Core exposes the same configuration and
common API as the other two engines.
(Logic thuần giá trị: xử lý config, tự sinh offering, thứ tự gói, snapshot đa luồng, parse chữ
ký offer, thông báo lỗi, identity header, ngưỡng log — cộng thêm test contract
(`TNEngineContractTests`), chứng minh Core có cùng cấu hình và API chung với hai engine kia.)

### Integration tests — 61 tests, 3 suites (Xcode host app)

```bash
cd IntegrationTests && xcodegen generate
```

```bash
cd IntegrationTests && xcodebuild test -project TNCoreIntegration.xcodeproj -scheme TNCoreIntegrationTests -destination 'platform=iOS Simulator,name=iPhone 17' -test-timeouts-enabled YES -default-test-execution-time-allowance 45
```

Real purchases against `SKTestSession` and `Resources/TNCoreTests.storekit`: products and
offerings, package-type inference, per-month price and savings maths, intro-offer eligibility
across a subscription group, purchase, lifetime-beats-subscription, lapse, refund, restore,
external transactions via `Transaction.updates`, the warm-start cache, and the consumable
ledger including server-authoritative spending.
(Giao dịch thật trên `SKTestSession` và `Resources/TNCoreTests.storekit`: sản phẩm và offering,
suy luận loại gói, tính giá theo tháng và % tiết kiệm, điều kiện ưu đãi người mới theo
subscription group, mua, lifetime thắng subscription, hết hạn, hoàn tiền, phục hồi, giao dịch
từ bên ngoài qua `Transaction.updates`, warm-start cache, và sổ consumable kèm tiêu qua server.)

**Why a host app is required.** StoreKit will not serve products to a SwiftPM test runner:
`SKTestSession` loads the configuration file fine, but `Product.products(for:)` comes back
empty, because `Bundle.main` there is the `xctest` binary rather than an app. `TNCoreTestHost`
is a deliberately empty app that exists only to be `TEST_HOST`.
(**Vì sao phải có host app.** StoreKit không trả sản phẩm cho test runner của SwiftPM:
`SKTestSession` nạp được file cấu hình, nhưng `Product.products(for:)` trả về rỗng, vì
`Bundle.main` ở đó là binary `xctest` chứ không phải một app. `TNCoreTestHost` là một app rỗng
có chủ đích, tồn tại chỉ để làm `TEST_HOST`.)

### Two bugs these tests caught (Hai bug mà bộ test này đã bắt được)

Both were invisible to unit tests, and both only hurt paying customers.
(Cả hai đều không thể thấy bằng unit test, và cả hai chỉ gây hại cho khách đã trả tiền.)

- **`NSNull` in the warm-start cache.** A lifetime grant has no expiry date, and storing that as
  `NSNull` made `UserDefaults` reject the *entire* dictionary, because `NSNull` is not a
  property-list type. Lifetime customers therefore got no warm start at all and saw the paywall
  flicker on every cold launch. Lifetime grants are now stored as `Date.distantFuture`.
  (**`NSNull` trong warm-start cache.** Quyền lợi vĩnh viễn không có ngày hết hạn, và lưu nó
  bằng `NSNull` khiến `UserDefaults` từ chối *toàn bộ* dictionary, vì `NSNull` không phải kiểu
  property-list. Người mua vĩnh viễn do đó không hề được warm start và thấy paywall nhoáng lên
  mỗi lần mở app nguội. Giờ quyền lợi vĩnh viễn được lưu bằng `Date.distantFuture`.)
- **`Decimal` overflowing to `nan` in the savings badge.** `pricePerMonth` divided by
  `Decimal(Double)`, and for a weekly plan `7.0/30.0` carries a full-precision mantissa; the
  second division inside `savingsPercentage` then overflowed Decimal's 38-digit mantissa into
  `nan`, which `Int(truncating:)` read as `0`. The paywall showed "SAVE 0%" on the best plan,
  with no crash and no log. Period lengths are now exact integer fractions and the percentage
  is computed in `Double`.
  (**`Decimal` tràn thành `nan` ở nhãn tiết kiệm.** `pricePerMonth` chia cho `Decimal(Double)`,
  và với gói tuần thì `7.0/30.0` mang mantissa ở độ chính xác đầy đủ; phép chia thứ hai trong
  `savingsPercentage` sau đó làm tràn mantissa 38 chữ số thành `nan`, và `Int(truncating:)` đọc
  ra `0`. Paywall hiện "SAVE 0%" trên gói tốt nhất, không crash, không log. Giờ độ dài kỳ hạn
  là phân số nguyên chính xác và phần trăm được tính bằng `Double`.)

### Known limits (Giới hạn đã biết)

- **Prices must be whole dollars** in the fixture. The simulator runtime reports
  `product.price` as the truncated integer of a fractional `displayPrice` (`"1.99"` arrives as
  `1.0`) while still formatting `displayPrice` as `"$1.99"`.
  (**Giá trong fixture phải tròn đô.** Simulator runtime trả `product.price` là phần nguyên đã
  bị cắt của `displayPrice` thập phân — `"1.99"` thành `1.0` — nhưng vẫn format ra `"$1.99"`.)
- **`expireSubscription` alone does not lapse anything**, because auto-renew is on by default
  and StoreKit immediately issues a renewal — correct App Store behaviour. The `lapse(_:)`
  helper cancels auto-renew first.
  (**Chỉ gọi `expireSubscription` thì không làm hết hạn được**, vì tự gia hạn bật theo mặc định
  và StoreKit lập tức tạo kỳ gia hạn mới — đúng hành vi App Store. Helper `lapse(_:)` tắt tự
  gia hạn trước.)
- **Expiry and revocation propagate asynchronously**, so assertions after them poll via
  `waitUntilResolved(_:_:_:)` rather than reading once. Asserting immediately made those tests
  pass or fail depending on timing.
  (**Hết hạn và thu hồi lan truyền bất đồng bộ**, nên assertion sau đó dùng
  `waitUntilResolved(_:_:_:)` để poll thay vì đọc một lần. Assert ngay lập tức khiến các test
  đó pass/fail tuỳ thời điểm.)
- **Still not covered:** `willRenew == false` while a subscription is still active, billing
  retry and the grace period. `SKTestSession` can drive these via
  `disableAutoRenewForTransaction(identifier:)`, `shouldEnterBillingRetryOnRenewal` and
  `billingGracePeriodIsEnabled` — worth adding.
  (**Vẫn chưa phủ:** `willRenew == false` khi subscription còn hiệu lực, billing retry và grace
  period. `SKTestSession` làm được qua `disableAutoRenewForTransaction(identifier:)`,
  `shouldEnterBillingRetryOnRenewal` và `billingGracePeriodIsEnabled` — nên bổ sung.)
