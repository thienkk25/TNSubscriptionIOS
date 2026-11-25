import Foundation
import Security
import UIKit

// MARK: - TNIdentity

/// A persistent device/client identity, stored in the Keychain so it survives app reinstalls.
/// (Danh tính client/thiết bị cố định, lưu trong Keychain nên vẫn còn sau khi cài lại app.)
///
/// **Optional.** No engine needs it: entitlements come from Apple or the billing vendor.
/// It exists for apps that *also* call their own backend and want a stable caller ID,
/// or that want `appAccountToken` on purchases so App Store Server Notifications can be
/// attributed to a user.
/// (**Không bắt buộc.** Không engine nào cần nó: quyền lợi lấy từ Apple hoặc nhà cung cấp.
/// Nó dành cho app *đồng thời* gọi backend riêng và cần một ID gọi cố định, hoặc muốn gắn
/// `appAccountToken` vào giao dịch để App Store Server Notifications quy được về user.)
///
/// Every engine reads the same Keychain item, so the ID survives a switch of engine. Items are
/// written `AfterFirstUnlockThisDeviceOnly`: they survive a reinstall but are not carried to a new
/// device through a backup — the behaviour the RevenueCat engine has always had.
/// (Mọi engine đọc cùng một Keychain item, nên ID còn nguyên khi đổi engine. Item được ghi với
/// `AfterFirstUnlockThisDeviceOnly`: còn sau khi cài lại app nhưng không theo bản sao lưu sang máy
/// mới — đúng hành vi engine RevenueCat vẫn có từ trước.)
public enum TNIdentity {

    private static let clientIdKeychainAccount = "client_id"
    private static let clientIdUserDefaultsKey = "persistent_client_id"
    package static let keychainService: String = Bundle.main.bundleIdentifier ?? "com.tnsubscription"

    private static let lock = NSLock()
    private static var cachedClientId: String?

    /// A persistent, unique client ID: a UUID stored in the Keychain (surviving reinstalls)
    /// and cached in memory for O(1) access.
    /// (Client ID cố định, duy nhất: một UUID lưu trong Keychain — vẫn còn sau khi cài lại app —
    /// và cache trong bộ nhớ để truy cập O(1).)
    ///
    /// Resolution order: memory cache → Keychain → UserDefaults (migrated into the Keychain) → new UUID.
    /// (Thứ tự tìm: cache bộ nhớ → Keychain → UserDefaults (sẽ được chuyển vào Keychain) → tạo UUID mới.)
    public static var clientId: String {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedClientId {
            return cached
        }

        // 1. Keychain — the durable source of truth.
        if let fromKeychain = loadFromKeychain(account: clientIdKeychainAccount), !fromKeychain.isEmpty {
            cachedClientId = fromKeychain
            return fromKeychain
        }

        // 2. Legacy UserDefaults value from an older build — migrate it up into the Keychain.
        if let legacy = UserDefaults.standard.string(forKey: clientIdUserDefaultsKey), !legacy.isEmpty {
            saveToKeychain(account: clientIdKeychainAccount, value: legacy)
            cachedClientId = legacy
            TNLog.debug("Migrated the legacy client_id from UserDefaults into the Keychain.")
            return legacy
        }

        // 3. First run on this device: mint one.
        let newId = UUID().uuidString
        saveToKeychain(account: clientIdKeychainAccount, value: newId)
        UserDefaults.standard.set(newId, forKey: clientIdUserDefaultsKey)
        cachedClientId = newId
        TNLog.debug("Generated a new persistent client_id.")
        return newId
    }

    /// `clientId` as a `UUID`, for use as StoreKit's `appAccountToken`.
    /// (`clientId` ở dạng `UUID`, dùng làm `appAccountToken` của StoreKit.)
    ///
    /// Returns `nil` only if a non-UUID value was migrated in from an older build —
    /// Apple rejects anything that is not a UUID.
    /// (Chỉ trả về `nil` khi giá trị chuyển lên từ bản build cũ không phải UUID —
    /// Apple từ chối mọi giá trị không phải UUID.)
    public static var appAccountToken: UUID? {
        UUID(uuidString: clientId)
    }

