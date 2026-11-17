import XCTest
import StoreKit
@testable import TNSubscriptionCore

// MARK: - Config

/// Tests for the pure value logic: config resolution, offering synthesis, period maths.
/// (Kiểm thử cho phần logic thuần giá trị: xử lý config, tự sinh offering, tính toán kỳ hạn.)
///
/// Note on scope: anything that needs a real `StoreKit.Product` or a `Transaction` cannot be
/// unit-tested here — StoreKit 2 provides no public initialisers for them. Those paths need
/// `SKTestSession` in an XCTest host app with a `.storekit` configuration file attached.
/// (Về phạm vi: những gì cần `StoreKit.Product` hoặc `Transaction` thật thì không thể unit-test
/// ở đây — StoreKit 2 không cung cấp initializer công khai cho chúng. Các luồng đó cần
/// `SKTestSession` trong một XCTest host app có kèm file cấu hình `.storekit`.)
final class TNSubscriptionConfigTests: XCTestCase {

    func testAllProductIDsUnionsEveryEntitlement() {
        let config = TNSubscriptionConfig(entitlements: [
            TNEntitlement(id: "Premium", productIDs: ["weekly", "yearly"]),
            TNEntitlement(id: "Sale", productIDs: ["sale_yearly"]),
        ])

        XCTAssertEqual(config.allProductIDs, ["weekly", "yearly", "sale_yearly"])
        XCTAssertEqual(config.allEntitlementIDs, ["Premium", "Sale"])
    }

    func testOverlappingProductIDsAreNotDoubleCounted() {
        // A product can legitimately grant two entitlements.
        let config = TNSubscriptionConfig(entitlements: [
            TNEntitlement(id: "Premium", productIDs: ["yearly"]),
            TNEntitlement(id: "Pro", productIDs: ["yearly", "pro_yearly"]),
        ])

        XCTAssertEqual(config.allProductIDs, ["yearly", "pro_yearly"])
    }

    func testDefaultOfferingIsSynthesisedWhenNoneDeclared() {
        let config = TNSubscriptionConfig(entitlements: [
            TNEntitlement(id: "Premium", productIDs: ["weekly", "yearly"]),
        ])

        let resolved = config.resolvedOfferings
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.identifier, "default")
        XCTAssertEqual(Set(resolved.first?.productIDs ?? []), ["weekly", "yearly"])
    }

    func testDeclaredOfferingsAreNotOverriddenBySynthesis() {
        let config = TNSubscriptionConfig(
            entitlements: [TNEntitlement(id: "Premium", productIDs: ["weekly", "yearly"])],
            offerings: [TNOffering(identifier: "sale", productIDs: ["yearly"])]
        )

        XCTAssertEqual(config.resolvedOfferings.map(\.identifier), ["sale"])
    }

    func testNoOfferingIsSynthesisedWithoutProducts() {
        let config = TNSubscriptionConfig(entitlements: [])
        XCTAssertTrue(config.resolvedOfferings.isEmpty)
    }

    func testLoadableProductIDsIncludeOfferingOnlyProducts() {
        // A promo product may be sold on a paywall before it is wired into an entitlement.
        // It still has to be fetched from the App Store, or the paywall renders empty.
        let config = TNSubscriptionConfig(
            entitlements: [TNEntitlement(id: "Premium", productIDs: ["yearly"])],
            offerings: [TNOffering(identifier: "promo", productIDs: ["yearly", "promo_only"])]
        )

        XCTAssertEqual(config.allLoadableProductIDs, ["yearly", "promo_only"])
    }

    func testSingleEntitlementConvenienceInit() {
        let config = TNSubscriptionConfig(productIDs: ["weekly", "yearly"])

        XCTAssertEqual(config.allEntitlementIDs, ["Premium"])
        XCTAssertEqual(config.allProductIDs, ["weekly", "yearly"])
    }

    func testCurrentOfferingDefaultsToTheFirstDeclared() {
        let config = TNSubscriptionConfig(
            entitlements: [TNEntitlement(id: "Premium", productIDs: ["yearly"])],
            offerings: [
                TNOffering(identifier: "a", productIDs: ["yearly"]),
                TNOffering(identifier: "b", productIDs: ["yearly"]),
            ]
        )

        XCTAssertNil(config.currentOfferingIdentifier)
        XCTAssertEqual(config.resolvedOfferings.first?.identifier, "a")
    }
}

// MARK: - Package Type

final class TNPackageTypeTests: XCTestCase {

    func testSortOrderPutsLongestCommitmentFirst() {
        let shuffled: [TNPackageType] = [.weekly, .lifetime, .monthly, .annual, .sixMonth]
        let sorted = shuffled.sorted { $0.sortOrder < $1.sortOrder }

        XCTAssertEqual(sorted, [.lifetime, .annual, .sixMonth, .monthly, .weekly])
    }

