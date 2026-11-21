import AppKit
import Carbon
import XCTest
@testable import MenuShelf

final class MenuShelfStartupTests: XCTestCase {
    func testLoginEventStartsQuietlyAndExplicitOpenShowsThePanel() {
        let open = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )

        XCTAssertTrue(MenuShelfStartup.opensPanel(event: open, loginEnabled: true))
        open.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        XCTAssertFalse(MenuShelfStartup.opensPanel(event: open, loginEnabled: true))
        XCTAssertFalse(MenuShelfStartup.opensPanel(event: open, loginEnabled: false))
    }

    func testLaunchWithoutAnEventIsQuietOnlyWhenRegisteredForLogin() {
        XCTAssertTrue(MenuShelfStartup.opensPanel(event: nil, loginEnabled: false))
        XCTAssertFalse(MenuShelfStartup.opensPanel(event: nil, loginEnabled: true))
    }
}
