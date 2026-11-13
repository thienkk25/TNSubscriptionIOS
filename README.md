# TNSubscriptionIOS

A reusable Swift Package for iOS subscription management powered by RevenueCat. (Gói Swift Package tái sử dụng cho quản lý subscription iOS, chạy trên RevenueCat.)

- Built-in paywall UI **or** bring your own custom paywall (Paywall có sẵn **hoặc** tự custom hoàn toàn)
- **Multiple entitlements** support (Hỗ trợ **nhiều entitlements**)
- **RevenueCat In-App Currencies** support (Hỗ trợ **tiền tệ ảo/coins/gems/credits** đồng bộ Cloud RevenueCat)
- Works with both **UIKit** and **SwiftUI** (Hoạt động với cả **UIKit** và **SwiftUI**)
- **Diagnostics**: log levels, a pluggable log handler, API key validation and readable failure reasons (**Chẩn đoán**: mức log, log handler tùy biến, validate API key và lý do lỗi rõ ràng)

---

## Requirements (Yêu cầu)

- iOS 16.0+
- Swift 5.9+
- RevenueCat account & API key

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

## API Reference (Tham chiếu API)

### `TNSubscriptionConfig`

| Initializer | Parameters |
|---|---|
| Multi-entitlement (Nhiều entitlements) | `apiKey`, `entitlements: [TNEntitlement]`, `isIAPEnabled`, `enableBackendIdentitySync`, `logLevel` |
| Single-entitlement (1 entitlement) | `apiKey`, `entitlementId`, `productIDs: Set<String>`, `isIAPEnabled`, `enableBackendIdentitySync`, `logLevel` |

### `TNLogLevel`

`.verbose` · `.debug` · `.info` · `.warn` · `.error` · `.none` — ordered, lowest to highest. Defaults to `.info` in DEBUG and `.error` in Release via `TNLogLevel.default`. See [Diagnostics & Logging](#8-diagnostics--logging-chẩn-đoán--log).

### `TNEntitlement`

| Property | Type | Description (Mô tả) |
|---|---|---|
| `id` | `String` | Entitlement ID in RevenueCat (ID entitlement trong RevenueCat) |
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
| `offeringIdentifier` | `String?` | `nil` | Specific RevenueCat Offering ID (ID Offering cụ thể) |
| `entitlementId` | `String?` | `nil` | Specific target Entitlement ID (ID Entitlement mục tiêu) |
| `showRedeemCodeButton` | `Bool` | `true` | Show "Redeem Code" button in footer (Hiện nút nhập mã ưu đãi ở cuối paywall) |
| `privacyURL` | `URL?` | `nil` | Privacy Policy link (Link chính sách bảo mật) |
| `termsURL` | `URL?` | `nil` | Terms of Use link (Link điều khoản sử dụng) |
| `accentColor` | `Color` | `.cyan` | Primary accent color (Màu accent chính) |
| `secondaryColor` | `Color` | `.purple` | Secondary accent color (Màu accent phụ) |
| `backgroundColor` | `Color` | `.black` | Screen background (Màu nền) |
| `textPrimaryColor` | `Color` | `.white` | Primary text color (Màu text chính) |
| `textSecondaryColor` | `Color` | `.gray` | Secondary text color (Màu text phụ) |
| `textMutedColor` | `Color` | `.gray 0.7` | Muted text color (Màu text mờ) |
| `cardColor` | `Color` | dark gray | Card background (Màu nền card) |
| `cardLightColor` | `Color` | lighter gray | Selected card background (Màu card khi chọn) |
| `premiumGradient` | `LinearGradient` | gold | CTA button gradient (Gradient nút CTA) |
| `preferredColorScheme` | `ColorScheme?` | `.dark` | Color scheme (Chế độ màu) |

---

## License

MIT @ Thien Nguyen

