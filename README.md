# TNSubscriptionIOS

A reusable Swift Package for iOS subscription management powered by RevenueCat. (Gói Swift Package tái sử dụng cho quản lý subscription iOS, chạy trên RevenueCat.)

- Built-in paywall UI **or** bring your own custom paywall (Paywall có sẵn **hoặc** tự custom hoàn toàn)
- **Multiple entitlements** support (Hỗ trợ **nhiều entitlements**)
- Works with both **UIKit** and **SwiftUI** (Hoạt động với cả **UIKit** và **SwiftUI**)

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

```swift
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

## 6. TN Studio Proxy Headers

Package auto-generates a persistent `clientId` (Keychain-backed). Use for `X-Client-Id` header when calling TN Studio proxy APIs. (Package tự tạo `clientId` persistent lưu Keychain. Dùng cho header `X-Client-Id` khi gọi TN Studio proxy API.)

```swift
request.setValue(TNSubscriptionIOS.clientId, forHTTPHeaderField: "X-Client-Id")
```

---

## API Reference (Tham chiếu API)

### `TNSubscriptionConfig`

| Initializer | Parameters |
|---|---|
| Multi-entitlement (Nhiều entitlements) | `apiKey`, `entitlements: [TNEntitlement]`, `isIAPEnabled` |
| Single-entitlement (1 entitlement) | `apiKey`, `entitlementId`, `productIDs: Set<String>`, `isIAPEnabled` |

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
| `isLoadingOfferings` | `Bool` | Loading offerings (Đang load offerings) |
| `isPurchasing` | `Bool` | Purchase in progress (Đang xử lý mua) |
| `offeringsError` | `String?` | Error loading offerings (Lỗi khi load offerings) |

#### Methods (Phương thức)

| Method | Description (Mô tả) |
|---|---|
| `hasEntitlement(_ id: String) → Bool` | Check specific entitlement (Kiểm tra entitlement cụ thể) |
| `productIDs(for: String) → Set<String>` | Get configured product IDs (Lấy product IDs đã config) |
| `fetchOfferings()` | Load offerings from RevenueCat (Load offerings từ RevenueCat) |
| `purchase(package:completion:)` | Purchase a package (Mua gói) |
| `restorePurchases(completion:)` | Restore purchases (Khôi phục mua hàng) |
| `checkSubscriptionStatus()` | Re-check entitlement status (Kiểm tra lại trạng thái) |
| `currentPlanProductID → String?` | First active plan's product ID (Product ID của plan active đầu tiên) |
| `currentProductID(for:) → String?` | Product ID for specific entitlement (Product ID cho entitlement cụ thể) |
| `currentPlanDisplayName → String?` | Display name of current plan (Tên hiển thị plan hiện tại) |

#### Static

| API | Description (Mô tả) |
|---|---|
| `TNSubscriptionIOS.clientId` | Persistent UUID for API headers (UUID persistent cho API headers) |
| `TNSubscriptionIOS.displayName(forProductID:)` | Display name from product ID (Tên hiển thị từ product ID) |
| `TNSubscriptionIOS.isRecommendedPackage(_:)` | Is recommended package, yearly (Có phải gói recommended, yearly) |
| `TNSubscriptionIOS.packageSortOrder(_:)` | Sort order for package types (Thứ tự sắp xếp gói) |

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

