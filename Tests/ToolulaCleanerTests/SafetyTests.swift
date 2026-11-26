import Foundation
import XCTest
@testable import ToolulaCleaner

/// 安全规则: 什么能删、什么绝对不能删
final class SafetyTests: FakeHomeTestCase {

    func allowed(_ rel: String, _ kind: CategoryKind) -> Bool {
        Safety.allowed(home.appendingPathComponent(rel), kind: kind)
    }

    func testCleaningRoots() {
        XCTAssertFalse(allowed("Library/Caches", .appCaches), "缓存文件夹本身不能删")
        XCTAssertTrue(allowed("Library/Caches/com.example.app", .appCaches))
        XCTAssertTrue(allowed("Library/Logs/Foo", .logs))
        XCTAssertFalse(allowed("Library/Preferences/com.example.app.plist", .appCaches))
        XCTAssertFalse(allowed("Library/Keychains/login.keychain-db", .appCaches))
        XCTAssertFalse(allowed("Library/Caches/../Keychains/x", .appCaches), "不能用 .. 绕出去")
        XCTAssertFalse(allowed("Documents/report.pages", .appCaches))
        XCTAssertFalse(allowed(".Trash", .trash))
        XCTAssertTrue(allowed(".Trash/old.zip", .trash))
        XCTAssertTrue(allowed("Downloads/old.dmg", .downloads))
        XCTAssertFalse(allowed("Downloads", .downloads))
    }

    func testDeveloperWholeCacheFolders() {
        XCTAssertTrue(allowed(".npm/_cacache", .developer), "npm 缓存文件夹整个可以删")
        XCTAssertFalse(allowed(".npm", .developer), "但 ~/.npm 本身不行")
        XCTAssertTrue(allowed("Library/Developer/Xcode/DerivedData/App-abc", .developer))
        XCTAssertFalse(allowed("Library/Developer", .developer))
    }

    func testLargeFilesRules() {
        XCTAssertTrue(allowed("Movies/big.mov", .largeFiles))
        XCTAssertFalse(allowed("Movies", .largeFiles), "个人文件夹第一层的文件夹不能删")
        XCTAssertFalse(allowed("Library/Mail/x.emlx", .largeFiles))
        XCTAssertFalse(allowed("Toolula/models/m.safetensors", .largeFiles), "Toolula AI 的数据和模型不能删")
    }

    func testRemoveRefusesAndDoesNotTouchFile() throws {
        let f = try file("Documents/keep.txt")
        XCTAssertThrowsError(try Safety.remove(f, kind: .appCaches, permanent: true))
        XCTAssertTrue(fm.fileExists(atPath: f.path))
    }

    func testRemoveToTrashReturnsTrashLocation() throws {
        let f = try file("Library/Caches/com.example.app/data.bin", bytes: 5000)
        let item = f.deletingLastPathComponent()
        let to = try XCTUnwrap(Safety.remove(item, kind: .appCaches, permanent: false))
        trashed.append(to)
        XCTAssertFalse(fm.fileExists(atPath: item.path))
        XCTAssertTrue(fm.fileExists(atPath: to.appendingPathComponent("data.bin").path))
        XCTAssertTrue(to.path.contains("/.Trash/"))
    }

    func testPermanentRemove() throws {
        let f = try file("Library/Logs/Foo/a.log")
        XCTAssertNil(try Safety.remove(f.deletingLastPathComponent(), kind: .logs, permanent: true))
        XCTAssertFalse(fm.fileExists(atPath: f.path))
    }

    func testErrorReasons() {
        let perm = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                           userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        XCTAssertTrue(Safety.isPermission(perm))
        XCTAssertTrue(Safety.reason(perm).contains("权限"))
        let missing = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        XCTAssertFalse(Safety.isPermission(missing))
        XCTAssertEqual(Safety.reason(missing), "文件已经不存在了")
        let busy = NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY))
        XCTAssertEqual(Safety.reason(busy), "正在被使用")
    }
}
