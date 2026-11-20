# TNSubscriptionIOS

A reusable Swift Package for iOS subscription management, with **three interchangeable billing engines** behind one API: RevenueCat, Adapty, or pure Apple StoreKit 2. (Gói Swift Package tái sử dụng cho quản lý subscription iOS, với **ba engine thanh toán thay thế được cho nhau** dưới cùng một API: RevenueCat, Adapty, hoặc thuần Apple StoreKit 2.)

- **Pick the engine per app** — configuration and the common API are identical in all three; see [what is the same and what differs](#what-is-the-same-what-differs-cái-gì-giống-cái-gì-khác) (**Chọn engine theo từng app** — cấu hình và phần API chung giống hệt nhau ở cả ba; xem [cái gì giống, cái gì khác](#what-is-the-same-what-differs-cái-gì-giống-cái-gì-khác))
- Built-in paywall UI **or** bring your own custom paywall (Paywall có sẵn **hoặc** tự custom hoàn toàn)
- **Multiple entitlements** support (Hỗ trợ **nhiều entitlements**)
- **Introductory and promotional offers**, plus App Store offer codes; iOS 18 **win-back** offers in `TNSubscriptionCore` and `TNSubscriptionAdapty` (Ưu đãi **người mới và promotional**, cùng offer code của App Store; ưu đãi **win-back** của iOS 18 trong `TNSubscriptionCore` và `TNSubscriptionAdapty`)
- **Consumables & virtual currency** — local coin/gem balances in every engine, plus cloud-synced RevenueCat In-App Currencies in `TNSubscriptionIOS` (**Consumable & tiền tệ ảo** — số dư coin/gem cục bộ ở mọi engine, cùng tiền tệ ảo đồng bộ cloud của RevenueCat trong `TNSubscriptionIOS`)
- **No paywall flicker for paying users** — a warm-start cache unlocks them before the first network call (**Không nhoáng paywall với người đã trả tiền** — warm-start cache mở khoá trước cả lần gọi mạng đầu tiên)
- Works with both **UIKit** and **SwiftUI** (Hoạt động với cả **UIKit** và **SwiftUI**)
- **Diagnostics**: log levels, a pluggable log handler, API key validation and readable failure reasons (**Chẩn đoán**: mức log, log handler tùy biến, validate API key và lý do lỗi rõ ràng)

### Used in production (Đang chạy thực tế)

| App | Engine | Version |
|---|---|---|
| [GameLens AI](https://apps.apple.com/us/app/gamelens-ai/id6787904202) | `TNSubscriptionIOS` (RevenueCat) | 1.1.3 |
| [PitchLab Soccer](https://apps.apple.com/us/app/pitchlab-soccer/id6774099988) | `TNSubscriptionIOS` (RevenueCat) | 1.1.3 |

…plus other apps not listed here. (…cùng nhiều app khác không liệt kê ở đây.)

The RevenueCat engine's purchase, restore and entitlement logic is unchanged from 1.1.3 to 1.3.0;
1.3.0 moves the configuration into a shared module and adds a savings badge to the built-in paywall.
(Logic mua, khôi phục và xác định quyền lợi của engine RevenueCat không đổi từ 1.1.3 tới 1.3.0;
bản 1.3.0 chuyển cấu hình sang module chung và thêm nhãn tiết kiệm vào paywall có sẵn.)

These apps have paying subscribers and run the RevenueCat engine. `TNSubscriptionCore` and
`TNSubscriptionAdapty` are covered by automated tests but are not yet used in a shipping app.
(Các app này có người dùng trả phí và chạy engine RevenueCat. `TNSubscriptionCore` và
`TNSubscriptionAdapty` đã có test tự động nhưng chưa được dùng trong app đang phát hành.)

### Choosing an engine (Chọn engine)

Each engine is a separate library product that links exactly one billing SDK — or none.
(Mỗi engine là một library product riêng, chỉ link đúng một SDK thanh toán — hoặc không SDK nào.)

**The configuration is shared, not copied.** `TNSubscriptionConfig`, `TNEntitlement`, `TNOffering`,
`TNLogLevel`, `DefaultPaywallConfig` and `TNConsumableProduct` are a single type each, re-exported by
every engine, and every engine names its entry point `TNSubscription` too. So this setup is the
same whichever engine you import:
(**Cấu hình được dùng chung, không phải sao chép.** Mỗi kiểu cấu hình chỉ có một bản duy nhất, được
mọi engine re-export, và engine nào cũng có điểm vào tên `TNSubscription`. Vì vậy đoạn cấu hình này
giống hệt nhau dù bạn import engine nào:)

```swift
import TNSubscriptionIOS        // or TNSubscriptionAdapty, or TNSubscriptionCore

TNSubscription.configure(config: TNSubscriptionConfig(
    apiKey: "…",                // ignored (with a warning) by Core
    entitlements: [TNEntitlement(id: "Premium", productIDs: ["com.app.weekly", "com.app.yearly"])],
    currentOfferingIdentifier: "main"
))

if TNSubscription.shared.isPremium { … }
TNSubscription.presentDefaultPaywall(from: viewController, config: DefaultPaywallConfig(appName: "My App"))
```

A setting an engine cannot honour — say `observerMode` on RevenueCat — is ignored and logged at
`configure`, never silently dropped. (Thiết lập nào engine không áp dụng được — ví dụ `observerMode`
trên RevenueCat — sẽ bị bỏ qua và ghi log lúc `configure`, không bao giờ âm thầm bị bỏ.)

- **`TNSubscriptionIOS`** — RevenueCat. Documented in the rest of this README. (RevenueCat. Được mô tả trong phần còn lại của README này.)
- **`TNSubscriptionAdapty`** — Adapty: access levels, A/B-tested placements, server-signed offers. See [ADAPTY.md](ADAPTY.md). (Adapty: access level, placement có A/B test, ưu đãi ký phía server. Xem [ADAPTY.md](ADAPTY.md).)
- **`TNSubscriptionCore`** — pure Apple StoreKit 2, zero dependencies, no API key. See [CORE.md](CORE.md). (Thuần Apple StoreKit 2, không dependency, không API key. Xem [CORE.md](CORE.md).)

**Which one? (Chọn cái nào?)**

- **iOS-only app, no vendor account wanted, works offline** → `TNSubscriptionCore`.
  (App chỉ có iOS, không muốn tài khoản bên thứ ba, cần chạy offline → `TNSubscriptionCore`.)
- **Subscriptions shared with Android or the web, or you want revenue charts** → `TNSubscriptionIOS`
  or `TNSubscriptionAdapty`. (Subscription dùng chung với Android hoặc web, hoặc cần biểu đồ doanh thu
  → `TNSubscriptionIOS` hoặc `TNSubscriptionAdapty`.)
- **A/B-testing paywalls from a dashboard** → `TNSubscriptionAdapty`.
  (A/B test paywall từ dashboard → `TNSubscriptionAdapty`.)
- **Already on RevenueCat, or need cloud-synced virtual currency** → `TNSubscriptionIOS`.
  (Đang dùng RevenueCat, hoặc cần tiền tệ ảo đồng bộ cloud → `TNSubscriptionIOS`.)

| | `TNSubscriptionIOS` | `TNSubscriptionCore` | `TNSubscriptionAdapty` |
|---|---|---|---|
| Dependency | RevenueCat | *none (không có)* | Adapty 4.x |
| API key | `appl_…` | none (không cần) | `public_live_…` |
| Cross-platform entitlements (Quyền lợi đa nền tảng) | ✅ | ❌ Apple ID only | ✅ |
| Offerings | dashboard | declared in code (khai báo trong code) | dashboard placements + A/B tests |
| Promotional offer signing (Ký promotional offer) | RevenueCat server | your server (server bạn) | Adapty server |
| Virtual currency | RevenueCat server | local / your server (cục bộ / server bạn) | local / your server |
| Works offline (Hoạt động offline) | cache | ✅ native (gốc) | ✅ StoreKit fallback |

> **Xcode 26+ is required to resolve this package** (Adapty 4.x needs Swift tools 6.2). App Store
> Connect has required Xcode 26 builds since 28 April 2026. (**Cần Xcode 26+ để resolve package này**
> (Adapty 4.x cần Swift tools 6.2). App Store Connect đã bắt buộc build bằng Xcode 26 từ 28/04/2026.)

### What is the same, what differs (Cái gì giống, cái gì khác)

**Identical in all three engines.** Everything in this table is enforced by a contract test
(`TNEngineContractTests`) that is compiled against each engine — if one engine drifts, its build
fails. Code that sticks to this table switches engine by changing only the `import`.
(**Giống hệt nhau ở cả ba engine.** Mọi thứ trong bảng này được bảo đảm bằng một test contract
(`TNEngineContractTests`) compile với từng engine — engine nào lệch thì build của nó fail. Code chỉ
dùng những gì trong bảng này thì đổi engine chỉ cần đổi `import`.)

| Area (Nhóm) | API |
|---|---|
| Configuration (Cấu hình) | `TNSubscriptionConfig`, `TNEntitlement`, `TNOffering`, `TNLogLevel` |
| Entry point (Điểm vào) | `TNSubscription.configure(config:)`, `TNSubscription.shared` |
| Status (Trạng thái) | `isPremium`, `activeEntitlements`, `entitlementState`, `hasEntitlement(_:)`, `productIDs(for:)`, `currentPlanProductID`, `currentPlanDisplayName`, `currentProductID(for:)`, `entitlementError` |
| Loading & actions (Tải & thao tác) | `checkSubscriptionStatus()`, `resolveEntitlement()`, `fetchOfferings(offeringIdentifier:)`, `loadOfferings(offeringIdentifier:)`, `isLoadingOfferings`, `offeringsError`, `isPurchasing`, `restorePurchases(completion:)`, `restorePurchasesAsync()`, `presentOfferCodeRedemption()` |
| Paywall | `DefaultPaywallConfig`, `TNDefaultPaywallView`, `TNSubscription.presentDefaultPaywall(from:config:)`, `TNSubscription.presentPaywall(from:content:)` |
| Consumables | `TNConsumableProduct`, `TNConsumableManager.configure(products:)`, `loadProducts()`, `purchaseAsync(productId:)`, `balance(for:)`, `canAfford(_:currency:)`, `addBalance(_:for:)`, `deductBalance(_:for:)`, `setBalance(_:for:)` |
| Identity & logs (Danh tính & log) | `TNSubscription.clientId`, `deviceId`, `identityHeaders(userId:)`, `displayName(forProductID:)`, `logLevel`, `logHandler` |

**Different between engines.** (Khác nhau giữa các engine.)

**1. Packages, purchases and customer info.** `TNSubscriptionIOS` exposes RevenueCat's own types;
the other two use the package's types. This was kept on purpose, so existing RevenueCat apps did not
break. (**Gói, giao dịch mua và thông tin khách hàng.** `TNSubscriptionIOS` dùng kiểu của chính
RevenueCat; hai engine còn lại dùng kiểu của package. Giữ nguyên có chủ đích, để các app RevenueCat
đang chạy không bị vỡ build.)

| API | `TNSubscriptionIOS` | `TNSubscriptionCore` / `TNSubscriptionAdapty` |
|---|---|---|
| `availablePackages` | `[Package]` (RevenueCat) | `[TNPackage]` |
| `customerInfo` | `CustomerInfo?` (RevenueCat) | `TNCustomerInfo?` |
| `purchaseAsync(package:)` | takes `Package`, returns `CustomerInfo` | takes `TNPackage`, returns `TNCustomerInfo` |
| `introOffer(for:)` | `StoreProductDiscount?` | `TNSubscriptionOffer?` |
| `introEligibility` | `[String: IntroEligibilityStatus]` | `[String: TNIntroEligibilityStatus]` |

Core's and Adapty's `TNPackage` / `TNCustomerInfo` are also two separate types: their common
properties have the same names (`productIdentifier`, `localizedPriceString`, `packageType`,
`pricePerMonth`, `entitlements`, …), so most code carries over, but each adds engine-specific
properties and the contract test does not cover them. (`TNPackage` / `TNCustomerInfo` của Core và
Adapty cũng là hai kiểu riêng: các thuộc tính chung trùng tên nên phần lớn code dùng lại được,
nhưng mỗi bên có thuộc tính riêng và test contract không bao phủ phần này.)

**2. Features only some engines have.** (Tính năng chỉ một số engine có.)

| Feature (Tính năng) | RevenueCat | Core | Adapty |
|---|---|---|---|
| Cloud virtual currency — `TNInAppCurrencyManager` | ✅ | — | — |
| Vendor's own paywall, designed in their dashboard (Paywall của nhà cung cấp, thiết kế trên dashboard) | ✅ RevenueCatUI — [§3 Option C](#option-c-revenuecats-own-paywall--revenuecatui-paywall-của-chính-revenuecat) | — | ✅ AdaptyUI — [ADAPTY.md §4.1](ADAPTY.md) |
| `entitlementInfo(for:)` — expiry, renewal, billing issues | — | ✅ | ✅ |
| `showManageSubscriptions()`, `requestRefund(for:)` | — | ✅ | ✅ |
| `cachedIsPremium` — read from a background thread without `await` | — | ✅ | ✅ |
| `currentOfferingMetadata` | — | ✅ | ✅ |
| `updateOfferings(_:current:)`, `configurePromotionalOfferSigner(_:)` | — | ✅ | — |
| `identify(_:)`, `logout()`, `logPaywallShown()`, `offer(for:)`, `waitUntilAdaptyActivated()` | — | — | ✅ |
| Server-authoritative spending (Tiêu qua server) | on `TNInAppCurrencyManager` | on `TNConsumableManager` | on `TNConsumableManager` |

**3. Concurrency.** `TNSubscriptionCore` and `TNSubscriptionAdapty` are `@MainActor`; call them with
`await` from background code, or read `cachedIsPremium`. `TNSubscriptionIOS` is not main-actor
isolated. (**Concurrency.** `TNSubscriptionCore` và `TNSubscriptionAdapty` là `@MainActor`; gọi từ
background thì dùng `await`, hoặc đọc `cachedIsPremium`. `TNSubscriptionIOS` không bị cô lập trên
main actor.)

**Rule of thumb.** (Quy tắc dễ nhớ.)

- Only the "identical" table above → switching engine is an `import` change.
  (Chỉ dùng bảng "giống hệt" ở trên → đổi engine chỉ là đổi `import`.)
- A custom paywall that lists packages or reads `customerInfo` → that part needs rewriting when moving
  to or from RevenueCat; between Core and Adapty it mostly carries over.
  (Paywall tự viết có liệt kê gói hoặc đọc `customerInfo` → phần đó phải viết lại khi chuyển sang hoặc
  rời RevenueCat; giữa Core và Adapty thì phần lớn dùng lại được.)
- An engine-only feature → rewrite or remove it.
  (Tính năng riêng của một engine → viết lại hoặc bỏ đi.)

---

## Requirements (Yêu cầu)

- iOS 16.0+
- Xcode 26+ (Swift 6.2 toolchain), required to resolve the package because of Adapty 4.x
  (Xcode 26+, bắt buộc để resolve package vì Adapty 4.x)
- RevenueCat account & API key — for `TNSubscriptionIOS` only (chỉ cho `TNSubscriptionIOS`)

---

## Installation (Cài đặt)

### Swift Package Manager

In Xcode: **File → Add Package Dependencies** → paste: (Trong Xcode: **File → Add Package Dependencies** → dán:)

```
https://github.com/thienkk25/TNSubscriptionIOS.git
```

Or add to your `Package.swift`: (Hoặc thêm vào `Package.swift`:)

```swift
.package(url: "https://github.com/thienkk25/TNSubscriptionIOS.git", from: "1.0.0"),
```

### Local Package

Drag the `TNSubscriptionIOS` folder into your Xcode project, then: (Kéo thư mục `TNSubscriptionIOS` vào Xcode project, sau đó:)  
**Target → General → Frameworks → Add → TNSubscriptionIOS**

---

> **Sections 1–8 below document `TNSubscriptionIOS` (RevenueCat).** The configuration and everything
> in [the identical table](#what-is-the-same-what-differs-cái-gì-giống-cái-gì-khác) work the same on every engine. For anything else, see
> [ADAPTY.md](ADAPTY.md) or [CORE.md](CORE.md).
> (**Mục 1–8 dưới đây là tài liệu cho `TNSubscriptionIOS` (RevenueCat).** Phần cấu hình và mọi thứ
> trong [bảng giống hệt](#what-is-the-same-what-differs-cái-gì-giống-cái-gì-khác) dùng y như nhau ở mọi engine. Phần còn lại xem
> [ADAPTY.md](ADAPTY.md) hoặc [CORE.md](CORE.md).)

## 1. Configure (Cấu hình)

> Call once at app launch. (Gọi 1 lần khi app khởi động.)

### UIKit — AppDelegate

```swift
import TNSubscriptionIOS

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        TNSubscriptionIOS.configure(config: TNSubscriptionConfig(
            apiKey: "appl_YOUR_REVENUECAT_API_KEY",
            entitlements: [
                TNEntitlement(id: "Premium", productIDs: [
                    "com.yourcompany.yourapp.weekly",     // ← Replace with your Product IDs (Thay bằng Product IDs của bạn)
                    "com.yourcompany.yourapp.monthly",
                    "com.yourcompany.yourapp.yearly"
                ]),
                TNEntitlement(id: "Sale", productIDs: [
                    "com.yourcompany.yourapp.sale_yearly"  // ← Sale-specific Product IDs (Product IDs riêng cho Sale)
                ]),
            ]
        ))
        
        return true
    }
}
```

### SwiftUI — App struct

```swift
import TNSubscriptionIOS

@main
struct MyApp: App {
    init() {
        TNSubscriptionIOS.configure(config: TNSubscriptionConfig(
            apiKey: "appl_YOUR_REVENUECAT_API_KEY",
            entitlements: [
                TNEntitlement(id: "Premium", productIDs: [
                    "com.yourcompany.yourapp.weekly",     // ← Replace with your Product IDs
                    "com.yourcompany.yourapp.monthly",
                    "com.yourcompany.yourapp.yearly"
                ]),
                TNEntitlement(id: "Sale", productIDs: [
                    "com.yourcompany.yourapp.sale_yearly"  // ← Sale-specific Product IDs
                ]),
            ]
        ))
    }
    
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### Single Entitlement (1 Entitlement duy nhất)

If your app only has 1 entitlement, use this shorthand: (Nếu app chỉ có 1 entitlement, dùng cú pháp ngắn:)

```swift
TNSubscriptionIOS.configure(config: TNSubscriptionConfig(
    apiKey: "appl_YOUR_REVENUECAT_API_KEY",
    entitlementId: "Premium",                   // ← Your Entitlement ID in RevenueCat (ID Entitlement trong RevenueCat)
    productIDs: [                                // ← Your StoreKit Product IDs (Product IDs trên StoreKit)
        "com.yourcompany.yourapp.weekly",
        "com.yourcompany.yourapp.monthly",
        "com.yourcompany.yourapp.yearly"
    ]
))
```

### Development Mode (Chế độ phát triển)

Bypass paywall during development: (Bỏ qua paywall khi dev/test:)

```swift
TNSubscriptionConfig(
    apiKey: "appl_xxx",
    entitlements: [...],
    isIAPEnabled: false  // All entitlements = active (Tất cả entitlements sẽ active)
)
```

---

## 2. Check Subscription Status (Kiểm tra trạng thái)

### UIKit (Combine)

```swift
import Combine
import TNSubscriptionIOS

class MyViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // One-time check (Kiểm tra 1 lần)
        if TNSubscriptionIOS.shared.isPremium {
            // User has premium (User đang có premium)
        }
        
        // Check specific entitlement (Kiểm tra entitlement cụ thể)
        if TNSubscriptionIOS.shared.hasEntitlement("Sale") {
            // User has sale plan (User đang có gói sale)
        }
        
        // Realtime observe — auto-update when user purchases/expires
        // (Lắng nghe realtime — tự update khi user mua/hết hạn)
        TNSubscriptionIOS.shared.$isPremium
            .receive(on: RunLoop.main)
            .sink { [weak self] isPremium in
                self?.updateUI(isPremium: isPremium)
            }
            .store(in: &cancellables)
        
        // Observe specific entitlements (Lắng nghe entitlements cụ thể)
        TNSubscriptionIOS.shared.$activeEntitlements
            .receive(on: RunLoop.main)
            .sink { [weak self] entitlements in
                let hasSale = entitlements.contains("Sale")
                self?.saleButton.isHidden = !hasSale
            }
            .store(in: &cancellables)
    }
}
```

### SwiftUI

```swift
import TNSubscriptionIOS

struct ContentView: View {
    @ObservedObject var sub = TNSubscriptionIOS.shared
    
    var body: some View {
        VStack {
            // Auto-update when status changes (Tự cập nhật khi trạng thái thay đổi)
            if sub.isPremium {
                Text("Welcome, Premium user!")
            } else {
                Text("Upgrade to unlock all features")
            }
            
            // Check specific entitlement (Kiểm tra entitlement cụ thể)
            if sub.hasEntitlement("Sale") {
                Text("🎉 Sale plan active!")
            }
            
            // Show all active entitlements (Hiển thị tất cả entitlements đang active)
            ForEach(Array(sub.activeEntitlements), id: \.self) { id in
                Label(id, systemImage: "checkmark.seal.fill")
            }
        }
    }
}
```

---

## 3. Present Paywall (Hiển thị Paywall)

Three ways, and you can mix them in one app (Ba cách, và có thể dùng lẫn trong cùng một app):

| | Design lives in (Thiết kế nằm ở) | Changes without an app update (Đổi không cần cập nhật app) |
|---|---|---|
| **A. Default paywall** | `DefaultPaywallConfig` in code | no |
| **B. Custom paywall** | your SwiftUI view | no |
| **C. RevenueCatUI** | RevenueCat dashboard | yes |

### Option A: Default Paywall (Paywall mặc định)

Package provides a built-in paywall. Just pass a config. (Package cung cấp paywall đẹp sẵn. Chỉ cần truyền config.)

#### UIKit

```swift
class SettingsViewController: UIViewController {
    @objc func upgradeTapped() {
        TNSubscriptionIOS.presentDefaultPaywall(from: self, config: DefaultPaywallConfig(
            appName: "<YOUR_APP_NAME>",           // ← e.g. "PitchLab", "PhotoEditor" (Tên app của bạn)
            features: [
                .init(icon: "star.fill",    title: "<Feature 1>", subtitle: "<Description 1>"),
                .init(icon: "bolt.fill",    title: "<Feature 2>", subtitle: "<Description 2>"),
                .init(icon: "icloud.fill",  title: "<Feature 3>", subtitle: "<Description 3>")
            ],
            privacyURL: URL(string: "https://<yoursite.com>/privacy"),
            termsURL: URL(string: "https://<yoursite.com>/terms"),
            accentColor: .cyan
        ))
    }
}
```

#### SwiftUI

```swift
struct SettingsView: View {
    @State private var showPaywall = false
    
    var body: some View {
        Button("Upgrade to Premium") { showPaywall = true }
        .sheet(isPresented: $showPaywall) {
            TNDefaultPaywallView(config: DefaultPaywallConfig(
                appName: "<YOUR_APP_NAME>",       // ← e.g. "PitchLab", "PhotoEditor" (Tên app của bạn)
                features: [
                    .init(icon: "star.fill",    title: "<Feature 1>", subtitle: "<Description 1>"),
                    .init(icon: "bolt.fill",    title: "<Feature 2>", subtitle: "<Description 2>"),
                ],
                accentColor: .orange
            ))
        }
    }
}
```

### Multiple Paywall Configs (Nhiều config paywall)

Define multiple configs and use them at different places in the app. (Định nghĩa nhiều config, dùng ở các chỗ khác nhau trong app.)

```swift
// Define once (Định nghĩa 1 lần)
enum PaywallConfigs {

    // Default paywall — standard price, cyan tone
    // (Paywall mặc định — giá gốc, tone xanh)
    static let `default` = DefaultPaywallConfig(
        appName: "<YOUR_APP_NAME>",               // ← e.g. "PitchLab" (Tên app của bạn)
        features: [
            .init(icon: "star.fill",    title: "<Feature 1>", subtitle: "<Description 1>"),
            .init(icon: "bolt.fill",    title: "<Feature 2>", subtitle: "<Description 2>"),
            .init(icon: "icloud.fill",  title: "<Feature 3>", subtitle: "<Description 3>")
        ],
        privacyURL: URL(string: "https://<yoursite.com>/privacy"),
        termsURL: URL(string: "https://<yoursite.com>/terms"),
        accentColor: .cyan
    )

    // Sale paywall — emphasize discount, red/orange tone
    // (Paywall sale — nhấn mạnh giảm giá, tone đỏ/cam)
    static let sale = DefaultPaywallConfig(
        appName: "<YOUR_APP_NAME> — 🔥 70% OFF",  // ← e.g. "PitchLab — 🔥 70% OFF" (Tên app + khuyến mãi)
        features: [
            .init(icon: "flame.fill",   title: "Limited Time Deal", subtitle: "Save 70% — ends soon!"),
            .init(icon: "star.fill",    title: "<Feature 1>", subtitle: "<Description 1>"),
            .init(icon: "bolt.fill",    title: "<Feature 2>", subtitle: "<Description 2>")
        ],
        offeringIdentifier: "sale",               // ← Optional: specific RevenueCat Offering ID (Tùy chọn: ID Offering trên RevenueCat)
        entitlementId: "Sale",                    // ← Optional: specific Entitlement ID (Tùy chọn: ID Entitlement mục tiêu)
        privacyURL: URL(string: "https://<yoursite.com>/privacy"),
        termsURL: URL(string: "https://<yoursite.com>/terms"),
        accentColor: .orange,
        secondaryColor: .red,
        backgroundColor: Color(red: 0.08, green: 0.02, blue: 0.02),
        premiumGradient: LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    )
}
```

```swift
// Use at different places (Dùng ở các chỗ khác nhau)

// Settings → default paywall (Settings → paywall mặc định)
TNSubscriptionIOS.presentDefaultPaywall(from: self, config: PaywallConfigs.default)

// Sale banner → sale paywall (Banner sale → paywall sale)
TNSubscriptionIOS.presentDefaultPaywall(from: self, config: PaywallConfigs.sale)
```

Same view, same purchase/restore logic — only UI and text differ. Which packages are displayed depends on the RevenueCat Offering set on dashboard. (Cùng view, cùng logic mua/restore — chỉ khác giao diện và text. Gói hiển thị phụ thuộc RevenueCat Offering set trên dashboard.)

### Option B: Custom Paywall (Paywall tự thiết kế hoàn toàn)

Design your own paywall, use only the core logic from the package. (Tự vẽ paywall, chỉ dùng core logic từ package.)

#### UIKit

```swift
class HomeViewController: UIViewController {
    @objc func showPaywall() {
        TNSubscriptionIOS.presentPaywall(from: self) {
            MyCustomPaywallView()
        }
    }
}
```

#### SwiftUI

```swift
struct HomeView: View {
    @State private var showPaywall = false
    
    var body: some View {
        Button("Upgrade") { showPaywall = true }
        .sheet(isPresented: $showPaywall) {
            MyCustomPaywallView()
        }
    }
}
```

#### Custom Paywall View Example (Ví dụ Custom Paywall View)

```swift
struct MyCustomPaywallView: View {
    @ObservedObject var manager = TNSubscriptionIOS.shared
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Go Premium").font(.largeTitle.bold())
                
                if manager.isLoadingOfferings {
                    ProgressView("Loading plans...")
                } else {
                    // Show packages (Hiển thị danh sách gói)
                    ForEach(manager.availablePackages, id: \.identifier) { pkg in
                        Button {
                            purchase(pkg)
                        } label: {
                            HStack {
                                Text(pkg.storeProduct.localizedTitle)
                                Spacer()
                                Text(pkg.storeProduct.localizedPriceString).bold()
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        }
                        .disabled(manager.isPurchasing)
                    }
                }
                
                if let error = errorMessage {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
                
                Button("Restore Purchases") {
                    manager.restorePurchases { result in
                        switch result {
                        case .success(let restored): if restored { dismiss() }
                        case .failure(let error): errorMessage = error.localizedDescription
                        }
                    }
                }
                .font(.subheadline)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { manager.fetchOfferings() }
    }
    
    private func purchase(_ package: Package) {
        manager.purchase(package: package) { result in
            switch result {
            case .success: dismiss()
            case .failure(let error):
                if let e = error as? TNSubscriptionIOS.PurchaseFlowError, case .userCancelled = e { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
```

### Option C: RevenueCat's own paywall — RevenueCatUI (Paywall của chính RevenueCat)

Use the paywalls you design in the RevenueCat dashboard instead of the package's UI.
(Dùng paywall bạn thiết kế trên dashboard RevenueCat thay cho giao diện của package.)

**Supported, not wrapped.** This package does not import RevenueCatUI, so it adds nothing to apps
that do not use it. Your app imports it directly, and the engine stays in sync on its own.
(**Được hỗ trợ, nhưng không được bọc.** Package không import RevenueCatUI, nên không làm nặng app
nào không dùng nó. App của bạn import trực tiếp, và engine tự đồng bộ trạng thái.)

**1. Add the product (Thêm product).** In Xcode: *Target → General → Frameworks → Add →
`RevenueCatUI`*. It comes from `purchases-ios-spm`, which this package already resolves, so there is
nothing new to download and the versions always match.
(Trong Xcode thêm product `RevenueCatUI`. Nó thuộc `purchases-ios-spm`, package này đã resolve sẵn,
nên không tải thêm gì và phiên bản luôn khớp nhau.)

**2. Configure as usual** — no extra step. (**Cấu hình như bình thường** — không cần bước nào thêm.)

**3. Present it.** (Hiển thị.)

SwiftUI — automatically, whenever `"Premium"` is not active:
(SwiftUI — tự động, mỗi khi `"Premium"` chưa hoạt động:)

```swift
import SwiftUI
import RevenueCatUI
import TNSubscriptionIOS

// MARK: SwiftUI — show RevenueCat's paywall automatically while "Premium" is missing.
struct RCHomeScreen: View {
    @ObservedObject private var subscription = TNSubscription.shared

    var body: some View {
        Text(subscription.isPremium ? "Premium" : "Free")
            .presentPaywallIfNeeded(requiredEntitlementIdentifier: "Premium")
    }
}
```

SwiftUI — on demand (SwiftUI — khi người dùng bấm):

```swift
// MARK: SwiftUI — show it on demand.
struct RCUpgradeButton: View {
    @State private var showPaywall = false

    var body: some View {
        Button("Upgrade") { showPaywall = true }
            .sheet(isPresented: $showPaywall) {
                PaywallView(displayCloseButton: true)
            }
    }
}
```

UIKit:

```swift
import UIKit
import RevenueCat
import RevenueCatUI
import TNSubscriptionIOS

// MARK: UIKit
final class RCSettingsViewController: UIViewController, @preconcurrency PaywallViewControllerDelegate {
    func showUpgrade() {
        let paywall = PaywallViewController(displayCloseButton: true)
        paywall.delegate = self
        present(paywall, animated: true)
    }

    func paywallViewController(_ controller: PaywallViewController,
                               didFinishPurchasingWith customerInfo: CustomerInfo) {
        controller.dismiss(animated: true)
    }
}
```

**What updates by itself after a purchase.** The engine registers itself as RevenueCat's
`Purchases.shared.delegate`, and RevenueCat calls it whenever `CustomerInfo` changes — including
after a purchase or restore made through RevenueCatUI. So `isPremium`, `activeEntitlements`,
`entitlementState` and `customerInfo` update without any code from you.
(**Những gì tự cập nhật sau khi mua.** Engine tự đăng ký làm `Purchases.shared.delegate` của RevenueCat, và
RevenueCat gọi nó mỗi khi `CustomerInfo` thay đổi — kể cả sau khi mua hoặc khôi phục qua RevenueCatUI.
Vì vậy `isPremium`, `activeEntitlements`, `entitlementState` và `customerInfo` tự cập nhật, bạn không
phải viết gì thêm.)

**Rules (Quy tắc):**

- **Never assign `Purchases.shared.delegate` yourself.** RevenueCat has a single delegate; replacing
  it silently disconnects the engine and `isPremium` stops updating. Use the paywall's own callbacks
  (`PaywallViewControllerDelegate`, or the `presentPaywallIfNeeded` handlers) instead. RevenueCatUI
  itself does not touch the delegate.
  (**Không bao giờ tự gán `Purchases.shared.delegate`.** RevenueCat chỉ có một delegate; gán đè sẽ âm
  thầm ngắt kết nối engine và `isPremium` ngừng cập nhật. Hãy dùng callback của chính paywall. Bản
  thân RevenueCatUI không đụng vào delegate.)
- **`requiredEntitlementIdentifier` must be the same ID as your `TNEntitlement.id`**, i.e. the
  RevenueCat entitlement ID, spelt exactly the same.
  (**`requiredEntitlementIdentifier` phải trùng với `TNEntitlement.id`** — tức ID entitlement trên
  RevenueCat, viết chính xác như nhau.)
- **`isPurchasing` and `TNPurchaseError` do not apply.** The purchase runs inside RevenueCatUI, not
  through the engine, so react to the paywall's callbacks for progress and errors.
  (**`isPurchasing` và `TNPurchaseError` không áp dụng.** Giao dịch chạy bên trong RevenueCatUI chứ
  không qua engine, nên hãy dùng callback của paywall để theo dõi tiến trình và lỗi.)
- **`DefaultPaywallConfig` has no effect here.** Products, layout and copy come from the RevenueCat
  dashboard. (**`DefaultPaywallConfig` không có tác dụng ở đây.** Sản phẩm, bố cục và nội dung lấy từ
  dashboard RevenueCat.)
- **Swift 6 language mode:** declare the UIKit conformance as `@preconcurrency
  PaywallViewControllerDelegate`, as above — it is an Objective-C protocol without actor annotations.
  (**Swift 6 language mode:** khai báo conformance UIKit là `@preconcurrency
  PaywallViewControllerDelegate` như trên — đây là protocol Objective-C chưa có chú thích actor.)

---

## 4. Premium Gating (Khóa feature theo subscription)

Show paywall when user taps a locked feature. (Hiện paywall khi user bấm vào feature bị khóa.)

> **`isPremium`** = `true` if **any** entitlement is active — use for features all paying users can access. (Dùng cho feature mà tất cả user trả phí đều được dùng.)  
> **`hasEntitlement("X")`** = check **specific** entitlement — use when different entitlements unlock different features. (Dùng khi mỗi entitlement mở khóa feature khác nhau.)

### UIKit

> Uses `PaywallConfigs` defined in [Section 3 — Multiple Paywall Configs](#multiple-paywall-configs-nhiều-config-paywall).
> (Dùng `PaywallConfigs` đã định nghĩa ở Mục 3.)

```swift
// Recap: PaywallConfigs was defined earlier (Nhắc lại: PaywallConfigs đã định nghĩa ở trên)
// enum PaywallConfigs {
//     static let `default` = DefaultPaywallConfig(appName: "<YOUR_APP_NAME>", features: [...], accentColor: .cyan)
//     static let sale = DefaultPaywallConfig(appName: "<YOUR_APP_NAME> — 🔥 70% OFF", features: [...], accentColor: .orange)
// }

// ✅ isPremium — any paying user can access (bất kỳ user trả phí nào cũng dùng được)
@objc func removeAdsTapped() {
    guard TNSubscriptionIOS.shared.isPremium else {
        TNSubscriptionIOS.presentDefaultPaywall(from: self, config: PaywallConfigs.default)
        return
    }
    removeAds()
}

// ✅ hasEntitlement — only "Premium" entitlement can access (chỉ user có entitlement "Premium" mới dùng được)
@objc func aiFeatureTapped() {
    guard TNSubscriptionIOS.shared.hasEntitlement("Premium") else {
        TNSubscriptionIOS.presentDefaultPaywall(from: self, config: PaywallConfigs.default)
        return
    }
    showAIFeature()
}

// ✅ hasEntitlement — only "Sale" entitlement can access (chỉ user có entitlement "Sale" mới dùng được)
@objc func saleFeatureTapped() {
    guard TNSubscriptionIOS.shared.hasEntitlement("Sale") else {
        TNSubscriptionIOS.presentDefaultPaywall(from: self, config: PaywallConfigs.sale)
        return
    }
    showSaleContent()
}
```

### SwiftUI

```swift
struct FeatureView: View {
    @ObservedObject var sub = TNSubscriptionIOS.shared
    @State private var showPaywall = false
    
    var body: some View {
        VStack {
            if sub.isPremium {
                PremiumContentView()
            } else {
                Button("🔒 Unlock Premium") { showPaywall = true }
            }
        }
        .sheet(isPresented: $showPaywall) {
            TNDefaultPaywallView(config: PaywallConfigs.default)
        }
    }
}
```

---

## 4.1. Introductory Offers, Promotional Offers & Offer Codes (Ưu đãi người mới, Khuyến mãi giữ chân & Mã ưu đãi)

### A. Introductory Offers — Free Trial / New User Pricing (Ưu đãi cho người mới)

When `fetchOfferings()` runs, the SDK automatically queries Apple/RevenueCat (`checkTrialOrIntroDiscountEligibility`) to check whether the user is a **new subscriber** eligible for a Free Trial or Introductory Price:
(Khi gọi `fetchOfferings()`, package tự động kiểm tra xem Apple ID của user có phải **người mới** đủ điều kiện nhận Dùng thử miễn phí / Giá ưu đãi kỳ đầu hay không:)

- **On `TNDefaultPaywallView` (Tự động trên Paywall mặc định)**:
  - **Eligible (Đủ điều kiện — Người mới)**: Automatically displays the `FREE TRIAL` / `INTRO OFFER` badge, shows the trial/intro summary (e.g. `"3 Days Free Trial · Then $9.99"`), and updates the CTA button to **"Start Free Trial"** or **"Claim Intro Offer"**.
  - **Ineligible (Không đủ điều kiện — Người cũ đã dùng thử)**: Automatically hides the trial text and displays the regular renewal price + **"Continue"** button.

- **In Custom Paywall / Code (Kiểm tra thủ công trong Custom Paywall)**:
```swift
let sub = TNSubscriptionIOS.shared

for package in sub.availablePackages {
    // 1. Check if user is eligible for intro offer / free trial (Kiểm tra có đủ điều kiện người mới không)
    if sub.isEligibleForIntroOffer(package: package) {
        // 2. Get formatted summary, e.g. "3 Days Free Trial" or "$0.99 for 1 Month"
        // (Lấy chuỗi mô tả ưu đãi đã format sẵn)
        let summary = sub.introOfferSummary(for: package) ?? "Free Trial"
        print("New user offer: \(summary)")
    }
}
```

### B. Promotional Offers — Win-back / Retention Offers (Ưu đãi cho người cũ / giữ chân)

> Requires uploading your App Store Connect **In-App Purchase Key (`.p8`)** to RevenueCat Dashboard so RevenueCat can sign the promotional offer.
> (Yêu cầu tải file khóa `.p8` từ App Store Connect lên RevenueCat Dashboard để ký xác thực ưu đãi.)

```swift
let sub = TNSubscriptionIOS.shared

// 1. Check all promotional discounts configured on the package (Lấy danh sách discount của gói)
let discounts = sub.promotionalDiscounts(for: package)

if let promoDiscount = discounts.first {
    // 2. Automatically sign via RevenueCat & purchase (Tự động ký qua RevenueCat và thanh toán)
    sub.purchasePromotionalOffer(package: package, discount: promoDiscount) { result in
        switch result {
        case .success(let customerInfo):
            print("Promotional offer purchased!")
        case .failure(let error):
            print("Error: \(error.localizedDescription)")
        }
    }
}
```

### C. Offer Codes — App Store Redemption Sheet (Nhập mã ưu đãi)

- **Built-in Paywall**: Shows a **"Redeem Code"** button in the footer by default (hide via `DefaultPaywallConfig(showRedeemCodeButton: false)`).
- **Custom UI**: Call `TNSubscriptionIOS.shared.presentOfferCodeRedemption()` to open iOS's native code redemption sheet.

---

## 5. Consumable Purchases (Mua consumable — coins, gems, credits)

> For one-time purchases that add a quantity (e.g. coins, gems, credits).
> (Cho việc mua 1 lần để cộng số lượng, ví dụ coins, gems, credits.)

### Configure (Cấu hình)

```swift
// At app launch, after TNSubscriptionIOS.configure(...)
// (Khi app khởi động, sau TNSubscriptionIOS.configure(...))
TNConsumableManager.configure(products: [
    TNConsumableProduct(id: "com.yourcompany.yourapp.100coins",  reward: 100,  currency: "coins"),
    TNConsumableProduct(id: "com.yourcompany.yourapp.500coins",  reward: 500,  currency: "coins"),
    TNConsumableProduct(id: "com.yourcompany.yourapp.1500coins", reward: 1500, currency: "coins"),
])
```

### UIKit

```swift
import TNSubscriptionIOS
import Combine

class ShopViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()
    let consumable = TNConsumableManager.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Load products from App Store (Load sản phẩm từ App Store)
        consumable.loadProducts()
        
        // Observe balance changes (Lắng nghe thay đổi số dư)
        consumable.$balances
            .receive(on: RunLoop.main)
            .sink { [weak self] balances in
                let coins = balances["coins"] ?? 0
                self?.coinLabel.text = "\(coins) coins"
            }
            .store(in: &cancellables)
    }
    
    @objc func buy100CoinsTapped() {
        consumable.purchase(productId: "com.yourcompany.yourapp.100coins") { result in
            switch result {
            case .success(let reward):
                print("Added \(reward) coins!") // (Đã cộng \(reward) coins!)
            case .failure(let error):
                if let e = error as? TNConsumableManager.ConsumableError, case .userCancelled = e { return }
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    // Deduct coins when user spends (Trừ coins khi user tiêu)
    @objc func useFeatureTapped() {
        guard consumable.deductBalance(10, for: "coins") else {
            // Not enough coins → show shop (Không đủ coins → hiện shop)
            return
        }
        // Feature unlocked (Feature đã mở khóa)
        activateFeature()
    }
}
```

### SwiftUI

```swift
import TNSubscriptionIOS

struct CoinShopView: View {
    @ObservedObject var shop = TNConsumableManager.shared
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            // Current balance (Số dư hiện tại)
            Text("\(shop.balance(for: "coins")) 🪙")
                .font(.largeTitle.bold())
            
            if shop.isLoadingProducts {
                ProgressView("Loading...")
            } else {
                // Show available products (Hiển thị sản phẩm)
                ForEach(shop.storeProducts, id: \.id) { product in
                    Button {
                        buyProduct(product)
                    } label: {
                        HStack {
                            if let config = shop.consumableProduct(for: product.id) {
                                Text("+\(config.reward) \(config.currency)")
                            }
                            Spacer()
                            Text(product.displayPrice).bold()
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    }
                    .disabled(shop.isPurchasing)
                }
            }
            
            if let error = errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        }
        .padding()
        .onAppear { shop.loadProducts() }
    }
    
    private func buyProduct(_ product: Product) {
        shop.purchase(product: product) { result in
            switch result {
            case .success(let reward):
                errorMessage = nil
                print("+\(reward) coins!") // (Đã cộng \(reward) coins!)
            case .failure(let error):
                if let e = error as? TNConsumableManager.ConsumableError, case .userCancelled = e { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

// Spending coins (Tiêu coins)
struct GameView: View {
    @ObservedObject var shop = TNConsumableManager.shared
    
    var body: some View {
        Button("Use Hint (-10 coins)") {  // (Dùng gợi ý, -10 coins)
            if shop.deductBalance(10, for: "coins") {
                showHint()
            } else {
                // Not enough coins (Không đủ coins)
            }
        }
        .disabled(!shop.canAfford(10, currency: "coins"))
    }
}
```

---

## 6. RevenueCat In-App Currencies (Tiền tệ trong app / Virtual Currencies)

> Cloud-synced currencies (coins, gems, credits) managed directly by RevenueCat. (Tiền ảo lưu trữ và đồng bộ đám mây trực tiếp qua RevenueCat.)  
> Official Docs: [RevenueCat In-App Currency](https://www.revenuecat.com/docs/offerings/virtual-currency) (Tài liệu chính thức từ RevenueCat)

### Key Rules & Limits (Lưu ý quan trọng & Giới hạn từ RevenueCat)

- **Capacity & Limits (Giới hạn số lượng)**: Up to 100 currencies per project; balance between 0 and 2,000,000,000 (2 billion); negative balances not supported. (Tối đa 100 loại tiền tệ / project; số dư tối đa 2 tỷ; không hỗ trợ số dư âm.)
- **Non-transferable on Restore (Không chuyển giao khi Restore)**: Unlike subscriptions, virtual currencies cannot be transferred across accounts during restore. (Khác với subscription, tiền ảo không thể chuyển qua tài khoản khác khi restore.)
- **Auto-Expiration Priority (Thứ tự ưu tiên hết hạn)**: Expiring currencies are automatically consumed first by RevenueCat. (RevenueCat tự động ưu tiên trừ tiền sắp hết hạn trước.)
- **Server-Side Security (Bảo mật chi tiêu phía server)**: Currency deductions require Developer API with Secret Key — must be initiated via Backend or API Proxy Gateway, never from client directly. (Trừ tiền yêu cầu Secret Key qua Backend hoặc API Proxy Gateway, không nhúng key trên app client.)
- **Idempotency (Chống trùng giao dịch)**: Pass `Idempotency-Key` (UUID) to guarantee exactly-once execution during retries. (Header `Idempotency-Key` đảm bảo chỉ trừ tiền tối đa 1 lần khi mạng bị timeout/retry.)

### Consumables vs In-App Currencies: When to use which? (Khi nào dùng cái nào?)

| Feature (Tiêu chí) | `TNConsumableManager` (StoreKit 2) | `TNInAppCurrencyManager` (RevenueCat) |
|---|---|---|
| **Balance Storage (Lưu trữ số dư)** | Local device (`UserDefaults`) (Thiết bị cục bộ) | RevenueCat Cloud (Đồng bộ đám mây qua App User ID) |
| **Subscription Perks (Gắn với gói Subscription)** | Not supported (Không hỗ trợ tự cộng định kỳ) | ✅ Auto-refill on renewal (Tự cộng định kỳ mỗi chu kỳ gia hạn) |
| **Expiration (Hạn dùng)** | Not supported (Không hỗ trợ) | ✅ Configurable on dashboard (Cấu hình trên dashboard) |
| **Anti-cheat / Fraud (Chống gian lận)** | Basic local client (Cơ bản trên client) | ✅ Server-side validated (Bảo vệ và xác thực phía server) |
| **Restore Behavior (Khôi phục)** | Recovers unfinished transactions (Khôi phục giao dịch dang dở) | Tied to User ID, non-transferable (Gắn theo User ID, không chuyển nhượng) |

### Dashboard Setup (Cấu hình trên RevenueCat Dashboard)

1. Open RevenueCat Dashboard → Project → **Product Catalog** → **In-App Currencies**. (Mở RevenueCat Dashboard → chọn Project → Product Catalog → In-App Currencies.)
2. Click **+ New in-app currency** (e.g. Code: `coins`, Name: `Coins`). (Bấm + New in-app currency, ví dụ Code: `coins`, Name: `Coins`.)
3. Associate products with your currency: (Gắn sản phẩm vào loại tiền:)
   - **One-time purchase**: Grant a fixed amount of coins upon purchase (e.g. 500 coins). (Mua gói nhận số lượng cố định, ví dụ 500 coins.)
   - **Subscription**: Auto-grant recurring coins each renewal cycle. (Tự động cộng coins định kỳ mỗi chu kỳ gia hạn.)

### UIKit (Combine)

```swift
import UIKit
import Combine
import TNSubscriptionIOS

class CurrencyViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()
    let currencyManager = TNInAppCurrencyManager.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Fetch latest balances from RevenueCat (Tải số dư mới nhất từ RevenueCat)
        currencyManager.fetchCurrencies()
        
        // Realtime observe balances (Lắng nghe thay đổi số dư)
        currencyManager.$balances
            .receive(on: RunLoop.main)
            .sink { [weak self] balances in
                let coins = balances["coins"] ?? 0
                self?.coinsLabel.text = "🪙 \(coins)"
            }
            .store(in: &cancellables)
    }
}
```

### SwiftUI

```swift
import SwiftUI
import TNSubscriptionIOS

struct CurrencyBalanceBarView: View {
    @ObservedObject var currencies = TNInAppCurrencyManager.shared
    
    var body: some View {
        HStack(spacing: 16) {
            Label("\(currencies.balance(for: "coins"))", systemImage: "bitcoinsign.circle.fill")
                .foregroundColor(.yellow)
            
            Label("\(currencies.balance(for: "gems"))", systemImage: "diamond.fill")
                .foregroundColor(.cyan)
            
            if currencies.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .onAppear {
            // Fetch balances on appear (Tải số dư khi view xuất hiện)
            currencies.fetchCurrencies()
        }
    }
}
```

### Spending & Deductions (Chi tiêu & Trừ tiền)

Works **with or without a backend**: (Hoạt động **cả khi không có backend** hoặc **có backend**:)

#### Mode A: No-Backend / Serverless Mode — Keychain Persistent (Chế độ Không Backend — Mặc định ✅)
> If your app does **not** have a backend server, deductions and local rewards are automatically persisted in the **iOS Keychain** (`effectiveBalance = revenueCatCloudBalance + localKeychainOffset`). They survive `fetchCurrencies()` refreshes, app restarts, and app reinstalls!
> (Nếu dự án **không có backend**, số tiền trừ hoặc thưởng thêm được tự động lưu bền vững trong **Keychain**, kết hợp tự động với số dư cộng từ RevenueCat Cloud — không bị mất khi gọi `fetchCurrencies()`, tắt mở lại app hay cài đặt lại app!)

```swift
// 1. Deduct coins directly — persisted in Keychain (Trừ coins trực tiếp — lưu bền vững trong Keychain)
if TNInAppCurrencyManager.shared.deductLocalBalance(10, for: "coins") {
    // Unlocked feature! (Đã trừ 10 coins thành công)
}

// Or use spend(...) without configuring any backend handler (Hoặc dùng spend(...) mà không cần cấu hình backend)
TNInAppCurrencyManager.shared.spend(code: "coins", amount: 10) { result in
    if case .success(let newBalance) = result {
        print("Remaining coins: \(newBalance)")
    }
}

// 2. Grant local bonus coins, e.g. daily check-in or rewarded ads (Thưởng thêm coins cục bộ: điểm danh, xem quảng cáo...)
TNInAppCurrencyManager.shared.addLocalBalance(50, for: "coins")
```

#### Mode B: With Backend / API Proxy Gateway (Optional — Tùy chọn cho dự án có Backend)

If your project has a backend or uses TN Studio API Proxy Gateway: (Nếu dự án có server riêng hoặc dùng API Proxy:)

```swift
// Option B1: Purchase Item via Proxy — Client only sends itemId (Mua item qua Proxy)
guard let proxyURL = URL(string: "https://your-api.com/api/proxy/purchase-item") else { return }

TNInAppCurrencyManager.shared.purchaseItemViaProxy(
    proxyEndpoint: proxyURL,
    apiKey: "YOUR_APP_API_KEY",
    itemId: "premium_filter_pack"
) { result in ... }

// Option B2: Direct Amount Spend via Proxy (Trừ theo số lượng qua Proxy)
guard let spendURL = URL(string: "https://your-api.com/api/proxy/spend") else { return }

TNInAppCurrencyManager.shared.spendViaProxy(
    proxyEndpoint: spendURL,
    apiKey: "YOUR_APP_API_KEY",
    code: "coins",
    amount: 10
) { result in ... }

// Option B3: Custom Backend Spend Handler (Tự gắn hàm gọi API riêng)
TNInAppCurrencyManager.shared.configureSpendHandler { code, amount, reference in
    return try await MyBackendAPI.deductCurrency(code: code, amount: amount, ref: reference)
}
```

---

## 7. [Optional] Persistent Client Identity for Backend APIs (Tùy chọn — Chỉ dành cho dự án có Backend API)

> **Skip this section if your app has no backend.** By default, `TNSubscriptionIOS` runs 100% serverless without generating or syncing `clientId` until you explicitly call `TNSubscriptionIOS.clientId` or `request.applyTNIdentityHeaders()`.
> (**Bỏ qua mục này nếu dự án không có backend.** Mặc định package chạy độc lập hoàn toàn, không sinh hay đồng bộ `clientId` cho đến khi bạn chủ động gọi `TNSubscriptionIOS.clientId` hoặc `applyTNIdentityHeaders()`.)

When your app calls a custom backend API or proxy gateway, attach these headers for rate-limiting and spam detection: (Khi app có gọi API Backend hoặc proxy gateway, gắn các headers sau để định danh client và chống spam:)

### Standard Identity Headers (Bảng headers định danh tiêu chuẩn)

| Header | Value (Giá trị) | Purpose (Mục đích) |
|---|---|---|
| `X-Client-Id` | `TNSubscriptionIOS.clientId` | Unique install UUID across sessions & reinstalls (UUID duy nhất theo lượt cài đặt, bền vững qua các phiên và cài lại app) |
| `X-Device-Id` | `TNSubscriptionIOS.deviceId` | Apple hardware vendor device identifier (Định danh thiết bị phần cứng từ Apple) |
| `X-User-Id` | User / Account ID (Optional) (Tùy chọn) | Authenticated user account identifier (ID tài khoản người dùng sau khi đăng nhập) |

### Usage Example (Ví dụ sử dụng)

```swift
var request = URLRequest(url: backendURL)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

// One-line helper (Gắn nhanh chỉ với 1 dòng)
request.applyTNIdentityHeaders(userId: currentUserId)
```

---

## 8. Diagnostics & Logging (Chẩn đoán & Log)

When a purchase succeeds but nothing unlocks, or the paywall shows no plans, this is where you look first.
(Khi mua xong mà không mở khóa, hoặc paywall không có gói nào, hãy xem ở đây trước.)

### Log Levels (Các mức log)

| Level | What you get (Nội dung) |
|---|---|
| `.verbose` | Every step, including each StoreKit transaction inspected, plus RevenueCat's own SDK logs |
| `.debug` | Entitlement resolution details — which source won, what resolved |
| `.info` | **Default in DEBUG.** Configuration, unlocks, purchases, restores |
| `.warn` | Misconfiguration and recoverable fallbacks |
| `.error` | **Default in Release.** Failures only |
| `.none` | Silent |

### Setting the Level (Đặt mức log)

```swift
TNSubscriptionIOS.configure(config: TNSubscriptionConfig(
    apiKey: "appl_YOUR_KEY",
    entitlements: [TNEntitlement(id: "Premium", productIDs: ["com.app.weekly"])],
    logLevel: .verbose    // ← troubleshooting (gỡ lỗi)
))

// Or change it at runtime, e.g. from a hidden debug menu
// (Hoặc đổi lúc chạy, ví dụ từ debug menu ẩn)
TNSubscriptionIOS.logLevel = .verbose
```

Setting `logLevel` also sets `Purchases.logLevel`, so RevenueCat reports exactly which product IDs it failed to fetch and why.
(Đặt `logLevel` cũng set luôn `Purchases.logLevel`, nên RevenueCat sẽ in rõ product ID nào fetch lỗi và vì sao.)

### Routing Logs to Your Own Stack (Đưa log vào hệ thống của bạn)

Set `logHandler` **before** `configure(...)` to also capture API key validation warnings. It receives TNSubscriptionIOS **and** RevenueCat SDK lines (the latter prefixed `[RevenueCat]`).
(Set `logHandler` **trước** `configure(...)` để bắt được cả cảnh báo validate API key.)

```swift
TNSubscriptionIOS.logHandler = { level, message in
    switch level {
    case .error, .warn:
        Crashlytics.crashlytics().log("[IAP][\(level)] \(message)")
    default:
        logger.debug("[IAP] \(message)")
    }
}
```

When no handler is installed, logs go to `print`.
(Không set handler thì log in ra `print`.)

### Reading Failures in Code (Đọc lỗi trong code)

Two published properties cover the two halves of an IAP failure:
(Hai property published phủ hai nửa của một lỗi IAP:)

| Property | Answers (Trả lời câu hỏi) |
|---|---|
| `offeringsError` | Why no plan could be **displayed** (Vì sao không hiện được gói nào) |
| `entitlementError` | Why a purchase could not be **verified** (Vì sao mua rồi mà không xác thực được) |

```swift
if let error = sub.offeringsError {
    // Products never loaded — show a retry, not a paywall with fake prices
    // (Product không load được — hiện nút thử lại, đừng hiện paywall với giá giả)
    showRetry(message: error)
}

if let error = sub.entitlementError {
    // The CHECK failed; this is NOT the same as the user being a non-subscriber
    // (Việc KIỂM TRA bị lỗi; khác với việc user chưa mua)
    showRetry(message: error)
}
```

> `entitlementError == nil` does **not** mean the user is premium — it only means the check completed. Read `isPremium` for entitlement status.
> (`entitlementError == nil` **không** có nghĩa là user đã premium — chỉ nghĩa là việc kiểm tra đã xong. Đọc `isPremium` để biết trạng thái.)

### API Key Validation (Kiểm tra API key)

`configure(...)` inspects the key prefix and reports the consequences:
(`configure(...)` kiểm tra prefix của key và cảnh báo hệ quả:)

| Prefix | Behaviour (Hành vi) |
|---|---|
| `appl_` | App Store. Products come from StoreKit — App Store Connect, or a `.storekit` file when the scheme uses one |
| `test_` | **RevenueCat Test Store.** Purchases are simulated and bypass StoreKit entirely; intro/promotional offers are not testable. Logs a warning in DEBUG, and an **error in Release** — the RevenueCat SDK deliberately crashes on a Test Store key in release builds (iOS SDK 5.89.0+) and App Review rejects such builds |
| anything else | Warns about an unrecognized prefix |

> Consumables bought through `TNConsumableManager` use **raw StoreKit 2**, not RevenueCat. The API key is irrelevant to them — a `test_` key cannot supply consumable products. They always need a `.storekit` configuration file or real App Store Connect products.
> (Consumable mua qua `TNConsumableManager` dùng **StoreKit 2 gốc**, không qua RevenueCat. API key không liên quan — key `test_` không cấp được product consumable. Luôn cần file `.storekit` hoặc product thật trên App Store Connect.)

Use build configurations to keep the two apart:
(Dùng build configuration để tách hai key:)

```swift
#if DEBUG
let rcKey = "test_YOUR_TEST_STORE_KEY"
#else
let rcKey = "appl_YOUR_APP_STORE_KEY"
#endif
```

---

## For maintainers (Dành cho người bảo trì)

### Package layout (Cấu trúc package)

```
Sources/
  TNSubscriptionShared/   config types shared by every engine — no dependencies, not a product
  TNSubscriptionIOS/      RevenueCat engine    → depends on Shared + RevenueCat
  TNSubscriptionCore/     StoreKit 2 engine    → depends on Shared only
  TNSubscriptionAdapty/   Adapty engine        → depends on Shared + Adapty
Tests/
  TNSubscriptionIOSTests/    TNSubscriptionCoreTests/    TNSubscriptionAdaptyTests/
    └─ each contains TNEngineContractTests.swift (identical except its import line)
IntegrationTests/         Xcode host app + .storekit file — real purchases for TNSubscriptionCore
```

### Rules (Quy tắc)

- **A configuration type goes in `TNSubscriptionShared`, never in an engine.** Copies in each engine
  are how the three drifted apart before. (**Kiểu cấu hình đặt trong `TNSubscriptionShared`, không bao
  giờ đặt trong engine.** Mỗi engine giữ một bản sao chính là lý do ba engine từng lệch nhau.)
- **A new config field** goes into `TNSubscriptionConfig` with a default value, appended after the
  existing parameters so released call sites keep compiling. If an engine cannot honour it, add it to
  `ignoredSettings(for:)` so that engine logs a warning instead of silently ignoring it.
  (**Trường config mới** thêm vào `TNSubscriptionConfig` kèm giá trị mặc định, đặt sau các tham số
  hiện có để code đã phát hành vẫn compile. Engine nào không áp dụng được thì thêm vào
  `ignoredSettings(for:)` để engine đó ghi cảnh báo thay vì âm thầm bỏ qua.)
- **A new API meant to be common to all engines** must be added to all three, and to
  `TNEngineContractTests`, and to the "identical" table above. Edit the three contract files together —
  they must stay identical except for the `import` line.
  (**API mới dùng chung cho mọi engine** phải được thêm vào cả ba engine, vào `TNEngineContractTests`,
  và vào bảng "giống hệt" ở trên. Sửa cả ba file contract cùng lúc — chúng phải giống hệt nhau, chỉ
  khác dòng `import`.)
- **An app imports exactly one engine.** Each engine links a different billing SDK, and the engine
  classes clash on the `TNSubscription` name. (**Mỗi app chỉ import đúng một engine.**)

### Running the tests (Chạy test)

Unit and contract tests for all three engines — this is what CI runs on `macos-26`:
(Unit test và test contract cho cả ba engine — đây là thứ CI chạy trên `macos-26`:)

```bash
xcodebuild test -scheme TNSubscriptionIOS-Package -destination 'platform=iOS Simulator,name=iPhone 17'
```

Use the `-Package` scheme: the per-product schemes have no test action.
StoreKit integration tests for `TNSubscriptionCore` need a host app, so they live in their own
project (see [CORE.md §9](CORE.md)) and are not run by CI.
(Dùng scheme `-Package`: các scheme theo từng product không có test action. Integration test StoreKit
của `TNSubscriptionCore` cần host app nên nằm trong project riêng, và CI không chạy chúng.)

```bash
cd IntegrationTests && xcodegen generate
```

---

## API Reference (Tham chiếu API)

### `TNSubscriptionConfig`

One shared type for every engine. All parameters except `entitlements` have defaults.
(Một kiểu dùng chung cho mọi engine. Mọi tham số trừ `entitlements` đều có giá trị mặc định.)

| Parameter | Default | RevenueCat | Adapty | Core |
|---|---|---|---|---|
| `apiKey` | `""` | ✅ `appl_…` | ✅ `public_live_…` | — |
| `entitlements` | *(required)* | ✅ | ✅ | ✅ |
| `offerings` | `[]` | — | — | ✅ |
| `currentOfferingIdentifier` | `nil` | ✅ offering ID | ✅ placement ID | ✅ |
| `customerUserId` | `nil` | ✅ | ✅ | — |
| `isIAPEnabled` | `true` | ✅ | ✅ | ✅ |
| `enableBackendIdentitySync` | `false` | ✅ | — | — |
| `observerMode` | `false` | — | ✅ | — |
| `attachAppAccountToken` | `false` | — | ✅ | ✅ |
| `offlineStoreKitFallback` | `true` | always on | ✅ | always on |
| `logLevel` | `.default` | ✅ | ✅ | ✅ |

"—" means the engine ignores the setting and logs a warning at `configure` if it is set.
The single-entitlement initialiser takes `entitlementId:` (default `"Premium"`) and
`productIDs:` instead of `entitlements:`.
("—" nghĩa là engine bỏ qua thiết lập đó và ghi cảnh báo lúc `configure` nếu nó được đặt.
Initializer cho một quyền lợi nhận `entitlementId:` (mặc định `"Premium"`) và `productIDs:` thay cho
`entitlements:`.)

### `TNLogLevel`

`.verbose` · `.debug` · `.info` · `.warn` · `.error` · `.none` — ordered, lowest to highest. Defaults to `.info` in DEBUG and `.error` in Release via `TNLogLevel.default`. See [Diagnostics & Logging](#8-diagnostics--logging-chẩn-đoán--log).

### `TNEntitlement`

| Property | Type | Description (Mô tả) |
|---|---|---|
| `id` | `String` | RevenueCat entitlement ID / Adapty access level ID / your own name in Core — must match exactly, including case (ID entitlement của RevenueCat / access level của Adapty / tên tự đặt ở Core — phải khớp chính xác, kể cả hoa/thường) |
| `productIDs` | `Set<String>` | StoreKit Product IDs for this entitlement (Product IDs thuộc entitlement này) |

### `TNSubscriptionIOS.shared`

#### Properties — `@Published`, realtime observable (Lắng nghe realtime)

| Property | Type | Description (Mô tả) |
|---|---|---|
| `isPremium` | `Bool` | `true` if **any** entitlement is active (`true` nếu **bất kỳ** entitlement nào active) |
| `activeEntitlements` | `Set<String>` | All currently active entitlement IDs (Tất cả entitlement IDs đang active) |
| `entitlementState` | `EntitlementState` | `.unknown` → `.locked` → `.unlocked` |
| `customerInfo` | `CustomerInfo?` | RevenueCat customer info |
| `availablePackages` | `[Package]` | Packages from RevenueCat (Danh sách gói từ RevenueCat) |
| `introEligibility` | `[String: IntroEligibilityStatus]` | Intro/Trial eligibility map per product ID (Trạng thái đủ điều kiện ưu đãi người mới theo product ID) |
| `isLoadingOfferings` | `Bool` | Loading offerings (Đang load offerings) |
| `isPurchasing` | `Bool` | Purchase in progress (Đang xử lý mua) |
| `offeringsError` | `String?` | Why no plan could be **displayed** (Vì sao không hiện được gói nào) |
| `entitlementError` | `String?` | Why a purchase could not be **verified**; `nil` means the check completed, **not** that the user is premium (Vì sao mua rồi mà không xác thực được) |

#### Methods (Phương thức)

| Method | Description (Mô tả) |
|---|---|
| `hasEntitlement(_ id: String) → Bool` | Check specific entitlement (Kiểm tra entitlement cụ thể) |
| `productIDs(for: String) → Set<String>` | Get configured product IDs (Lấy product IDs đã config) |
| `fetchOfferings(offeringIdentifier:)` | Load offerings & check intro eligibility (Load offerings và kiểm tra điều kiện ưu đãi người mới) |
| `isEligibleForIntroOffer(package:) → Bool` | Check if user is eligible for free trial / intro offer (Kiểm tra user có đủ điều kiện người mới không) |
| `introOffer(for: Package) → StoreProductDiscount?` | Get intro discount only if user is eligible (Lấy thông tin ưu đãi nếu đủ điều kiện) |
| `introOfferSummary(for: Package) → String?` | Human-readable intro offer text, e.g. `"3 Days Free Trial"` (Chuỗi mô tả ưu đãi người mới) |
| `promotionalDiscounts(for: Package) → [StoreProductDiscount]` | Get promotional discounts for package (Lấy danh sách Promotional Offers của gói) |
| `eligiblePromotionalOffers(for: Package) async → [PromotionalOffer]` | Fetch signed promotional offers from RevenueCat (Lấy danh sách PromotionalOffer đã ký) |
| `purchase(package:completion:)` | Purchase a package (Mua gói) |
| `purchasePromotionalOffer(package:discount:completion:)` | Sign & purchase a Promotional Offer (Ký và mua gói với Promotional Offer) |
| `restorePurchases(completion:)` | Restore purchases (Khôi phục mua hàng) |
| `presentOfferCodeRedemption()` | Present iOS native Offer Code Redemption sheet (Mở sheet nhập mã ưu đãi gốc của iOS) |
| `checkSubscriptionStatus()` | Re-check entitlement status (Kiểm tra lại trạng thái) |
| `currentPlanProductID → String?` | First active plan's product ID (Product ID của plan active đầu tiên) |
| `currentProductID(for:) → String?` | Product ID for specific entitlement (Product ID cho entitlement cụ thể) |
| `currentPlanDisplayName → String?` | Display name of current plan (Tên hiển thị plan hiện tại) |
| `currencyManager → TNInAppCurrencyManager` | Access RevenueCat In-App Currency manager (Truy cập manager tiền ảo) |
| `currencyBalance(for: String) → Int` | Fast balance query for currency code (Tra cứu nhanh số dư tiền ảo) |

#### Static

| API | Description (Mô tả) |
|---|---|
| `TNSubscriptionIOS.logLevel` | Get/set diagnostic verbosity; also sets `Purchases.logLevel` (Đặt mức log, set luôn cho RevenueCat) |
| `TNSubscriptionIOS.logHandler` | Route TNSubscriptionIOS + RevenueCat logs into your own stack (Đưa log vào hệ thống của bạn) |
| `TNSubscriptionIOS.clientId` | Persistent UUID for API headers (UUID persistent cho API headers) |
| `TNSubscriptionIOS.displayName(forProductID:)` | Display name from product ID (Tên hiển thị từ product ID) |
| `TNSubscriptionIOS.isRecommendedPackage(_:)` | Is recommended package, yearly (Có phải gói recommended, yearly) |
| `TNSubscriptionIOS.packageSortOrder(_:)` | Sort order for package types (Thứ tự sắp xếp gói) |

### `TNInAppCurrencyManager.shared` (or `TNVirtualCurrencyManager.shared`)

#### Properties — `@Published`, realtime observable (Lắng nghe realtime)

| Property | Type | Description (Mô tả) |
|---|---|---|
| `balances` | `[String: Int]` | Current balances keyed by currency code (Số dư theo mã tiền tệ, e.g. `["coins": 500]`) |
| `currencies` | `[String: VirtualCurrency]` | RevenueCat `VirtualCurrency` objects with name, code, serverDescription (Danh sách đối tượng chi tiết từ RevenueCat) |
| `rawCurrencies` | `VirtualCurrencies?` | Underlying RevenueCat `VirtualCurrencies` container (Đối tượng gốc từ RevenueCat) |
| `isLoading` | `Bool` | Whether balances are currently fetching (Đang tải số dư) |
| `error` | `String?` | Error message if load or spend fails (Lỗi khi load hoặc trừ tiền) |
| `lastUpdated` | `Date?` | Last successful sync timestamp (Thời gian đồng bộ gần nhất) |

#### Methods (Phương thức)

| Method | Description (Mô tả) |
|---|---|
| `fetchCurrencies(forceRefresh:completion:)` | Fetch balances from RevenueCat with completion handler (Tải số dư từ RevenueCat) |
| `fetchCurrenciesAsync(forceRefresh:) async throws` | Async/await fetch balances (Tải số dư dùng async/await) |
| `balance(for: String) → Int` | Get balance for currency code (Lấy số dư theo mã tiền) |
| `currency(for: String) → VirtualCurrency?` | Get `VirtualCurrency` object (Lấy chi tiết đối tượng tiền tệ) |
| `canAfford(_:currency:) → Bool` | Check if user has sufficient balance (Kiểm tra đủ số dư) |
| `invalidateCache()` | Invalidate local virtual currencies cache (Xóa cache để buộc fetch mới từ server) |
| `spend(code:amount:reference:completion:)` | Spend currency via custom spend handler (Trừ tiền qua spend handler) |
| `spendViaProxy(proxyEndpoint:apiKey:code:amount:userId:completion:)` | Spend currency via API Proxy Gateway with identity headers (Trừ tiền qua API proxy kèm headers định danh) |
| `purchaseItem(itemId:extraParams:completion:)` | Secure item purchase via action handler (Mua item an toàn qua handler) |
| `purchaseItemViaProxy(proxyEndpoint:apiKey:itemId:extraParams:userId:completion:)` | Secure item purchase via API Proxy Gateway (Mua item an toàn qua API proxy, client chỉ gửi `itemId`) |
| `deductLocalBalance(_:for:) → Bool` | Optimistic local balance deduction for instant UI response (Trừ cục bộ tức thì) |
| `configureSpendHandler(_:)` | Register custom amount spend handler (Đăng ký hàm trừ tiền theo số lượng trên server) |
| `configureActionSpendHandler(_:)` | Register custom item-based spend handler (Đăng ký hàm mua item bảo mật trên server) |

### `TNConsumableManager.shared`

#### Properties — `@Published`, realtime observable (Lắng nghe realtime)

| Property | Type | Description (Mô tả) |
|---|---|---|
| `storeProducts` | `[Product]` | StoreKit products loaded from App Store (Sản phẩm đã load từ App Store) |
| `isLoadingProducts` | `Bool` | Loading products (Đang load sản phẩm) |
| `isPurchasing` | `Bool` | Purchase in progress (Đang xử lý mua) |
| `balances` | `[String: Int]` | Current balances per currency (Số dư hiện tại theo loại tiền) |
| `loadError` | `String?` | Error loading products (Lỗi khi load sản phẩm) |

#### Methods (Phương thức)

| Method | Description (Mô tả) |
|---|---|
| `loadProducts()` | Load StoreKit products (Load sản phẩm từ App Store) |
| `purchase(productId:completion:)` | Purchase by product ID (Mua theo product ID) |
| `purchase(product:completion:)` | Purchase by StoreKit Product (Mua bằng StoreKit Product) |
| `balance(for: String) → Int` | Get balance for currency (Lấy số dư cho loại tiền) |
| `addBalance(_:for:)` | Add to balance (Cộng vào số dư) |
| `deductBalance(_:for:) → Bool` | Deduct from balance, returns false if insufficient (Trừ số dư, trả false nếu không đủ) |
| `setBalance(_:for:)` | Set balance to exact value, for server sync (Đặt số dư chính xác, dùng khi sync server) |
| `canAfford(_:currency:) → Bool` | Check if user can afford amount (Kiểm tra user có đủ số dư) |
| `consumableProduct(for:)` | Get configured product by ID (Lấy sản phẩm đã config theo ID) |
| `products(for:)` | Get all products for a currency (Lấy tất cả sản phẩm cho loại tiền) |
| `storeProduct(for:)` | Get StoreKit Product by ID (Lấy StoreKit Product theo ID) |

### `TNConsumableProduct`

| Property | Type | Description (Mô tả) |
|---|---|---|
| `id` | `String` | StoreKit Product ID (e.g. `"com.app.100coins"`) |
| `reward` | `Int` | Amount added after purchase (Số lượng cộng sau khi mua) |
| `currency` | `String` | Currency type name (Tên loại tiền, e.g. `"coins"`, `"gems"`) |

### `DefaultPaywallConfig`

All properties have sensible defaults. Only customize what you need. (Tất cả properties có giá trị mặc định. Chỉ cần customize phần muốn thay đổi.)

| Property | Type | Default | Description (Mô tả) |
|---|---|---|---|
| `appName` | `String` | `"Premium"` | App name in header (Tên app ở header) |
| `features` | `[Feature]` | 3 defaults | Premium features list (Danh sách tính năng premium) |
| `offeringIdentifier` | `String?` | `nil` | Offering to show — RevenueCat offering ID, Adapty placement ID, or Core `TNOffering` ID. `nil` uses `currentOfferingIdentifier` (Offering cần hiển thị — offering ID của RevenueCat, placement ID của Adapty, hoặc ID `TNOffering` của Core. `nil` dùng `currentOfferingIdentifier`) |
| `entitlementId` | `String?` | `nil` | Specific target Entitlement ID (ID Entitlement mục tiêu) |
| `showRedeemCodeButton` | `Bool` | `true` | Show "Redeem Code" button in footer (Hiện nút nhập mã ưu đãi ở cuối paywall) |
| `showSavingsBadge` | `Bool` | `true` | "SAVE X%" badge on plans cheaper per month than the most expensive one (Nhãn "SAVE X%" trên gói rẻ hơn tính theo tháng) |
| `showPricePerMonth` | `Bool` | `true` | Per-month price under non-monthly plans (Giá quy đổi theo tháng dưới các gói không phải gói tháng) |
| `privacyURL` | `URL?` | `nil` | Privacy Policy link (Link chính sách bảo mật) |
| `termsURL` | `URL?` | `nil` | Terms of Use link (Link điều khoản sử dụng) |
| `accentColor` | `Color` | `.cyan` | Purchase button, selected plan, badges, prices — not the Close button (Nút mua, gói đang chọn, badge, giá — không áp dụng cho nút Close) |
| `secondaryColor` | `Color` | `.purple` | Secondary accent color (Màu accent phụ) |
| `backgroundColor` | `Color` | `.black` | Screen background (Màu nền) |
| `textPrimaryColor` | `Color` | `.white` | Primary text color (Màu text chính) |
| `textSecondaryColor` | `Color` | `.gray` | Secondary text color (Màu text phụ) |
| `textMutedColor` | `Color` | `.gray 0.7` | Muted text color (Màu text mờ) |
| `cardColor` | `Color` | dark gray | Card background (Màu nền card) |
| `cardLightColor` | `Color` | lighter gray | Selected card background (Màu card khi chọn) |
| `premiumGradient` | `LinearGradient` | gold | CTA button gradient (Gradient nút CTA) |
| `preferredColorScheme` | `ColorScheme?` | `.dark` | Color scheme (Chế độ màu) |
| `closeButtonTint` | `Color?` | `nil` | Text colour of the toolbar Close button. `nil` leaves it to the system (the Liquid Glass capsule on iOS 26). Before this field, Close used `accentColor`; pass your accent colour to keep that look (Màu chữ nút Close trên toolbar. `nil` để hệ thống tự quyết — viên nang Liquid Glass trên iOS 26. Trước khi có field này, nút Close dùng `accentColor`; truyền màu accent nếu muốn giữ giao diện cũ) |

---

## License

MIT @ Thien Nguyen

