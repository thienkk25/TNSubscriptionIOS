import Foundation
import StoreKit
import UIKit

// MARK: - TNAppStoreSheets

/// Apple's own sheets — manage subscriptions, redeem an offer code, request a refund. They are
/// the same whichever vendor validates purchases, so every engine calls these.
/// (Các bảng của chính Apple — quản lý đăng ký, nhập offer code, yêu cầu hoàn tiền. Chúng giống
/// nhau dù nhà cung cấp nào xác thực giao dịch, nên mọi engine đều gọi các hàm này.)
@MainActor
package enum TNAppStoreSheets {

    /// The scene to present on: the foreground-active one, else any.
    /// (Scene để hiển thị: scene đang hoạt động ở foreground, nếu không thì bất kỳ scene nào.)
    package static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// Apple's "Manage Subscriptions" sheet, falling back to the App Store account page.
    /// (Bảng "Quản lý đăng ký" của Apple, nếu không mở được thì sang trang tài khoản App Store.)
    package static func showManageSubscriptions() {
        Task {
            if let scene = activeWindowScene() {
                do {
                    try await AppStore.showManageSubscriptions(in: scene)
                    return
                } catch {
                    TNLog.warn("showManageSubscriptions failed (\(error.localizedDescription)); opening the App Store URL instead.")
                }
            }
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                await UIApplication.shared.open(url)
            }
        }
    }

    /// Apple's offer code sheet. Once a code is redeemed, `Transaction.updates` delivers the
    /// transaction and the entitlement unlocks on its own.
    /// (Bảng nhập offer code của Apple. Sau khi nhập code, `Transaction.updates` gửi giao dịch về
    /// và quyền lợi tự mở khoá.)
    package static func presentOfferCodeRedemption() {
        guard let scene = activeWindowScene() else {
            TNLog.error("Cannot present the offer code sheet: no active UIWindowScene.")
            return
        }
        Task {
            do {
                try await AppStore.presentOfferCodeRedeemSheet(in: scene)
            } catch {
                TNLog.error("Presenting the offer code sheet FAILED: \(error.localizedDescription)")
            }
        }
    }

    /// Apple's refund sheet for an owned product. `transactionID` is looked up in
    /// `Transaction.currentEntitlements` when the engine does not already know it.
    /// (Bảng hoàn tiền của Apple cho một sản phẩm đang sở hữu. Nếu engine chưa biết
    /// `transactionID` thì tra trong `Transaction.currentEntitlements`.)
    ///
    /// Handling this in-app is what stops a refund request turning into a one-star review.
    /// (Xử lý ngay trong app là cách để một yêu cầu hoàn tiền không biến thành đánh giá 1 sao.)
    package static func requestRefund(for productID: String, transactionID knownID: UInt64? = nil) async -> Bool {
        guard let scene = activeWindowScene() else {
            TNLog.error("Cannot present the refund sheet: no active UIWindowScene.")
            return false
        }
        var transactionID = knownID
        if transactionID == nil {
            for await result in StoreKit.Transaction.currentEntitlements {
                if case .verified(let transaction) = result, transaction.productID == productID {
                    transactionID = transaction.id
                    break
                }
            }
        }
        guard let transactionID else {
            TNLog.warn("requestRefund(for:) found no App Store transaction for \(productID). Purchases from other platforms are refunded there.")
            return false
        }
        do {
            let status = try await StoreKit.Transaction.beginRefundRequest(for: transactionID, in: scene)
            if status == .success { TNLog.info("Refund request for \(productID) was submitted.") }
            return status == .success
        } catch {
            TNLog.error("Presenting the refund sheet for \(productID) FAILED: \(error.localizedDescription)")
            return false
        }
    }
}
