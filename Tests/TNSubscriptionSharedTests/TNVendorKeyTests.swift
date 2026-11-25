import XCTest
@testable import TNSubscriptionShared

/// The one key table, checked for every engine — the rules each engine used to keep separately.
/// (Bảng key duy nhất, được kiểm tra cho mọi engine — các quy tắc mà trước đây mỗi engine tự giữ.)
final class TNVendorKeyTests: XCTestCase {

    private let adaptyKey = "public_live_" + String(repeating: "a", count: 29)

    // MARK: Recognition

    func testPrefixesAreRecognised() {
        XCTAssertEqual(TNVendorKey.vendor(ofKey: "appl_x"), .revenueCat)
        XCTAssertEqual(TNVendorKey.vendor(ofKey: "test_x"), .revenueCat)
        XCTAssertEqual(TNVendorKey.vendor(ofKey: "goog_x"), .revenueCat)
        XCTAssertEqual(TNVendorKey.vendor(ofKey: "amzn_x"), .revenueCat)
        XCTAssertEqual(TNVendorKey.vendor(ofKey: "public_live_x"), .adapty)
        XCTAssertEqual(TNVendorKey.vendor(ofKey: "secret_live_x"), .adapty)
        XCTAssertNil(TNVendorKey.vendor(ofKey: "PV77YHL7qnGvsdmpTs7gimsxUvY-Znl2"), "Qonversion keys have no prefix to recognise.")
        XCTAssertEqual(TNVendorKey.vendor(ofKey: "  appl_x\n"), .revenueCat, "A pasted newline must not hide the vendor.")
    }

    // MARK: Every engine catches every other vendor's key

    func testEachVendorEngineRefusesTheOthersKeys() {
        XCTAssertEqual(TNVendorKey.check("public_live_abc", for: .revenueCat), .otherVendor(.adapty),
                       "The RevenueCat engine used to pass an Adapty key straight to RevenueCat.")
        XCTAssertEqual(TNVendorKey.check("appl_abc", for: .adapty), .otherVendor(.revenueCat))
        XCTAssertEqual(TNVendorKey.check("appl_abc", for: .qonversion), .otherVendor(.revenueCat))
        XCTAssertEqual(TNVendorKey.check("public_live_abc", for: .qonversion), .otherVendor(.adapty))
    }

    func testCoreNeedsNoKey() {
        XCTAssertNil(TNVendorKey.check("", for: .storeKit))
        XCTAssertNil(TNVendorKey.check("appl_abc", for: .storeKit), "Core ignores the key; ignoredSettings reports it.")
    }

    // MARK: Engine-specific formats

    func testRevenueCat() {
        XCTAssertNil(TNVendorKey.check("appl_abc", for: .revenueCat))
        XCTAssertNil(TNVendorKey.check("test_abc", for: .revenueCat))
        XCTAssertEqual(TNVendorKey.check("goog_abc", for: .revenueCat), .unexpectedFormat, "An Android key in an iOS app.")
        XCTAssertEqual(TNVendorKey.check("LegacyKeyWithoutPrefix123", for: .revenueCat), .unexpectedFormat)
        XCTAssertEqual(TNVendorKey.check("", for: .revenueCat), .empty)
    }

    func testAdapty() {
        XCTAssertEqual(adaptyKey.count, TNVendorKey.adaptyMinimumLength)
        XCTAssertNil(TNVendorKey.check(adaptyKey, for: .adapty))
        XCTAssertNil(TNVendorKey.check("  \(adaptyKey)\n", for: .adapty))
        XCTAssertEqual(TNVendorKey.check("public_live_short", for: .adapty), .tooShort(minimum: 41))
        XCTAssertEqual(TNVendorKey.check("secret_live_" + String(repeating: "a", count: 40), for: .adapty), .secretKey)
        XCTAssertEqual(TNVendorKey.check(String(repeating: "x", count: 50), for: .adapty), .unexpectedFormat)
        XCTAssertEqual(TNVendorKey.check("", for: .adapty), .empty)
    }

    func testQonversion() {
        XCTAssertNil(TNVendorKey.check("PV77YHL7qnGvsdmpTs7gimsxUvY-Znl2", for: .qonversion))
        XCTAssertEqual(TNVendorKey.check("", for: .qonversion), .empty)
    }

    // MARK: Policy

    func testOnlyAnUnfamiliarRevenueCatFormatIsAllowedThrough() {
        // Legacy RevenueCat keys have no prefix and still work; refusing them could break a live app.
        XCTAssertFalse(TNKeyProblem.unexpectedFormat.blocksLaunch(for: .revenueCat))
        XCTAssertTrue(TNKeyProblem.otherVendor(.adapty).blocksLaunch(for: .revenueCat))
        XCTAssertTrue(TNKeyProblem.empty.blocksLaunch(for: .revenueCat))
        for problem in [TNKeyProblem.empty, .otherVendor(.revenueCat), .secretKey, .unexpectedFormat, .tooShort(minimum: 41)] {
            XCTAssertTrue(problem.blocksLaunch(for: .adapty), "Adapty asserts on a bad key, so everything must block: \(problem)")
            XCTAssertTrue(problem.blocksLaunch(for: .qonversion))
        }
    }

    func testEveryMessageSaysWhatToDo() {
        let problems: [TNKeyProblem] = [.empty, .otherVendor(.adapty), .secretKey, .unexpectedFormat, .tooShort(minimum: 41)]
        for engine in [TNEngineKind.revenueCat, .adapty, .qonversion] {
            for problem in problems {
                XCTAssertFalse(problem.explanation(for: engine).isEmpty)
            }
        }
        XCTAssertTrue(TNKeyProblem.secretKey.explanation(for: .adapty).contains("rotate"),
                      "A leaked secret key needs rotating, not just replacing in code.")
        XCTAssertTrue(TNKeyProblem.otherVendor(.revenueCat).explanation(for: .qonversion).contains("RevenueCat"))
    }
}
