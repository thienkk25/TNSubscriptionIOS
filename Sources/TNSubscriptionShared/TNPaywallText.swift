import Foundation

// MARK: - TNPaywallText

/// Every piece of text on the built-in paywall that an app can replace through
/// `DefaultPaywallConfig.texts` — the same in every engine.
/// (Mọi chữ trên paywall có sẵn mà app có thể thay qua `DefaultPaywallConfig.texts` — giống nhau ở
/// mọi engine.)
///
/// ```swift
/// DefaultPaywallConfig(texts: [
///     .redeemCode: "Nhập mã ưu đãi",
///     .restorePurchases: "Khôi phục giao dịch",
/// ])
/// ```
///
/// Not listed here (Không có ở đây):
/// - The headline and the line under it — use `headerTitle`, `headerSubtitle`,
///   `unlockedHeaderTitle`, `unlockedHeaderSubtitle`. (Tiêu đề và dòng bên dưới — dùng các field riêng.)
/// - Text with placeholders such as `"SAVE %d%%"` or `"Current plan: %@"`. A placeholder typed
///   wrong crashes at runtime, so these are overridable only through your `Localizable` file.
///   (Chuỗi có placeholder như `"SAVE %d%%"`. Gõ sai placeholder sẽ crash lúc chạy, nên các chuỗi
///   này chỉ ghi đè được qua file `Localizable` của app.)
///
/// A case an engine's paywall never shows is simply never read — `.welcomeBack`, for instance,
/// only appears with Adapty's win-back offers.
/// (Case nào paywall của một engine không dùng thì đơn giản là không bao giờ được đọc — ví dụ
/// `.welcomeBack` chỉ xuất hiện với ưu đãi win-back của Adapty.)
public enum TNPaywallText: String, CaseIterable, Hashable, Sendable {

    // Screen
    /// "Premium"
    case navigationTitle
    /// "Close"
    case close
    /// "Verifying your subscription..."
    case verifying
    /// "What's included"
    case whatsIncluded
    /// "Choose your plan"
    case choosePlan
    /// "Plans could not be loaded."
    case plansUnavailable
    /// "Retry"
    case retry

    // Active plan
    /// "Premium Active"
    case premiumActive
    /// "Want a different plan? Choose one below to switch. Apple will prorate your subscription when applicable."
    case switchPlanHint
    /// "Manage Subscription in App Store"
    case manageSubscription
    /// "There's a problem with your payment method. Please update it to keep your subscription."
    case gracePeriodNotice
    /// "Your last payment failed. Update your payment method in the App Store to restore access."
    case billingRetryNotice

    // Plan names
    /// "Weekly"
    case weekly
    /// "Monthly"
    case monthly
    /// "2 Months"
    case twoMonths
    /// "3 Months"
    case threeMonths
    /// "6 Months"
    case sixMonths
    /// "Yearly"
    case yearly
    /// "Lifetime"
    case lifetime

    // Plan cards
    /// "One-time purchase · Forever access"
    case lifetimeSubtitle
    /// "Auto-renewable subscription"
    case autoRenewSubtitle
    /// "BEST VALUE"
    case bestValue
    /// "CURRENT"
    case current
    /// "FREE TRIAL"
    case freeTrial
    /// "INTRO OFFER"
    case introOffer
    /// "SPECIAL OFFER"
    case specialOffer
    /// "WELCOME BACK"
    case welcomeBack

    // Buttons
    /// "Continue"
    case continueButton
    /// "Switch Plan"
    case switchPlan
    /// "Start Free Trial"
    case startFreeTrial
    /// "Claim Intro Offer"
    case claimIntroOffer
    /// "Claim Offer"
    case claimOffer
    /// "Restore Purchases"
    case restorePurchases
    /// "Redeem Code"
    case redeemCode

    // Footer
    /// "Privacy Policy"
    case privacyPolicy
    /// "Terms of Use"
    case termsOfUse
    /// "Payment will be charged to your Apple ID. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period."
    case legalDisclaimer

    // Alerts
    /// "OK"
    case ok
    /// "Welcome to Premium!"
    case purchaseSuccessTitle
    /// "You now have full access to all premium features."
    case purchaseSuccessMessage
    /// "Purchase Failed"
    case purchaseFailedTitle
    /// "Waiting for Approval"
    case purchasePendingTitle
    /// "Your purchase needs to be approved before it can complete. You'll get access automatically once it is."
    case purchasePendingMessage
    /// "Purchase Restored"
    case restoreSuccessTitle
    /// "Your Premium subscription has been restored successfully!"
    case restoreSuccessMessage
    /// "Network Error"
    case restoreFailedTitle
    /// "Please check your internet connection and try again."
    case restoreFailedMessage
    /// "No Active Subscription"
    case noSubscriptionTitle
    /// "We couldn't find an active Premium subscription to restore."
    case noSubscriptionMessage

