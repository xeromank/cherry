import XCTest
@testable import MenuShelf

final class StatusItemCatalogTests: XCTestCase {
    @MainActor
    func testExcludesControlCenterWithoutDroppingIndependentSources() async {
        XCTAssertFalse(StatusItemCatalog.shouldScan(bundleIdentifier: "com.apple.controlcenter", activationPolicy: .accessory))
        XCTAssertTrue(StatusItemCatalog.shouldScan(bundleIdentifier: "com.example.menuutility", activationPolicy: .accessory))
        XCTAssertTrue(StatusItemCatalog.shouldScan(bundleIdentifier: "com.apple.systemuiserver", activationPolicy: .prohibited))
    }
}