    /// The per-install vendor identifier, which resets when the user deletes every app
    /// from this vendor. Not durable — prefer `clientId`.
    /// (Vendor identifier theo lần cài, bị reset khi người dùng xoá hết app của cùng nhà phát triển.
    /// Không bền — nên ưu tiên `clientId`.)
    /// Empty in the rare moment the system has no vendor identifier yet (before first unlock);
    /// `identityHeaders` then leaves `X-Device-Id` out rather than send a fake value.
    /// (Rỗng trong khoảnh khắc hiếm hoi hệ thống chưa có vendor identifier — trước lần mở khoá đầu;
    /// khi đó `identityHeaders` bỏ `X-Device-Id` thay vì gửi giá trị giả.)
    public static var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? ""
    }

    /// Standard identity headers for your own backend.
    /// (Bộ header danh tính chuẩn để gọi backend của bạn.)
    ///
    /// ```swift
    /// var request = URLRequest(url: url)
    /// request = request.applyingTNIdentityHeaders()
    /// ```
    public static func identityHeaders(userId: String? = nil) -> [String: String] {
        var headers = ["X-Client-Id": clientId]
        let device = deviceId
        if !device.isEmpty {
            headers["X-Device-Id"] = device
        }
        if let userId, !userId.isEmpty {
            headers["X-User-Id"] = userId
        }
        return headers
    }

    // MARK: - Keychain

    /// Reads a string from the Keychain. Returns `nil` when absent or unreadable.
    /// (Đọc một string từ Keychain. Trả về `nil` nếu không có hoặc không đọc được.)
    package static func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data,
           let value = String(data: data, encoding: .utf8), !value.isEmpty {
            return value
        }
        if status != errSecSuccess, status != errSecItemNotFound {
            TNLog.warn("Reading '\(account)' from the Keychain failed with OSStatus \(status).")
        }

        // Early RevenueCat-engine builds wrote items without a service; read one once and move it
        // under the service so it is found directly next time.
        // (Các bản đầu của engine RevenueCat ghi item không có service; đọc một lần rồi chuyển nó vào
        // service để lần sau tìm thấy ngay.)
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var legacyItem: CFTypeRef?
        guard SecItemCopyMatching(legacyQuery as CFDictionary, &legacyItem) == errSecSuccess,
              let data = legacyItem as? Data,
              let legacy = String(data: data, encoding: .utf8), !legacy.isEmpty else {
            return nil
        }
        saveToKeychain(account: account, value: legacy)
        return legacy
    }

    /// Writes a string to the Keychain, replacing any existing value for the same account.
    /// (Ghi một string vào Keychain, thay thế giá trị cũ của cùng account.)
    ///
    /// Uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: readable during a background launch
    /// once the device has been unlocked since boot, and never restored onto another device.
    /// (Dùng `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: đọc được khi app khởi động ở
    /// background sau lần mở khoá đầu kể từ khi bật máy, và không bao giờ được khôi phục sang máy khác.)
    package static func saveToKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                TNLog.warn("Writing '\(account)' to the Keychain failed with OSStatus \(addStatus).")
            }
            return
        }

        TNLog.warn("Updating '\(account)' in the Keychain failed with OSStatus \(updateStatus).")
    }
}

// MARK: - URLRequest Convenience

public extension URLRequest {

    /// Attaches `identityHeaders(userId:)` to this request. (Gắn `identityHeaders(userId:)` vào request.)
    mutating func applyTNIdentityHeaders(userId: String? = nil) {
        for (key, value) in TNIdentity.identityHeaders(userId: userId) {
            setValue(value, forHTTPHeaderField: key)
        }
    }

    /// Returns a copy of this request with `X-Client-Id`, `X-Device-Id` and optionally
    /// `X-User-Id` applied.
    /// (Trả về bản copy của request đã gắn `X-Client-Id`, `X-Device-Id` và tuỳ chọn `X-User-Id`.)
    ///
    /// ```swift
    /// let request = URLRequest(url: url).applyingTNIdentityHeaders()
    /// ```
    func applyingTNIdentityHeaders(userId: String? = nil) -> URLRequest {
        var copy = self
        for (key, value) in TNIdentity.identityHeaders(userId: userId) {
            copy.setValue(value, forHTTPHeaderField: key)
        }
        return copy
    }
}
