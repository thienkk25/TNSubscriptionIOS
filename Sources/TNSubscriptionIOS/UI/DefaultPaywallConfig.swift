import SwiftUI

// MARK: - Default Paywall Configuration

/// Configuration for the built-in default paywall view.
/// Pass this to `TNSubscriptionIOS.presentDefaultPaywall(from:config:)`.
///
/// Provides sensible defaults so you only need to customize what you want.
public struct DefaultPaywallConfig {
    
    /// A premium feature displayed in the paywall.
    public struct Feature {
        public let icon: String
        public let title: String
        public let subtitle: String
        
        public init(icon: String, title: String, subtitle: String) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
        }
    }
    
    // MARK: - Content
    
    /// The app name displayed in the paywall header.
    public var appName: String
    
    /// The list of premium features shown to the user.
    public var features: [Feature]
    
    /// Privacy Policy URL. Set to `nil` to hide.
    public var privacyURL: URL?
    
    /// Terms of Use URL. Set to `nil` to hide.
    public var termsURL: URL?
    
    // MARK: - Theme Colors
    
    /// Primary accent color (buttons, highlights).
    public var accentColor: Color
    
    /// Secondary color (badges, active plan indicator).
    public var secondaryColor: Color
    
    /// Screen background color.
    public var backgroundColor: Color
    
    /// Primary text color.
    public var textPrimaryColor: Color
    
    /// Secondary text color.
    public var textSecondaryColor: Color
    
    /// Muted text color (legal disclaimers, footnotes).
    public var textMutedColor: Color
    
    /// Card background color.
    public var cardColor: Color
    
    /// Lighter card background (selected state).
    public var cardLightColor: Color
    
    /// Premium gradient for CTA button and crown icon.
    public var premiumGradient: LinearGradient
    
    /// Preferred color scheme. Set to `nil` to follow system.
    public var preferredColorScheme: ColorScheme?
    
    // MARK: - Init
    
    public init(
        appName: String = "Premium",
        features: [Feature] = [
            Feature(icon: "sparkles", title: NSLocalizedString("Feature One", comment: ""), subtitle: NSLocalizedString("Unlock unlimited access to Feature One", comment: "")),
            Feature(icon: "bolt.fill", title: NSLocalizedString("Feature Two", comment: ""), subtitle: NSLocalizedString("Get 10x faster processing times", comment: "")),
            Feature(icon: "cloud.fill", title: NSLocalizedString("Feature Three", comment: ""), subtitle: NSLocalizedString("Sync data seamlessly in the cloud", comment: ""))
        ],
        privacyURL: URL? = nil,
        termsURL: URL? = nil,
        accentColor: Color = .cyan,
        secondaryColor: Color = .purple,
        backgroundColor: Color = .black,
        textPrimaryColor: Color = .white,
        textSecondaryColor: Color = .gray,
        textMutedColor: Color = Color.gray.opacity(0.7),
        cardColor: Color = Color(red: 0.1, green: 0.1, blue: 0.1),
        cardLightColor: Color = Color(red: 0.15, green: 0.15, blue: 0.15),
        premiumGradient: LinearGradient = LinearGradient(
            colors: [Color(red: 0.83, green: 0.69, blue: 0.22), Color(red: 0.64, green: 0.49, blue: 0.23)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        preferredColorScheme: ColorScheme? = .dark
    ) {
        self.appName = appName
        self.features = features
        self.privacyURL = privacyURL
        self.termsURL = termsURL
        self.accentColor = accentColor
        self.secondaryColor = secondaryColor
        self.backgroundColor = backgroundColor
        self.textPrimaryColor = textPrimaryColor
        self.textSecondaryColor = textSecondaryColor
        self.textMutedColor = textMutedColor
        self.cardColor = cardColor
        self.cardLightColor = cardLightColor
        self.premiumGradient = premiumGradient
        self.preferredColorScheme = preferredColorScheme
    }
}
