import UIKit
import SwiftUI

// MARK: - Paywall Presentation API

extension TNSubscriptionIOS {
    
    /// Presents the **default** built-in paywall screen modally.
    ///
    /// Usage:
    /// ```swift
    /// TNSubscriptionIOS.presentDefaultPaywall(from: viewController, config: DefaultPaywallConfig(
    ///     appName: "My App",
    ///     features: [
    ///         .init(icon: "sparkles", title: "Feature", subtitle: "Description")
    ///     ],
    ///     accentColor: .cyan
    /// ))
    /// ```
    ///
    /// - Parameters:
    ///   - viewController: The presenting UIViewController.
    ///   - config: Configuration for the default paywall appearance and content.
    public static func presentDefaultPaywall(
        from viewController: UIViewController,
        config: DefaultPaywallConfig = DefaultPaywallConfig()
    ) {
        let view = TNDefaultPaywallView(config: config)
        presentSwiftUIView(view, from: viewController)
    }
    
    /// Presents a **fully custom** paywall view modally.
    ///
    /// The host app provides its own SwiftUI view. Use `TNSubscriptionIOS.shared`
    /// inside your custom view to access purchase logic.
    ///
    /// Usage:
    /// ```swift
    /// TNSubscriptionIOS.presentPaywall(from: viewController) {
    ///     MyCustomPaywallView()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - viewController: The presenting UIViewController.
    ///   - content: A closure returning the custom SwiftUI view.
    public static func presentPaywall<Content: View>(
        from viewController: UIViewController,
        @ViewBuilder content: () -> Content
    ) {
        let view = content()
        presentSwiftUIView(view, from: viewController)
    }

    // MARK: - Internal Presentation Helper

    // The page-sheet and top-most-controller logic is shared with every engine
    // (`TNPaywallPresentation` in TNSubscriptionShared).
    // (Phần page sheet và tìm controller trên cùng dùng chung với mọi engine.)
    private static func presentSwiftUIView<Content: View>(
        _ view: Content,
        from viewController: UIViewController
    ) {
        TNPaywallPresentation.present(view, from: viewController)
    }
}
