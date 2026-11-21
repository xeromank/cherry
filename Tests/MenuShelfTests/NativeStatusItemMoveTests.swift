import CoreGraphics
import XCTest
@testable import MenuShelf

final class NativeStatusItemMoveTests: XCTestCase {
    func testWindowMatchUsesTheCenterOfTheOffscreenItem() {
        let accessibilityFrame = CGRect(x: -2788, y: 7.5, width: 24, height: 24)
        let nativeFrame = CGRect(x: -2795, y: 0, width: 38, height: 39)
        let host: pid_t = 200
        let source: pid_t = 300
        let matches: [NativeStatusItemMove.Window] = [
            .init(id: 4, owner: 400, frame: nativeFrame),
            .init(id: 5, owner: host, frame: nativeFrame),
            .init(id: 6, owner: host, frame: nativeFrame.offsetBy(dx: 10, dy: 0)),
        ]

        XCTAssertEqual(NativeStatusItemMove.findWindow(at: accessibilityFrame, owner: source, hostedBy: host, in: matches)?.id, 5)
        let ambiguous = matches + [.init(id: 7, owner: source, frame: nativeFrame)]
        XCTAssertNil(NativeStatusItemMove.findWindow(at: accessibilityFrame, owner: source, hostedBy: host, in: ambiguous))
    }

    func testPinIsVerifiedPastTheDividerOnTheSameMenuBar() {
        let divider = CGRect(x: -2260, y: 0, width: 3650, height: 39)
        let item = CGRect(x: 1395, y: 7.5, width: 24, height: 24)

        XCTAssertTrue(StatusItemPlacement.visible.matches(item, divider: divider))
        XCTAssertFalse(StatusItemPlacement.visible.matches(item.offsetBy(dx: -55, dy: 0), divider: divider))
        XCTAssertFalse(StatusItemPlacement.visible.matches(item.offsetBy(dx: 0, dy: 1100), divider: divider))
    }

    func testDividerCanSwapOnlyWithAnAdjacentItem() {
        let divider = CGRect(x: 1309, y: 0, width: 17, height: 39)
        let item = CGRect(x: 1279, y: 0, width: 30, height: 39)

        XCTAssertTrue(StatusItemPlacement.hidden.matches(item, divider: divider))
        XCTAssertTrue(StatusItemPlacement.visible.isAdjacent(item, to: divider))
        XCTAssertFalse(StatusItemPlacement.visible.isAdjacent(item.offsetBy(dx: -30, dy: 0), to: divider))
        XCTAssertTrue(StatusItemPlacement.hidden.isAdjacent(item.offsetBy(dx: 47, dy: 0), to: divider))
        XCTAssertFalse(StatusItemPlacement.hidden.isAdjacent(item.offsetBy(dx: 47, dy: 40), to: divider))
    }
}
