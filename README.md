# TNSubscriptionIOS

A reusable Swift Package for iOS subscription management powered by RevenueCat.  
Drop-in solution with a built-in paywall UI **or** bring your own custom paywall.

## Requirements

- iOS 16.0+
- Swift 5.9+
- RevenueCat account & API key

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies** → paste:

```
https://github.com/thienkk25/TNSubscriptionIOS.git
```

Or add to your `Package.swift`:

```swift
.package(url: "https://github.com/thienkk25/TNSubscriptionIOS.git", from: "1.0.0"),
```

### Local Package (Development)

Drag the `TNSubscriptionIOS` folder into your Xcode project, then:  
**Target → General → Frameworks → Add → TNSubscriptionIOS**

---

## Quick Start

### 1. Configure at App Launch

```swift
// AppDelegate.swift
import TNSubscriptionIOS

func application(_ application: UIApplication, 
                 didFinishLaunchingWithOptions launchOptions: ...) -> Bool {
    
    TNSubscriptionIOS.configure(config: TNSubscriptionConfig(
        apiKey: "appl_YOUR_REVENUECAT_KEY",
        entitlementId: "Premium",   // Your RevenueCat Entitlement ID
        productIDs: [               // Your StoreKit Product IDs
            "com.yourapp.weekly",
            "com.yourapp.monthly",
            "com.yourapp.yearly"
        ]
    ))
    
    return true
}
```

### 2. Check Premium Status

```swift
if TNSubscriptionIOS.shared.isPremium {
    // User has premium access
} else {
    // Show paywall
}

// Or observe with Combine / SwiftUI
@ObservedObject var subscription = TNSubscriptionIOS.shared
// subscription.isPremium
// subscription.entitlementState (.unknown / .locked / .unlocked)
```

### 3. Present Paywall

#### Option A: Default Paywall (quick & easy)

```swift
TNSubscriptionIOS.presentDefaultPaywall(from: viewController, config: DefaultPaywallConfig(
    appName: "PitchLab",
    features: [
        .init(icon: "music.note", title: "Unlimited Tuning", subtitle: "Tune any instrument with precision"),
        .init(icon: "waveform", title: "Pro Analysis", subtitle: "Advanced pitch detection and graphs"),
        .init(icon: "icloud.fill", title: "Cloud Sync", subtitle: "Access your data on all devices")
    ],
    privacyURL: URL(string: "https://yoursite.com/privacy"),
    termsURL: URL(string: "https://yoursite.com/terms"),
    accentColor: .cyan,
    secondaryColor: .purple,
    backgroundColor: .black
))
```

#### Option B: Fully Custom Paywall

```swift
TNSubscriptionIOS.presentPaywall(from: viewController) {
    MyCustomPaywallView()
}
```

Inside your custom view, use the shared manager:

```swift
struct MyCustomPaywallView: View {
    @ObservedObject var manager = TNSubscriptionIOS.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            ForEach(manager.availablePackages, id: \.identifier) { pkg in
                Button(pkg.storeProduct.localizedPriceString) {
                    manager.purchase(package: pkg) { result in
                        switch result {
                        case .success: dismiss()
                        case .failure(let error): print(error)
                        }
                    }
                }
            }

            Button("Restore") {
                manager.restorePurchases { _ in }
            }
        }
        .onAppear {
            manager.fetchOfferings()
        }
    }
}
```

---

## TN Studio Proxy Headers

This package automatically generates and persists a `clientId` (Keychain-backed).  
Use it for the `X-Client-Id` header when calling TN Studio proxy APIs:

```swift
request.setValue(TNSubscriptionIOS.clientId, forHTTPHeaderField: "X-Client-Id")
```

---

## API Reference

### `TNSubscriptionConfig`

| Parameter | Type | Default | Description |
|---|---|---|---|
| `apiKey` | `String` | required | RevenueCat API key |
| `entitlementId` | `String` | `"Premium"` | RevenueCat Entitlement ID |
| `productIDs` | `Set<String>` | required | StoreKit Product IDs for local validation |
| `isIAPEnabled` | `Bool` | `true` | Set `false` to bypass paywall during dev |

### `TNSubscriptionIOS.shared` (after configure)

| Property/Method | Description |
|---|---|
| `.isPremium` | `Bool` — whether user has active subscription |
| `.entitlementState` | `.unknown` / `.locked` / `.unlocked` |
| `.availablePackages` | `[Package]` — loaded from RevenueCat |
| `.fetchOfferings()` | Loads offerings from RevenueCat |
| `.purchase(package:completion:)` | Purchases a package |
| `.restorePurchases(completion:)` | Restores previous purchases |
| `.checkSubscriptionStatus()` | Re-checks entitlement status |
| `.clientId` | Persistent UUID for API headers |

### `DefaultPaywallConfig`

Customizes the built-in paywall. All properties have sensible defaults.

| Property | Type | Description |
|---|---|---|
| `appName` | `String` | App name in header |
| `features` | `[Feature]` | List of premium features |
| `privacyURL` | `URL?` | Privacy Policy link |
| `termsURL` | `URL?` | Terms of Use link |
| `accentColor` | `Color` | Primary accent |
| `secondaryColor` | `Color` | Secondary accent |
| `backgroundColor` | `Color` | Screen background |
| `textPrimaryColor` | `Color` | Primary text |
| `textSecondaryColor` | `Color` | Secondary text |
| `textMutedColor` | `Color` | Muted text |
| `cardColor` | `Color` | Card background |
| `cardLightColor` | `Color` | Selected card background |
| `premiumGradient` | `LinearGradient` | CTA button gradient |
| `preferredColorScheme` | `ColorScheme?` | `.dark` / `.light` / `nil` |

---

## License

MIT @ Thien Nguyen
