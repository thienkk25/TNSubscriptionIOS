import SwiftUI
import StoreKit

// MARK: - TNPaywallScreen

/// The built-in paywall, written once for every engine that conforms to `TNPaywallEngine`.
/// (Paywall có sẵn, viết một lần cho mọi engine tuân theo `TNPaywallEngine`.)
///
/// Apps never see this type: each engine exposes it as its own public `TNDefaultPaywallView`,
/// which is a one-line wrapper. A fix here reaches Core, Adapty and Qonversion at once.
/// (App không bao giờ thấy kiểu này: mỗi engine expose nó qua `TNDefaultPaywallView` public của
/// riêng mình — chỉ là lớp bọc một dòng. Sửa ở đây là Core, Adapty và Qonversion cùng được sửa.)
package struct TNPaywallScreen<Engine: TNPaywallEngine>: View {

    @ObservedObject private var manager: Engine
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPackage: Engine.Package?
    @State private var activeAlert: UpgradeAlert?
    @State private var isRestoring = false
    @State private var isRedeemingOfferCode = false

    package let config: DefaultPaywallConfig

    package init(engine: Engine, config: DefaultPaywallConfig) {
        self.manager = engine
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
    private var displayedPackages: [Engine.Package] {
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
    private var savingsBaseline: Engine.Package? {
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

    package var body: some View {
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
            .navigationTitle(config.text(.navigationTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    closeButton
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
            // A no-op except where the vendor counts paywall views (Adapty's A/B tests).
            await manager.paywallDidAppear()
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
                    title: Text(config.text(.purchaseSuccessTitle)),
                    message: Text(config.text(.purchaseSuccessMessage)),
                    dismissButton: .default(Text(config.text(.ok))) { dismiss() }
                )
            case .purchaseFailed(let message):
                return Alert(
                    title: Text(config.text(.purchaseFailedTitle)),
                    message: Text(message),
                    dismissButton: .default(Text(config.text(.ok)))
                )
            case .purchasePending:
                return Alert(
                    title: Text(config.text(.purchasePendingTitle)),
                    message: Text(config.text(.purchasePendingMessage)),
                    dismissButton: .default(Text(config.text(.ok)))
                )
            case .restoreSuccess:
                return Alert(
                    title: Text(config.text(.restoreSuccessTitle)),
                    message: Text(config.text(.restoreSuccessMessage)),
                    dismissButton: .default(Text(config.text(.ok)))
                )
            case .restoreFailed:
                return Alert(
                    title: Text(config.text(.restoreFailedTitle)),
                    message: Text(config.text(.restoreFailedMessage)),
                    dismissButton: .default(Text(config.text(.ok)))
                )
            case .noSubscription:
                return Alert(
                    title: Text(config.text(.noSubscriptionTitle)),
                    message: Text(config.text(.noSubscriptionMessage)),
                    dismissButton: .default(Text(config.text(.ok)))
                )
            }
        }
    }

    private func selectDefaultPackageIfNeeded() {
        guard selectedPackage == nil, !displayedPackages.isEmpty else { return }
        selectedPackage = displayedPackages.first { manager.isRecommended($0) } ?? displayedPackages.first
    }

    /// The toolbar's Close button. Tinted only when `closeButtonTint` is set, so by default it is
    /// the plain system control (the standard Liquid Glass capsule on iOS 26).
    /// (Nút Close trên toolbar. Chỉ tô màu khi có `closeButtonTint`, nên mặc định nó là control
    /// chuẩn của hệ thống — viên nang Liquid Glass trên iOS 26.)
    @ViewBuilder
    private var closeButton: some View {
        let button = Button(config.text(.close)) { dismiss() }
        if let tint = config.closeButtonTint {
            button.foregroundStyle(tint)
        } else {
            button
        }
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

    /// The app's own copy from `DefaultPaywallConfig` when set, otherwise the generic default.
    /// (Câu của chính app trong `DefaultPaywallConfig` nếu có, nếu không thì dùng câu mặc định.)
    private var headerTitle: String {
        isTargetUnlocked
            ? (config.unlockedHeaderTitle ?? NSLocalizedString("You're Premium", comment: ""))
            : (config.headerTitle ?? NSLocalizedString("Upgrade to Premium", comment: ""))
    }

    private var headerSubtitle: String {
        isTargetUnlocked
            ? (config.unlockedHeaderSubtitle ?? NSLocalizedString("Thank you for supporting the app. Manage or change your plan below.", comment: ""))
            : (config.headerSubtitle ?? NSLocalizedString("Unlock all premium features, custom designs, and settings.", comment: ""))
    }

    private var verifyingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(config.accentColor)
                .scaleEffect(1.3)
            Text(config.text(.verifying))
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
                Text(config.text(.premiumActive))
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

            Text(config.text(.switchPlanHint))
                .font(.caption)
                .foregroundStyle(config.textMutedColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            plansSection
            purchaseButton

            Button {
                manager.showManageSubscriptions()
            } label: {
                Text(config.text(.manageSubscription))
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
                    text: config.text(.gracePeriodNotice),
                    tint: .orange
                )
            } else if info.hasBillingIssue {
                noticeRow(
                    icon: "creditcard.trianglebadge.exclamationmark",
                    text: config.text(.billingRetryNotice),
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
            Text(config.text(.whatsIncluded))
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
            Text(config.text(.choosePlan))
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
                    Text(manager.offeringsError ?? config.text(.plansUnavailable))
                        .font(.caption)
                        .foregroundStyle(config.textSecondaryColor)
                        .multilineTextAlignment(.center)
                    Button(config.text(.retry)) {
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

    private func planCard(for package: Engine.Package) -> some View {
        let isSelected = selectedPackage?.identifier == package.identifier
        let isCurrent = manager.currentPlanProductID == package.productIdentifier
        let isRecommended = manager.isRecommended(package)
        // The offer the user will actually get — engines return one only when it applies.
        let offer = manager.paywallOffer(for: package)
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
                            badge(config.text(.bestValue), fg: .black, bg: config.accentColor)
                        }
                        if let savings, savings > 0 {
                            badge(
                                String(format: NSLocalizedString("SAVE %d%%", comment: ""), savings),
                                fg: config.secondaryColor,
                                bg: config.secondaryColor.opacity(0.15)
                            )
                        }
                        if let offer {
                            badge(
                                badgeText(for: offer),
                                fg: config.accentColor,
                                bg: config.accentColor.opacity(0.18)
                            )
                        }
                        if isCurrent {
                            badge(
                                config.text(.current),
                                fg: config.secondaryColor,
                                bg: config.secondaryColor.opacity(0.15)
                            )
                        }
                    }

                    Text(planSubtitle(for: package))
                        .font(.caption)
                        .foregroundStyle(offer != nil ? config.accentColor : config.textSecondaryColor)
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

    /// The plan's name: your replacement from `texts` if set, otherwise the built-in name. A plan with
    /// a non-standard period uses the store's own product name.
    /// (Tên gói: chữ thay thế trong `texts` nếu có, nếu không thì tên có sẵn. Gói có kỳ hạn không chuẩn
    /// thì dùng tên sản phẩm của store.)
    private func planTitle(for package: Engine.Package) -> String {
        switch package.packageType {
        case .weekly: return config.text(.weekly)
        case .monthly: return config.text(.monthly)
        case .twoMonth: return config.text(.twoMonths)
        case .threeMonth: return config.text(.threeMonths)
        case .sixMonth: return config.text(.sixMonths)
        case .annual: return config.text(.yearly)
        case .lifetime: return config.text(.lifetime)
        case .custom, .unknown: return package.localizedTitle
        }
    }

    private func planSubtitle(for package: Engine.Package) -> String {
        if package.packageType == .lifetime {
            return config.text(.lifetimeSubtitle)
        }
        if let summary = manager.paywallOffer(for: package)?.localizedSummary {
            return String(
                format: NSLocalizedString("%@ · Then %@", comment: ""),
                summary,
                package.localizedPriceString
            )
        }
        return config.text(.autoRenewSubtitle)
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
            return config.text(.switchPlan)
        }
        if let selected = selectedPackage, let offer = manager.paywallOffer(for: selected) {
            switch offer.paywallKind {
            case .freeTrial: return config.text(.startFreeTrial)
            case .introductory: return config.text(.claimIntroOffer)
            case .winBack, .other: return config.text(.claimOffer)
            }
        }
        return config.text(.continueButton)
    }

    /// The badge for the offer the user will get. (Nhãn cho ưu đãi người dùng sẽ nhận.)
    private func badgeText(for offer: Engine.Offer) -> String {
        switch offer.paywallKind {
        case .freeTrial: return config.text(.freeTrial)
        case .introductory: return config.text(.introOffer)
        case .winBack: return config.text(.welcomeBack)
        case .other: return config.text(.specialOffer)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var legalLinksRow: some View {
        HStack(spacing: 20) {
            if let privacyURL = config.privacyURL {
                Link(config.text(.privacyPolicy), destination: privacyURL)
            }
            if let termsURL = config.termsURL {
                Link(config.text(.termsOfUse), destination: termsURL)
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
                        Text(config.text(.restorePurchases))
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
                        Text(config.text(.redeemCode))
                            .font(.subheadline)
                            .foregroundStyle(config.accentColor)
                    }
                }
            }

            legalLinksRow

            Text(config.text(.legalDisclaimer))
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
                switch (error as? any TNPaywallPurchaseError)?.paywallOutcome {
                case .cancelled:
                    return  // the user's own choice is not an error worth an alert
                case .pending:
                    activeAlert = .purchasePending
                case .failed, nil:
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
