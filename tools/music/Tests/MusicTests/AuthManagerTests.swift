import XCTest
@testable import music

final class AuthManagerTests: XCTestCase {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("music-auth-test-\(UUID().uuidString)")
    var configPath: String { dir.appendingPathComponent("config.json").path }

    override func setUp() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    // Absent config is a normal "not configured" state — nil, no throw.
    func testStrictLoadReturnsNilWhenAbsent() throws {
        let config = try AuthManager().loadConfigStrict(path: configPath)
        XCTAssertNil(config)
    }

    // A present-but-malformed config must be distinguishable from "not configured",
    // so the user is told the file is broken rather than "not set up".
    func testStrictLoadThrowsOnCorruptConfig() throws {
        try "not json{".write(toFile: configPath, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AuthManager().loadConfigStrict(path: configPath)) { error in
            guard case AuthError.configCorrupt = error else {
                return XCTFail("expected AuthError.configCorrupt, got \(error)")
            }
        }
    }

    func testStrictLoadReturnsConfigWhenValid() throws {
        let json = #"{"keyId":"K","teamId":"T","keyPath":"~/k.p8","storefront":"us"}"#
        try json.write(toFile: configPath, atomically: true, encoding: .utf8)
        let config = try AuthManager().loadConfigStrict(path: configPath)
        XCTAssertEqual(config?.keyId, "K")
        XCTAssertEqual(config?.storefront, "us")
    }
}
