import XCTest
@testable import Atlasbound

final class SupabaseAuthCallbackTests: XCTestCase {
    func testAcceptsAtlasboundAuthCallback() {
        let url = URL(string: "atlasbound://auth/callback?code=one-time-code")!

        XCTAssertTrue(SupabaseConfiguration.isAuthCallback(url))
    }

    func testRejectsSideStoreLaunchURL() {
        let url = URL(string: "sidestore-com.atlasbound.app://")!

        XCTAssertFalse(SupabaseConfiguration.isAuthCallback(url))
    }

    func testRejectsOtherAtlasboundPaths() {
        let url = URL(string: "atlasbound://auth/other?code=one-time-code")!

        XCTAssertFalse(SupabaseConfiguration.isAuthCallback(url))
    }
}