    /// The built-in English text, looked up in your app's `Localizable` file first — so an
    /// existing translation keeps working.
    /// (Chữ tiếng Anh có sẵn, được tra trong file `Localizable` của app trước — nên bản dịch đang
    /// có vẫn tiếp tục hoạt động.)
    public var defaultValue: String {
        switch self {
        case .navigationTitle: return NSLocalizedString("Premium", comment: "")
        case .close: return NSLocalizedString("Close", comment: "")
        case .verifying: return NSLocalizedString("Verifying your subscription...", comment: "")
        case .whatsIncluded: return NSLocalizedString("What's included", comment: "")
        case .choosePlan: return NSLocalizedString("Choose your plan", comment: "")
        case .plansUnavailable: return NSLocalizedString("Plans could not be loaded.", comment: "")
        case .retry: return NSLocalizedString("Retry", comment: "")
        case .premiumActive: return NSLocalizedString("Premium Active", comment: "")
        case .switchPlanHint: return NSLocalizedString("Want a different plan? Choose one below to switch. Apple will prorate your subscription when applicable.", comment: "")
        case .manageSubscription: return NSLocalizedString("Manage Subscription in App Store", comment: "")
        case .gracePeriodNotice: return NSLocalizedString("There's a problem with your payment method. Please update it to keep your subscription.", comment: "")
        case .billingRetryNotice: return NSLocalizedString("Your last payment failed. Update your payment method in the App Store to restore access.", comment: "")
        case .weekly: return NSLocalizedString("Weekly", comment: "")
        case .monthly: return NSLocalizedString("Monthly", comment: "")
        case .twoMonths: return NSLocalizedString("2 Months", comment: "")
        case .threeMonths: return NSLocalizedString("3 Months", comment: "")
        case .sixMonths: return NSLocalizedString("6 Months", comment: "")
        case .yearly: return NSLocalizedString("Yearly", comment: "")
        case .lifetime: return NSLocalizedString("Lifetime", comment: "")
        case .lifetimeSubtitle: return NSLocalizedString("One-time purchase · Forever access", comment: "")
        case .autoRenewSubtitle: return NSLocalizedString("Auto-renewable subscription", comment: "")
        case .bestValue: return NSLocalizedString("BEST VALUE", comment: "")
        case .current: return NSLocalizedString("CURRENT", comment: "")
        case .freeTrial: return NSLocalizedString("FREE TRIAL", comment: "")
        case .introOffer: return NSLocalizedString("INTRO OFFER", comment: "")
        case .specialOffer: return NSLocalizedString("SPECIAL OFFER", comment: "")
        case .welcomeBack: return NSLocalizedString("WELCOME BACK", comment: "")
        case .continueButton: return NSLocalizedString("Continue", comment: "")
        case .switchPlan: return NSLocalizedString("Switch Plan", comment: "")
        case .startFreeTrial: return NSLocalizedString("Start Free Trial", comment: "")
        case .claimIntroOffer: return NSLocalizedString("Claim Intro Offer", comment: "")
        case .claimOffer: return NSLocalizedString("Claim Offer", comment: "")
        case .restorePurchases: return NSLocalizedString("Restore Purchases", comment: "")
        case .redeemCode: return NSLocalizedString("Redeem Code", comment: "")
        case .privacyPolicy: return NSLocalizedString("Privacy Policy", comment: "")
        case .termsOfUse: return NSLocalizedString("Terms of Use", comment: "")
        case .legalDisclaimer: return NSLocalizedString("Payment will be charged to your Apple ID. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period.", comment: "")
        case .ok: return NSLocalizedString("OK", comment: "")
        case .purchaseSuccessTitle: return NSLocalizedString("Welcome to Premium!", comment: "")
        case .purchaseSuccessMessage: return NSLocalizedString("You now have full access to all premium features.", comment: "")
        case .purchaseFailedTitle: return NSLocalizedString("Purchase Failed", comment: "")
        case .purchasePendingTitle: return NSLocalizedString("Waiting for Approval", comment: "")
        case .purchasePendingMessage: return NSLocalizedString("Your purchase needs to be approved before it can complete. You'll get access automatically once it is.", comment: "")
        case .restoreSuccessTitle: return NSLocalizedString("Purchase Restored", comment: "")
        case .restoreSuccessMessage: return NSLocalizedString("Your Premium subscription has been restored successfully!", comment: "")
        case .restoreFailedTitle: return NSLocalizedString("Network Error", comment: "")
        case .restoreFailedMessage: return NSLocalizedString("Please check your internet connection and try again.", comment: "")
        case .noSubscriptionTitle: return NSLocalizedString("No Active Subscription", comment: "")
        case .noSubscriptionMessage: return NSLocalizedString("We couldn't find an active Premium subscription to restore.", comment: "")
        }
    }
}
