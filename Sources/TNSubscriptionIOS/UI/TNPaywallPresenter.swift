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
    
    private static func presentSwiftUIView<Content: View>(
        _ view: Content,
        from viewController: UIViewController
    ) {
        let hostingController = UIHostingController(rootView: view)
        hostingController.modalPresentationStyle = .pageSheet
        
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
        
        let targetPresenter = viewController.tn_topMostViewController()
        targetPresenter.present(hostingController, animated: true)
    }
}

// MARK: - UIViewController Extension

extension UIViewController {
    /// Traverses the view controller hierarchy to find the topmost presented controller.
    func tn_topMostViewController() -> UIViewController {
        if let presented = self.presentedViewController {
            return presented.tn_topMostViewController()
        }
        if let navigation = self as? UINavigationController {
            return navigation.visibleViewController?.tn_topMostViewController() ?? navigation
        }
        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.tn_topMostViewController() ?? tab
        }
        return self
    }
}
