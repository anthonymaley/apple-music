import XCTest
@testable import music

final class ArtworkStoreTests: XCTestCase {

    // MARK: resolveURL — both live-probed URL shapes

    func testResolveURLSubstitutesTemplate() {
        let t = "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/df/db/61/x/18UMGIM31076.rgb.jpg/{w}x{h}bb.jpg"
        XCTAssertEqual(
            ArtworkStore.resolveURL(t, width: 300, height: 300),
            "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/df/db/61/x/18UMGIM31076.rgb.jpg/300x300bb.jpg")
    }

    func testResolveURLPassesThroughPreSignedURL() {
        let t = "https://store-033.blobstore.apple.com/sq-mq-us/image?X-Amz-Expires=86400&X-Amz-Signature=abc"
        XCTAssertEqual(ArtworkStore.resolveURL(t, width: 300, height: 300), t)
    }

    // MARK: cacheKey — filesystem-safe, distinct-enough

    func testCacheKeySanitizesNonAlphanumerics() {
        XCTAssertEqual(ArtworkStore.cacheKey("p.abc123XY/z"), "p_abc123XY_z")
    }

    func testCacheKeyKeepsAlphanumerics() {
        XCTAssertEqual(ArtworkStore.cacheKey("l4bC9"), "l4bC9")
    }
}
