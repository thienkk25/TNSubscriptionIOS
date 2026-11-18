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
        present(TNDefaultPaywallView(config: config), from: viewController)
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
        present(content(), from: viewController)
    }

    @MainActor
    private static func present<Content: View>(_ view: Content, from viewController: UIViewController) {
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .pageSheet

        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }

        // Presenting from a controller that already has something presented silently
        // does nothing, so walk to the top of the stack first.
        viewController.tn_topMostViewController().present(host, animated: true)
    }
}

// MARK: - UIViewController Helper

extension UIViewController {
    /// Walks the hierarchy to the controller actually on screen.
    /// (Đi theo cây view controller tới controller đang thật sự hiển thị.)
    func tn_topMostViewController() -> UIViewController {
        if let presented = presentedViewController {
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
