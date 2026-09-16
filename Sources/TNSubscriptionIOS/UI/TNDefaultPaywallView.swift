import SwiftUI
import RevenueCat

// MARK: - Default Paywall View

/// The built-in paywall view provided by TNSubscriptionIOS.
/// Fully configurable via `DefaultPaywallConfig`.
///
/// Host apps can use this directly or present via `TNSubscriptionIOS.presentDefaultPaywall(from:config:)`.
struct TNDefaultPaywallView: View {
    @ObservedObject private var manager = TNSubscriptionIOS.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPackage: Package?
    @State private var activeAlert: UpgradeAlert?
    @State private var isRestoring = false
    
    let config: DefaultPaywallConfig
    
    private enum UpgradeAlert: Identifiable {
        case purchaseSuccess
        case purchaseFailed(String)
        case restoreSuccess
        case restoreFailed
        case noSubscription
        
        var id: String {
            switch self {
            case .purchaseSuccess: return "purchaseSuccess"
            case .purchaseFailed(let msg): return "purchaseFailed-\(msg)"
            case .restoreSuccess: return "restoreSuccess"
            case .restoreFailed: return "restoreFailed"
            case .noSubscription: return "noSubscription"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                config.backgroundColor.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        headerSection
                        
                        if manager.entitlementState == .unknown {
                            verifyingSection
                        } else if manager.entitlementState == .unlocked {
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
        .onAppear {
            manager.checkSubscriptionStatus()
            manager.fetchOfferings()
            if selectedPackage == nil {
                selectedPackage = manager.availablePackages.first(where: TNSubscriptionIOS.isRecommendedPackage)
                    ?? manager.availablePackages.first
            }
        }
        .onChange(of: manager.availablePackages.map(\.identifier)) { _ in
            guard selectedPackage == nil, !manager.availablePackages.isEmpty else { return }
            selectedPackage = manager.availablePackages.first(where: TNSubscriptionIOS.isRecommendedPackage)
                ?? manager.availablePackages.first
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
    
    // MARK: - Sections
    
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
        switch manager.entitlementState {
        case .unlocked:
            return NSLocalizedString("You're Premium", comment: "")
        default:
            return NSLocalizedString("Upgrade to Premium", comment: "")
        }
    }
    
    private var headerSubtitle: String {
        switch manager.entitlementState {
        case .unlocked:
            return NSLocalizedString("Thank you for supporting the app. Manage or change your plan below.", comment: "")
        default:
            return NSLocalizedString("Unlock all premium features, custom designs, and settings.", comment: "")
        }
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
            
            featuresSection
            
            Text(NSLocalizedString("Want a different plan? Choose one below to switch. Apple will prorate your subscription when applicable.", comment: ""))
                .font(.caption)
                .foregroundStyle(config.textMutedColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            plansSection
            purchaseButton
            
            Button {
                openSubscriptionManagement()
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
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("What's included", comment: ""))
                .font(.headline)
                .foregroundStyle(config.textPrimaryColor)
            
            VStack(spacing: 10) {
                ForEach(config.features, id: \.title) { feature in
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
            } else if manager.availablePackages.isEmpty {
                VStack(spacing: 12) {
                    Text(manager.offeringsError ?? NSLocalizedString("Plans could not be loaded.", comment: ""))
                        .font(.caption)
                        .foregroundStyle(config.textSecondaryColor)
                        .multilineTextAlignment(.center)
                    Button(NSLocalizedString("Retry", comment: "")) {
                        manager.fetchOfferings()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(config.accentColor)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(config.cardColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(manager.availablePackages, id: \.identifier) { package in
                    planCard(for: package)
                }
            }
        }
    }
    
    private func planCard(for package: Package) -> some View {
        let isSelected = selectedPackage?.identifier == package.identifier
        let isCurrent = manager.currentPlanProductID == package.storeProduct.productIdentifier
        let isRecommended = TNSubscriptionIOS.isRecommendedPackage(package)
        
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
                            Text(NSLocalizedString("BEST VALUE", comment: ""))
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(config.accentColor)
                                .clipShape(Capsule())
                        }
                        if isCurrent {
                            Text(NSLocalizedString("CURRENT", comment: ""))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(config.secondaryColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(config.secondaryColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(planSubtitle(for: package))
                        .font(.caption)
                        .foregroundStyle(config.textSecondaryColor)
                }
                Spacer()
                Text(package.storeProduct.localizedPriceString)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(config.accentColor)
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
        .disabled(isCurrent && manager.entitlementState == .unlocked && package.packageType != .lifetime)
    }
    
    private var purchaseButton: some View {
        Group {
            if !manager.availablePackages.isEmpty || manager.entitlementState == .unlocked {
                Button(action: purchaseSelectedPlan) {
                    Group {
                        if manager.isPurchasing {
                            ProgressView()
                                .tint(.black)
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
        if manager.entitlementState == .unlocked {
            return NSLocalizedString("Switch Plan", comment: "")
        }
        return NSLocalizedString("Continue", comment: "")
    }
    
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
            Button(action: restorePurchases) {
                if isRestoring {
                    ProgressView()
                        .tint(config.accentColor)
                } else {
                    Text(NSLocalizedString("Restore Purchases", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(config.accentColor)
                }
            }
            .disabled(isRestoring)
            
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
    
    private func planTitle(for package: Package) -> String {
        switch package.packageType {
        case .weekly: return NSLocalizedString("Weekly", comment: "")
        case .monthly: return NSLocalizedString("Monthly", comment: "")
        case .annual: return NSLocalizedString("Yearly", comment: "")
        case .lifetime: return NSLocalizedString("Lifetime", comment: "")
        case .sixMonth: return NSLocalizedString("6 Months", comment: "")
        case .threeMonth: return NSLocalizedString("3 Months", comment: "")
        case .twoMonth: return NSLocalizedString("2 Months", comment: "")
        case .custom, .unknown: return package.storeProduct.localizedTitle
        @unknown default: return package.storeProduct.localizedTitle
        }
    }
    
    private func planSubtitle(for package: Package) -> String {
        if package.packageType == .lifetime {
            return NSLocalizedString("One-time purchase · Forever access", comment: "")
        }
        return NSLocalizedString("Auto-renewable subscription", comment: "")
    }
    
    private func purchaseSelectedPlan() {
        guard let package = selectedPackage else { return }
        if manager.currentPlanProductID == package.storeProduct.productIdentifier {
            openSubscriptionManagement()
            return
        }
        
        manager.purchase(package: package) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    if manager.isPremium {
                        activeAlert = .purchaseSuccess
                    }
                case .failure(let error):
                    if let flowError = error as? TNSubscriptionIOS.PurchaseFlowError,
                       case .userCancelled = flowError {
                        return
                    }
                    activeAlert = .purchaseFailed(error.localizedDescription)
                }
            }
        }
    }
    
    private func restorePurchases() {
        isRestoring = true
        manager.restorePurchases { result in
            DispatchQueue.main.async {
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
    
    private func openSubscriptionManagement() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }
}
