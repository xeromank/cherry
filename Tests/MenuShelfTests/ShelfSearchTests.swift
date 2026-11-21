import XCTest
@testable import MenuShelf

final class ShelfSearchTests: XCTestCase {
    func testMatchesTermsAcrossItemAndApplicationNames() {
        XCTAssertTrue(ShelfSearch.matches("  카메라   café ", in: ["카메라 켜기", "Cafe Tools"]))
        XCTAssertFalse(ShelfSearch.matches("카메라 꺼짐", in: ["카메라 켜기", "Cafe Tools"]))
    }

    func testWhitespaceLeavesAllItemsEligible() {
        XCTAssertTrue(ShelfSearch.matches(" \t\n", in: ["Wi-Fi", "제어 센터"]))
    }
}
