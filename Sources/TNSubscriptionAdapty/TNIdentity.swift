import Foundation
import Security
import UIKit

// MARK: - TNIdentity

/// A persistent device/client identity, stored in the Keychain so it survives app reinstalls.
/// (Danh tính client/thiết bị cố định, lưu trong Keychain nên vẫn còn sau khi cài lại app.)
///
/// **Optional.** Nothing in this engine needs it: entitlements come from Apple alone.
/// It exists for apps that *also* call their own backend and want a stable caller ID,
/// or that want `appAccountToken` on purchases so App Store Server Notifications can be
/// attributed to a user.
/// (**Không bắt buộc.** Engine này không cần nó: quyền lợi lấy trực tiếp từ Apple.
/// Nó dành cho app *đồng thời* gọi backend riêng và cần một ID gọi cố định, hoặc muốn gắn
/// `appAccountToken` vào giao dịch để App Store Server Notifications quy được về user.)
public enum TNIdentity {

    private static let clientIdKeychainAccount = "client_id"
    private static let clientIdUserDefaultsKey = "persistent_client_id"
    internal static let keychainService: String = Bundle.main.bundleIdentifier ?? "com.tnsubscription.adapty"

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
    public static var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? clientId
    }

    /// Standard identity headers for your own backend.
    /// (Bộ header danh tính chuẩn để gọi backend của bạn.)
    ///
    /// ```swift
    /// var request = URLRequest(url: url)
    /// request = request.applyingTNIdentityHeaders()
    /// ```
    public static func identityHeaders(userId: String? = nil) -> [String: String] {
        var headers = [
            "X-Client-Id": clientId,
            "X-Device-Id": deviceId,
        ]
        if let userId, !userId.isEmpty {
            headers["X-User-Id"] = userId
        }
        return headers
    }

    // MARK: - Keychain

    /// Reads a string from the Keychain. Returns `nil` when absent or unreadable.
    /// (Đọc một string từ Keychain. Trả về `nil` nếu không có hoặc không đọc được.)
    internal static func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                TNLog.warn("Reading '\(account)' from the Keychain failed with OSStatus \(status).")
            }
            return nil
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Writes a string to the Keychain, replacing any existing value for the same account.
    /// (Ghi một string vào Keychain, thay thế giá trị cũ của cùng account.)
    ///
    /// Uses `kSecAttrAccessibleAfterFirstUnlock` so the value is readable during a
    /// background launch, after the device has been unlocked at least once since boot.
    /// (Dùng `kSecAttrAccessibleAfterFirstUnlock` để vẫn đọc được khi app khởi động ở
    /// background, miễn là thiết bị đã được mở khoá ít nhất một lần sau khi bật máy.)
    internal static func saveToKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
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
