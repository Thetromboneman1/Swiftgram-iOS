import XCTest
@testable import SGPushEnvironment

final class SGPushEnvironmentTests: XCTestCase {
    func testDevelopmentSigningUsesSandboxAPNs() {
        XCTAssertTrue(SGPushEnvironment.isSandbox(apsEnvironment: "development", fallbackIsDebug: false))
    }

    func testProductionSigningUsesProductionAPNs() {
        XCTAssertFalse(SGPushEnvironment.isSandbox(apsEnvironment: "production", fallbackIsDebug: true))
    }

    func testEnvironmentIsNormalized() {
        XCTAssertTrue(SGPushEnvironment.isSandbox(apsEnvironment: " DEVELOPMENT\n", fallbackIsDebug: false))
        XCTAssertFalse(SGPushEnvironment.isSandbox(apsEnvironment: " Production ", fallbackIsDebug: true))
    }

    func testMissingOrUnknownEnvironmentUsesBuildModeFallback() {
        XCTAssertTrue(SGPushEnvironment.isSandbox(apsEnvironment: nil, fallbackIsDebug: true))
        XCTAssertFalse(SGPushEnvironment.isSandbox(apsEnvironment: "unknown", fallbackIsDebug: false))
    }
}
