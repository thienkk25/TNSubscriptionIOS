import UIKit
import SwiftUI

// MARK: - Paywall Presentation API

public extension TNSubscriptionAdapty {

    /// Presents the built-in paywall modally from UIKit.
    /// (Hiển thị paywall có sẵn dạng modal từ UIKit.)
    ///
    /// ```swift
    /// TNSubscriptionAdapty.presentDefaultPaywall(from: viewController, config: DefaultPaywallConfig(
    ///     appName: "My App",
    ///     features: [.init(icon: "sparkles", title: "Feature", subtitle: "Description")],
    ///     accentColor: .cyan
    /// ))
    /// ```
    @MainActor
    static func presentDefaultPaywall(
        from viewController: UIViewController,
        config: DefaultPaywallConfig = DefaultPaywallConfig()
    ) {
        guard isConfigured else {
            TNLog.error("presentDefaultPaywall was called before TNSubscriptionAdapty.configure(config:); nothing was presented.")
            return
        }
        TNPaywallPresentation.present(TNDefaultPaywallView(config: config), from: viewController)
    }

    /// Presents your own paywall view modally from UIKit.
    /// (Hiển thị paywall tự viết của bạn dạng modal từ UIKit.)
    ///
    /// Use `TNSubscriptionAdapty.shared` inside the view for purchase logic.
    /// (Dùng `TNSubscriptionAdapty.shared` trong view để xử lý mua.)
    ///
    /// ```swift
    /// TNSubscriptionAdapty.presentPaywall(from: viewController) { MyCustomPaywallView() }
    /// ```
    @MainActor
    static func presentPaywall<Content: View>(
        from viewController: UIViewController,
        @ViewBuilder content: () -> Content
    ) {
        TNPaywallPresentation.present(content(), from: viewController)
    }
}
