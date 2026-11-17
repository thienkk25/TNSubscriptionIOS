import SwiftUI
import StoreKit

// MARK: - TNDefaultPaywallView

/// The built-in paywall, driven entirely by `TNSubscriptionCore` and `DefaultPaywallConfig`.
/// (Paywall có sẵn, điều khiển hoàn toàn bởi `TNSubscriptionCore` và `DefaultPaywallConfig`.)
///
/// Use it directly in SwiftUI (`.sheet { TNDefaultPaywallView(config: …) }`), or present it
/// from UIKit with `TNSubscriptionCore.presentDefaultPaywall(from:config:)`.
/// (Dùng trực tiếp trong SwiftUI (`.sheet { TNDefaultPaywallView(config: …) }`), hoặc hiển thị
/// từ UIKit bằng `TNSubscriptionCore.presentDefaultPaywall(from:config:)`.)
public struct TNDefaultPaywallView: View {

    @ObservedObject private var manager = TNSubscriptionCore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPackage: TNPackage?
    @State private var activeAlert: UpgradeAlert?
    @State private var isRestoring = false
    @State private var isRedeemingOfferCode = false

    public let config: DefaultPaywallConfig

    public init(config: DefaultPaywallConfig = DefaultPaywallConfig()) {
        self.config = config
    }

    // MARK: - Derived State

    private var isTargetUnlocked: Bool {
        if let targetId = config.entitlementId, !targetId.isEmpty {
            return manager.hasEntitlement(targetId)
        }
        return manager.entitlementState == .unlocked || manager.isPremium
    }

    /// The packages to show, narrowed to the target entitlement's products when one is set.
    /// (Các gói sẽ hiển thị, lọc theo sản phẩm của quyền lợi mục tiêu nếu có đặt.)
    private var displayedPackages: [TNPackage] {
        guard let targetId = config.entitlementId, !targetId.isEmpty else {
            return manager.availablePackages
        }
        let allowed = manager.productIDs(for: targetId)
        guard !allowed.isEmpty, config.offeringIdentifier == nil else {
            return manager.availablePackages
        }
        let filtered = manager.availablePackages.filter { allowed.contains($0.productIdentifier) }
        // Falling back to the full list beats showing an empty paywall when the filter
        // matches nothing — that would be a dead end for the user.
        return filtered.isEmpty ? manager.availablePackages : filtered
    }

    /// The reference plan for "save X%": the most expensive per month on display.
    /// (Gói tham chiếu cho "tiết kiệm X%": gói đắt nhất tính theo tháng đang hiển thị.)
    private var savingsBaseline: TNPackage? {
        displayedPackages
            .filter { $0.pricePerMonth != nil }
            .max { ($0.pricePerMonth ?? 0) < ($1.pricePerMonth ?? 0) }
    }

    private enum UpgradeAlert: Identifiable {
        case purchaseSuccess
        case purchaseFailed(String)
        case purchasePending
        case restoreSuccess
        case restoreFailed
        case noSubscription

        var id: String {
            switch self {
            case .purchaseSuccess: return "purchaseSuccess"
            case .purchaseFailed(let message): return "purchaseFailed-\(message)"
            case .purchasePending: return "purchasePending"
            case .restoreSuccess: return "restoreSuccess"
            case .restoreFailed: return "restoreFailed"
            case .noSubscription: return "noSubscription"
            }
        }
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                config.backgroundColor.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        headerSection

                        // `.unknown` is the gap before the first verified answer. Showing a
                        // paywall here is what makes paying users see one on every cold start.
                        if manager.entitlementState == .unknown {
                            verifyingSection
                        } else if isTargetUnlocked {
                            activePlanSection
                        } else {
                            featuresSection
                            plansSection
                            purchaseButton
                        }