    func testEveryTypeHasADistinctSortOrder() {
        let orders = TNPackageType.allCases.map(\.sortOrder)
        XCTAssertEqual(Set(orders).count, orders.count, "Two package types share a sort order, so paywall ordering would be nondeterministic.")
    }

    func testOnlyCustomAndUnknownLackADisplayName() {
        for type in TNPackageType.allCases {
            switch type {
            case .custom, .unknown:
                XCTAssertNil(type.localizedName, "\(type) should fall back to the store's own product name.")
            default:
                XCTAssertNotNil(type.localizedName, "\(type) needs a display name for the paywall.")
            }
        }
    }
}

// MARK: - Entitlement Snapshot

final class TNEntitlementSnapshotTests: XCTestCase {

    func testSnapshotRoundTrips() {
        TNEntitlementSnapshot.shared.update(isPremium: true, active: ["Premium", "Sale"])

        XCTAssertTrue(TNSubscriptionCore.cachedIsPremium)
        XCTAssertEqual(TNSubscriptionCore.cachedActiveEntitlements, ["Premium", "Sale"])

        TNEntitlementSnapshot.shared.update(isPremium: false, active: [])

        XCTAssertFalse(TNSubscriptionCore.cachedIsPremium)
        XCTAssertTrue(TNSubscriptionCore.cachedActiveEntitlements.isEmpty)
    }

    func testConcurrentAccessDoesNotRace() {
        // The whole point of the snapshot is being readable off the main actor.
        // Run under the thread sanitiser to make this test meaningful.
        let iterations = 500
        let done = expectation(description: "concurrent access")
        done.expectedFulfillmentCount = iterations * 2

        for i in 0..<iterations {
            DispatchQueue.global().async {
                TNEntitlementSnapshot.shared.update(isPremium: i.isMultiple(of: 2), active: ["E\(i)"])
                done.fulfill()
            }
            DispatchQueue.global().async {
                _ = TNSubscriptionCore.cachedIsPremium
                _ = TNSubscriptionCore.cachedActiveEntitlements
                done.fulfill()
            }
        }

        wait(for: [done], timeout: 10)
    }
}

// MARK: - Entitlement Info

final class TNEntitlementInfosTests: XCTestCase {

    func testActiveFiltersOutInactiveEntries() {
        // TNEntitlementInfo needs a real Transaction, which cannot be constructed here,
        // so this exercises the collection with an empty set — the degenerate case that
        // paywall code hits on a cold, offline launch.
        let infos = TNEntitlementInfos()

        XCTAssertTrue(infos.all.isEmpty)
        XCTAssertTrue(infos.active.isEmpty)
        XCTAssertTrue(infos.activeIdentifiers.isEmpty)
        XCTAssertNil(infos["Premium"])
    }

    func testEmptyCustomerInfoHasNoActiveEntitlement() {
        let info = TNCustomerInfo()

        XCTAssertFalse(info.hasActiveEntitlement)
        XCTAssertTrue(info.activeSubscriptions.isEmpty)
        XCTAssertNil(info.latestExpirationDate)
        XCTAssertNotNil(info.managementURL)
    }
}

// MARK: - Offer Signature

final class TNPromotionalOfferSignatureTests: XCTestCase {

    func testBase64InitParsesAValidPayload() {
        let nonce = UUID()
        let signature = Data([0x01, 0x02, 0x03])

        let parsed = TNPromotionalOfferSignature(
            keyID: "ABC123",
            nonce: nonce.uuidString,
            timestamp: 1_700_000_000_000,
            base64Signature: signature.base64EncodedString()
        )

        XCTAssertEqual(parsed?.keyID, "ABC123")
        XCTAssertEqual(parsed?.nonce, nonce)
        XCTAssertEqual(parsed?.signature, signature)
    }

    func testBase64InitRejectsAMalformedNonce() {
        let parsed = TNPromotionalOfferSignature(
            keyID: "ABC123",
            nonce: "not-a-uuid",
            timestamp: 1_700_000_000_000,
            base64Signature: Data([0x01]).base64EncodedString()
        )

        XCTAssertNil(parsed, "A non-UUID nonce must be rejected here rather than by Apple at purchase time.")
    }

    func testBase64InitRejectsMalformedSignatureData() {
        let parsed = TNPromotionalOfferSignature(
            keyID: "ABC123",
            nonce: UUID().uuidString,
            timestamp: 1_700_000_000_000,
            base64Signature: "!!! not base64 !!!"
        )

        XCTAssertNil(parsed)
    }
}

// MARK: - Errors

final class TNPurchaseErrorTests: XCTestCase {

