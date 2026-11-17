import SwiftUI

/// An intentionally empty app, used only as `TEST_HOST` for the StoreKit integration tests.
/// (Một app rỗng có chủ đích, chỉ dùng làm `TEST_HOST` cho integration test StoreKit.)
///
/// StoreKit will not serve products to a process that is not an app, so the tests need a real
/// bundle to run inside. Nothing here is shipped.
/// (StoreKit không trả sản phẩm cho tiến trình không phải app, nên test cần một bundle thật để
/// chạy bên trong. Không có gì ở đây được phát hành.)
@main
struct TNCoreTestHostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("TNSubscriptionCore integration test host")
                .padding()
        }
    }
}
