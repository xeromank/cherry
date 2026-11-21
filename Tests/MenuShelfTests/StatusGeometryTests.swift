import CoreGraphics
import XCTest
@testable import MenuShelf

final class StatusGeometryTests: XCTestCase {
    private let notchedDisplay = StatusBarGeometry(
        displayFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
        rightBand: CGRect(x: 1010, y: 0, width: 790, height: 38)
    )

    func testOnlyFullItemsToTheRightOfTheNotchAreVisible() {
        XCTAssertFalse(notchedDisplay.isHidden(statusFrame(x: 1010), menuEndX: nil))
        XCTAssertTrue(notchedDisplay.isHidden(statusFrame(x: 1009), menuEndX: nil))
        XCTAssertTrue(notchedDisplay.isHidden(statusFrame(x: 760), menuEndX: nil))
        XCTAssertTrue(notchedDisplay.isHidden(statusFrame(x: 0), menuEndX: nil))
    }

    func testItemsOutsideTheMenuBarAreHidden() {
        XCTAssertTrue(notchedDisplay.isHidden(statusFrame(x: -500), menuEndX: nil))
        XCTAssertTrue(notchedDisplay.isHidden(statusFrame(x: 1790), menuEndX: nil))
        XCTAssertTrue(notchedDisplay.isHidden(statusFrame(x: 1200, y: 90), menuEndX: nil))
        XCTAssertFalse(notchedDisplay.isHidden(nil, menuEndX: nil))
    }

    func testFrontAppMenusCanReduceStatusItemSpace() {
        XCTAssertFalse(notchedDisplay.isHidden(statusFrame(x: 1070), menuEndX: 1070))
        XCTAssertTrue(notchedDisplay.isHidden(statusFrame(x: 1070), menuEndX: 1071))
        XCTAssertTrue(notchedDisplay.isHidden(statusFrame(x: 1000), menuEndX: 760))
    }

    func testCoordinatesRespectADisplayAboveAndLeftOfThePrimaryDisplay() {
        let display = CGRect(x: -1920, y: 1169, width: 1920, height: 1080)
        let rightBand = CGRect(x: -1920, y: 2225, width: 1920, height: 24)
        let geometry = StatusBarGeometry(
            displayFrame: StatusBarGeometry.accessibilityFrame(display, desktopTop: 1169),
            rightBand: StatusBarGeometry.accessibilityFrame(rightBand, desktopTop: 1169)
        )

        XCTAssertEqual(geometry.rightBand, CGRect(x: -1920, y: -1080, width: 1920, height: 24))
        XCTAssertFalse(geometry.isHidden(statusFrame(x: -50, y: -1080), menuEndX: -100))
        XCTAssertTrue(geometry.isHidden(statusFrame(x: -110, y: -1080), menuEndX: -100))

        let displays = [notchedDisplay, geometry]
        let menus = [CGRect(x: -1920, y: -1080, width: 1820, height: 24), statusFrame(x: 0)]
        XCTAssertFalse(StatusBarGeometry.isHidden(statusFrame(x: -50, y: -1080), on: displays, appMenus: menus))
        XCTAssertTrue(StatusBarGeometry.isHidden(statusFrame(x: -110, y: -1080), on: displays, appMenus: menus))
        XCTAssertTrue(StatusBarGeometry.isHidden(statusFrame(x: -30, y: -100), on: displays, appMenus: menus))
    }

    private func statusFrame(x: CGFloat, y: CGFloat = 0) -> CGRect {
        CGRect(x: x, y: y, width: 24, height: 22)
    }
}