                        footerActions
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(NSLocalizedString("Premium", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Close", comment: "")) { dismiss() }
                        .foregroundStyle(config.accentColor)
                }
            }
            .toolbarBackground(config.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(config.preferredColorScheme)
        .task {
            await manager.resolveEntitlement()
            await manager.loadOfferings(offeringIdentifier: config.offeringIdentifier)
            selectDefaultPackageIfNeeded()
        }
        .onChange(of: displayedPackages.map(\.identifier)) { _ in
            selectDefaultPackageIfNeeded()
        }
        .offerCodeRedemption(isPresented: $isRedeemingOfferCode) { result in
            guard case .success = result else { return }
            Task { @MainActor in
                await manager.resolveEntitlement()
                if isTargetUnlocked || manager.isPremium {
                    activeAlert = .purchaseSuccess
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .purchaseSuccess:
                return Alert(
                    title: Text(NSLocalizedString("Welcome to Premium!", comment: "")),
                    message: Text(NSLocalizedString("You now have full access to all premium features.", comment: "")),
                    dismissButton: .default(Text(NSLocalizedString("OK", comment: ""))) { dismiss() }
                )
            case .purchaseFailed(let message):
                return Alert(
                    title: Text(NSLocalizedString("Purchase Failed", comment: "")),
                    message: Text(message),
                    dismissButton: .default(Text(NSLocalizedString("OK", comment: "")))
                )
            case .purchasePending:
                return Alert(
                    title: Text(NSLocalizedString("Waiting for Approval", comment: "")),
                    message: Text(NSLocalizedString("Your purchase needs to be approved before it can complete. You'll get access automatically once it is.", comment: "")),
                    dismissButton: .default(Text(NSLocalizedString("OK", comment: "")))
                )
            case .restoreSuccess:
                return Alert(
                    title: Text(NSLocalizedString("Purchase Restored", comment: "")),
                    message: Text(NSLocalizedString("Your Premium subscription has been restored successfully!", comment: "")),
                    dismissButton: .default(Text(NSLocalizedString("OK", comment: "")))
                )
            case .restoreFailed:
                return Alert(
                    title: Text(NSLocalizedString("Network Error", comment: "")),
                    message: Text(NSLocalizedString("Please check your internet connection and try again.", comment: "")),
                    dismissButton: .default(Text(NSLocalizedString("OK", comment: "")))
                )
            case .noSubscription:
                return Alert(
                    title: Text(NSLocalizedString("No Active Subscription", comment: "")),
                    message: Text(NSLocalizedString("We couldn't find an active Premium subscription to restore.", comment: "")),
                    dismissButton: .default(Text(NSLocalizedString("OK", comment: "")))
                )
            }
        }
    }

    private func selectDefaultPackageIfNeeded() {
        guard selectedPackage == nil, !displayedPackages.isEmpty else { return }
        selectedPackage = displayedPackages.first { manager.isRecommended($0) } ?? displayedPackages.first
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(config.premiumGradient.opacity(0.25))
                    .frame(width: 88, height: 88)
                Image(systemName: "crown.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(config.premiumGradient)
            }
            .padding(.top, 8)

            Text(config.appName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(config.textSecondaryColor)
                .textCase(.uppercase)
                .tracking(1.2)

            Text(headerTitle)
                .font(.title2)
                .fontWeight(.black)
                .foregroundStyle(config.textPrimaryColor)
                .multilineTextAlignment(.center)

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(config.textSecondaryColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var headerTitle: String {
        isTargetUnlocked
            ? NSLocalizedString("You're Premium", comment: "")
            : NSLocalizedString("Upgrade to Premium", comment: "")
    }

    private var headerSubtitle: String {
        isTargetUnlocked
            ? NSLocalizedString("Thank you for supporting the app. Manage or change your plan below.", comment: "")
            : NSLocalizedString("Unlock all premium features, custom designs, and settings.", comment: "")
    }

    private var verifyingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(config.accentColor)
                .scaleEffect(1.3)
            Text(NSLocalizedString("Verifying your subscription...", comment: ""))
                .foregroundStyle(config.textSecondaryColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Active Plan

    private var activePlanSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(config.secondaryColor)
                Text(NSLocalizedString("Premium Active", comment: ""))
                    .font(.headline)
                    .foregroundStyle(config.textPrimaryColor)
                Spacer()
            }
            .padding()
            .background(config.cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(config.secondaryColor.opacity(0.4), lineWidth: 1)
            )

            if let planName = manager.currentPlanDisplayName {
                Text(String(format: NSLocalizedString("Current plan: %@", comment: ""), planName))
                    .font(.subheadline)
                    .foregroundStyle(config.textSecondaryColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            subscriptionStatusNotice

            featuresSection

            Text(NSLocalizedString("Want a different plan? Choose one below to switch. Apple will prorate your subscription when applicable.", comment: ""))
                .font(.caption)
                .foregroundStyle(config.textMutedColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            plansSection
            purchaseButton

            Button {
                manager.showManageSubscriptions()
            } label: {
                Text(NSLocalizedString("Manage Subscription in App Store", comment: ""))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(config.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(config.cardColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    /// Surfaces a billing problem or a cancelled renewal, which is the one thing a
    /// subscriber genuinely needs to be told about.
    /// (Hiển thị lỗi thanh toán hoặc việc đã tắt gia hạn — điều duy nhất mà người đang đăng ký
    /// thật sự cần được thông báo.)
    @ViewBuilder
    private var subscriptionStatusNotice: some View {
        if let entitlementId = activeEntitlementId,
           let info = manager.entitlementInfo(for: entitlementId) {
            if info.isInGracePeriod {
                noticeRow(
                    icon: "exclamationmark.triangle.fill",
                    text: NSLocalizedString("There's a problem with your payment method. Please update it to keep your subscription.", comment: ""),
                    tint: .orange
                )
            } else if info.hasBillingIssue {
                noticeRow(
                    icon: "creditcard.trianglebadge.exclamationmark",
                    text: NSLocalizedString("Your last payment failed. Update your payment method in the App Store to restore access.", comment: ""),
                    tint: .red
                )
            } else if !info.willRenew, let expiry = info.expirationDate {
                noticeRow(
                    icon: "clock.badge.exclamationmark",
                    text: String(
                        format: NSLocalizedString("Auto-renew is off. Your access ends on %@.", comment: ""),
                        expiry.formatted(date: .abbreviated, time: .omitted)
                    ),
                    tint: config.textSecondaryColor
                )
            }
        }
    }

    private var activeEntitlementId: String? {
        if let targetId = config.entitlementId, !targetId.isEmpty { return targetId }
        return manager.activeEntitlements.sorted().first
    }

    private func noticeRow(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(config.textSecondaryColor)
            Spacer()
        }
        .padding(12)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("What's included", comment: ""))
                .font(.headline)
                .foregroundStyle(config.textPrimaryColor)

            VStack(spacing: 10) {
                ForEach(config.features) { feature in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: feature.icon)
                            .font(.body)
                            .foregroundStyle(config.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(config.textPrimaryColor)
                            Text(feature.subtitle)
                                .font(.caption)
                                .foregroundStyle(config.textSecondaryColor)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(config.cardColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    // MARK: - Plans

    @ViewBuilder
    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Choose your plan", comment: ""))
                .font(.headline)
                .foregroundStyle(config.textPrimaryColor)

            if manager.isLoadingOfferings {
                HStack {
                    Spacer()
                    ProgressView().tint(config.accentColor)
                    Spacer()
                }
                .padding(.vertical, 24)
            } else if displayedPackages.isEmpty {
                VStack(spacing: 12) {
                    Text(manager.offeringsError ?? NSLocalizedString("Plans could not be loaded.", comment: ""))
                        .font(.caption)
                        .foregroundStyle(config.textSecondaryColor)
                        .multilineTextAlignment(.center)
                    Button(NSLocalizedString("Retry", comment: "")) {
                        manager.fetchOfferings(offeringIdentifier: config.offeringIdentifier)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(config.accentColor)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(config.cardColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(displayedPackages) { package in
                    planCard(for: package)
                }
            }
        }
    }

    private func planCard(for package: TNPackage) -> some View {
        let isSelected = selectedPackage?.identifier == package.identifier
        let isCurrent = manager.currentPlanProductID == package.productIdentifier
        let isRecommended = manager.isRecommended(package)
        let intro = manager.introOffer(for: package)
        let savings = config.showSavingsBadge
            ? savingsBaseline.flatMap { package.savingsPercentage(comparedTo: $0) }
            : nil

        return Button {
            selectedPackage = package
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(planTitle(for: package))
                            .font(.headline)
                            .foregroundStyle(config.textPrimaryColor)

                        if isRecommended {
                            badge(NSLocalizedString("BEST VALUE", comment: ""), fg: .black, bg: config.accentColor)
                        }
                        if let savings, savings > 0 {
                            badge(
                                String(format: NSLocalizedString("SAVE %d%%", comment: ""), savings),
                                fg: config.secondaryColor,
                                bg: config.secondaryColor.opacity(0.15)
                            )
                        }
                        if let intro {
                            badge(
                                intro.paymentMode == .freeTrial
                                    ? NSLocalizedString("FREE TRIAL", comment: "")
                                    : NSLocalizedString("INTRO OFFER", comment: ""),
                                fg: config.accentColor,
                                bg: config.accentColor.opacity(0.18)
                            )
                        }
                        if isCurrent {
                            badge(
                                NSLocalizedString("CURRENT", comment: ""),
                                fg: config.secondaryColor,
                                bg: config.secondaryColor.opacity(0.15)
                            )
                        }
                    }

                    Text(planSubtitle(for: package))
                        .font(.caption)
                        .foregroundStyle(intro != nil ? config.accentColor : config.textSecondaryColor)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(package.localizedPriceString)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(config.accentColor)
                    if config.showPricePerMonth,
                       package.packageType != .monthly,
                       package.packageType != .lifetime,
                       let perMonth = package.localizedPricePerMonth {
                        Text(String(format: NSLocalizedString("%@ / mo", comment: ""), perMonth))
                            .font(.caption2)
                            .foregroundStyle(config.textMutedColor)
                    }
                }
            }
            .padding(16)
            .background(isSelected ? config.cardLightColor : config.cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? config.accentColor : config.textMutedColor.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        // Re-buying the plan you already have would be a no-op charge, so block it —
        // except for lifetime, which is the legitimate upgrade out of a subscription.
        .disabled(isCurrent && isTargetUnlocked && package.packageType != .lifetime)
    }

    private func badge(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .clipShape(Capsule())
    }

    private func planTitle(for package: TNPackage) -> String {
        package.packageType.localizedName ?? package.localizedTitle
    }

    private func planSubtitle(for package: TNPackage) -> String {
        if package.packageType == .lifetime {
            return NSLocalizedString("One-time purchase · Forever access", comment: "")
        }
        if let summary = manager.introOfferSummary(for: package) {
            return String(
                format: NSLocalizedString("%@ · Then %@", comment: ""),
                summary,
                package.localizedPriceString
            )
        }
        return NSLocalizedString("Auto-renewable subscription", comment: "")
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        Group {
            if !displayedPackages.isEmpty || isTargetUnlocked {
                Button(action: purchaseSelectedPlan) {
                    Group {
                        if manager.isPurchasing {
                            ProgressView().tint(.black)
                        } else {
                            Text(purchaseButtonTitle)
                                .font(.headline.weight(.black))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.black)
                    .background(config.premiumGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(selectedPackage == nil || manager.isPurchasing)
                .opacity(selectedPackage == nil ? 0.5 : 1)
            }
        }
    }

    private var purchaseButtonTitle: String {
        if isTargetUnlocked {
            return NSLocalizedString("Switch Plan", comment: "")
        }
        if let selected = selectedPackage, let intro = manager.introOffer(for: selected) {
            return intro.paymentMode == .freeTrial
                ? NSLocalizedString("Start Free Trial", comment: "")
                : NSLocalizedString("Claim Intro Offer", comment: "")
        }
        return NSLocalizedString("Continue", comment: "")
    }

    // MARK: - Footer

    @ViewBuilder
    private var legalLinksRow: some View {
        HStack(spacing: 20) {
            if let privacyURL = config.privacyURL {
                Link(NSLocalizedString("Privacy Policy", comment: ""), destination: privacyURL)
            }
            if let termsURL = config.termsURL {
                Link(NSLocalizedString("Terms of Use", comment: ""), destination: termsURL)
            }
        }
        .font(.caption2)
        .foregroundStyle(config.textMutedColor)
    }

    private var footerActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button(action: restorePurchases) {
                    if isRestoring {
                        ProgressView().tint(config.accentColor)
                    } else {
                        Text(NSLocalizedString("Restore Purchases", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(config.accentColor)
                    }
                }
                .disabled(isRestoring)

                if config.showRedeemCodeButton {
                    Text("•")
                        .font(.subheadline)
                        .foregroundStyle(config.textMutedColor)

                    Button {
                        isRedeemingOfferCode = true
                    } label: {
                        Text(NSLocalizedString("Redeem Code", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(config.accentColor)
                    }
                }
            }

            legalLinksRow

            Text(NSLocalizedString("Payment will be charged to your Apple ID. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period.", comment: ""))
                .font(.caption2)
                .foregroundStyle(config.textMutedColor.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func purchaseSelectedPlan() {
        guard let package = selectedPackage else { return }

        // Already on this plan: send them to Apple's management sheet instead of
        // charging them again.
        if manager.currentPlanProductID == package.productIdentifier {
            manager.showManageSubscriptions()
            return
        }

        manager.purchase(package: package) { result in
            switch result {
            case .success:
                if isTargetUnlocked || manager.isPremium {
                    activeAlert = .purchaseSuccess
                }
            case .failure(let error):
                switch error {
                case TNPurchaseError.userCancelled:
                    return  // the user's own choice is not an error worth an alert
                case TNPurchaseError.purchasePending:
                    activeAlert = .purchasePending
                default:
                    activeAlert = .purchaseFailed(error.localizedDescription)
                }
            }
        }
    }

    private func restorePurchases() {
        isRestoring = true
        manager.restorePurchases { result in
            isRestoring = false
            switch result {
            case .success(let hasPremium):
                activeAlert = hasPremium ? .restoreSuccess : .noSubscription
            case .failure:
                activeAlert = .restoreFailed
            }
        }
    }
}
