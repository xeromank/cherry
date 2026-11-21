import CoreGraphics
import Darwin

enum StatusWindowIDs {
    private typealias Connection = @convention(c) () -> Int32
    private typealias WindowCount = @convention(c) (Int32, Int32, UnsafeMutablePointer<Int32>) -> Int32
    private typealias MenuBarList = @convention(c) (
        Int32, Int32, Int32, UnsafeMutablePointer<CGWindowID>, UnsafeMutablePointer<Int32>
    ) -> Int32

    private struct SkyLight {
        let connection: Connection
        let count: WindowCount
        let menuBarList: MenuBarList
    }

    // Keep the loaded framework alive for the lifetime of these optional function pointers.
    private static let skyLight: SkyLight? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let connection = dlsym(library, "CGSMainConnectionID"),
              let count = dlsym(library, "CGSGetWindowCount"),
              let list = dlsym(library, "CGSGetProcessMenuBarWindowList") else {
            dlclose(library)
            return nil
        }
        return SkyLight(
            connection: unsafeBitCast(connection, to: Connection.self),
            count: unsafeBitCast(count, to: WindowCount.self),
            menuBarList: unsafeBitCast(list, to: MenuBarList.self)
        )
    }()

    static func menuBarItems() -> Set<CGWindowID>? {
        guard let skyLight else { return nil }
        let connection = skyLight.connection()
        var capacity: Int32 = 0
        // The count of all windows bounds the number of menu bar windows.
        guard connection != 0, skyLight.count(connection, 0, &capacity) == 0,
              (0...100_000).contains(capacity) else { return nil }
        guard capacity > 0 else { return [] }

        var ids = [CGWindowID](repeating: kCGNullWindowID, count: Int(capacity))
        var count: Int32 = 0
        guard skyLight.menuBarList(connection, 0, capacity, &ids, &count) == 0,
              (0...capacity).contains(count) else { return nil }
        var result = Set(ids.prefix(Int(count)))
        result.remove(kCGNullWindowID)
        return result
    }
}