    func testEveryErrorHasAUserFacingMessage() {
        let errors: [TNPurchaseError] = [
            .userCancelled,
            .purchasePending,
            .failedVerification(NSError(domain: "test", code: 1)),
            .promotionalOfferSignerMissing,
            .promotionalOfferSigningFailed(NSError(domain: "test", code: 1)),
            .offerMissingIdentifier,
            .offerNotApplicable(.introductory),
            .unknown,
        ]

        for error in errors {
            let message = error.errorDescription
            XCTAssertNotNil(message, "\(error) would show an empty alert.")
            XCTAssertFalse(message?.isEmpty ?? true)
            // A raw Swift error description leaking into an alert is a bug, not a message.
            XCTAssertFalse(message?.contains("TNPurchaseError") ?? false)
        }
    }

    func testVerificationFailureDoesNotLeakInternalDetailToTheUser() {
        let underlying = NSError(domain: "JWS", code: 42, userInfo: [NSLocalizedDescriptionKey: "certificate chain invalid"])
        let error = TNPurchaseError.failedVerification(underlying)

        XCTAssertFalse(error.errorDescription?.contains("certificate chain") ?? true,
                       "Cryptographic failure detail belongs in the log, not in a user-facing alert.")
    }
}

// MARK: - Identity

final class TNIdentityTests: XCTestCase {

    func testClientIdIsStableAcrossReads() {
        let first = TNIdentity.clientId
        let second = TNIdentity.clientId

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    func testClientIdIsAUUIDSoItCanBeUsedAsAnAppAccountToken() {
        // Apple rejects an appAccountToken that is not a UUID, which would fail the
        // purchase rather than just dropping the token.
        XCTAssertNotNil(UUID(uuidString: TNIdentity.clientId))
        XCTAssertNotNil(TNIdentity.appAccountToken)
    }

    func testIdentityHeadersIncludeUserIdOnlyWhenGiven() {
        let without = TNIdentity.identityHeaders()
        XCTAssertNotNil(without["X-Client-Id"])
        XCTAssertNotNil(without["X-Device-Id"])
        XCTAssertNil(without["X-User-Id"])

        let with = TNIdentity.identityHeaders(userId: "user-7")
        XCTAssertEqual(with["X-User-Id"], "user-7")

        let empty = TNIdentity.identityHeaders(userId: "")
        XCTAssertNil(empty["X-User-Id"], "An empty user ID should be omitted, not sent as a blank header.")
    }

    func testApplyingIdentityHeadersDoesNotMutateTheOriginal() {
        let original = URLRequest(url: URL(string: "https://example.com")!)
        let decorated = original.applyingTNIdentityHeaders()

        XCTAssertNil(original.value(forHTTPHeaderField: "X-Client-Id"))
        XCTAssertEqual(decorated.value(forHTTPHeaderField: "X-Client-Id"), TNIdentity.clientId)
    }
}

// MARK: - Log Level

final class TNLogLevelTests: XCTestCase {

    func testLevelsAreOrderedBySeverity() {
        XCTAssertTrue(TNLogLevel.verbose < .debug)
        XCTAssertTrue(TNLogLevel.debug < .info)
        XCTAssertTrue(TNLogLevel.info < .warn)
        XCTAssertTrue(TNLogLevel.warn < .error)
        XCTAssertTrue(TNLogLevel.error < .none)
    }

    func testHandlerReceivesOnlyMessagesAtOrAboveTheThreshold() {
        let previousLevel = TNLog.level
        let previousHandler = TNLog.handler
        defer {
            TNLog.level = previousLevel
            TNLog.handler = previousHandler
        }

        var captured: [(TNLogLevel, String)] = []
        TNLog.handler = { captured.append(($0, $1)) }
        TNLog.level = .warn

        TNLog.verbose("v")
        TNLog.debug("d")
        TNLog.info("i")
        TNLog.warn("w")
        TNLog.error("e")

        XCTAssertEqual(captured.map(\.1), ["w", "e"])
    }

    func testNoneSilencesEverything() {
        let previousLevel = TNLog.level
        let previousHandler = TNLog.handler
        defer {
            TNLog.level = previousLevel
            TNLog.handler = previousHandler
        }

        var count = 0
        TNLog.handler = { _, _ in count += 1 }
        TNLog.level = .none

        TNLog.error("this must not be emitted")

        XCTAssertEqual(count, 0)
    }

    func testFilteredMessagesAreNeverEvaluated() {
        let previousLevel = TNLog.level
        let previousHandler = TNLog.handler
        defer {
            TNLog.level = previousLevel
            TNLog.handler = previousHandler
        }

        TNLog.handler = { _, _ in }
        TNLog.level = .error

        // String interpolation in a dropped log line must cost nothing: at .verbose this
        // package logs per transaction, and that adds up.
        var evaluated = false
        func expensive() -> String {
            evaluated = true
            return "expensive"
        }
        TNLog.debug(expensive())

        XCTAssertFalse(evaluated)
    }
}
