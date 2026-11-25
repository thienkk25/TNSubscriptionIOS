import SwiftUI
import UIKit

// MARK: - UIKit Presentation

/// Presents a SwiftUI paywall modally from UIKit — the same for every engine.
/// (Hiển thị paywall SwiftUI dạng modal từ UIKit — giống nhau ở mọi engine.)
///
/// `@preconcurrency`: the RevenueCat engine's class is not main-actor isolated and its presenters
/// predate strict concurrency; this keeps them compiling unchanged, exactly as calling UIKit does.
/// (`@preconcurrency`: class của engine RevenueCat không cô lập main actor và các hàm present của nó
/// có từ trước strict concurrency; nhờ vậy chúng vẫn compile như cũ, y như khi gọi thẳng UIKit.)
@preconcurrency @MainActor
package enum TNPaywallPresentation {

    package static func present<Content: View>(_ view: Content, from viewController: UIViewController) {
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .pageSheet

        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }

        // Presenting from a controller that already has something presented silently does
        // nothing, so walk to the top of the stack first.
        topMost(from: viewController).present(host, animated: true)
    }

    /// Walks the hierarchy to the controller actually on screen.
    /// (Đi theo cây view controller tới controller đang thật sự hiển thị.)
    package static func topMost(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return topMost(from: presented)
        }
        if let navigation = controller as? UINavigationController {
            return navigation.visibleViewController.map(topMost(from:)) ?? navigation
        }
        if let tab = controller as? UITabBarController {
            return tab.selectedViewController.map(topMost(from:)) ?? tab
        }
        return controller
    }
}
