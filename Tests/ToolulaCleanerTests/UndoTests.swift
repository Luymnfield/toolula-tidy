import Foundation
import XCTest
@testable import ToolulaCleaner

/// 撤销: 移到废纸篓的东西能原样放回去; 放不回去时说明原因
final class UndoTests: FakeHomeTestCase {

    func testRestoreBringsItemsBack() throws {
        let f = try file("Library/Caches/com.example.undo/data.bin", bytes: 7777)
        let item = f.deletingLastPathComponent()
        let to = try XCTUnwrap(Safety.remove(item, kind: .appCaches, permanent: false))
        trashed.append(to)
        let r = CleanerStore.restore([Move(from: item.path, to: to.path)])
        XCTAssertEqual(r.restored, 1)
        XCTAssertTrue(r.failures.isEmpty)
        XCTAssertEqual(try Data(contentsOf: f).count, 7777, "内容原样放回")
        XCTAssertFalse(fm.fileExists(atPath: to.path))
    }

    func testRestoreSkipsWhenOriginalWasRecreated() throws {
        let f = try file("Library/Caches/com.example.regen/data.bin")
        let item = f.deletingLastPathComponent()
        let to = try XCTUnwrap(Safety.remove(item, kind: .appCaches, permanent: false))
        trashed.append(to)
        try file("Library/Caches/com.example.regen/new.bin")   // 应用已经重新生成了缓存
        let r = CleanerStore.restore([Move(from: item.path, to: to.path)])
        XCTAssertEqual(r.restored, 0)
        XCTAssertEqual(r.failures.count, 1)
        XCTAssertTrue(r.failures[0].reason.contains("同名"))
        XCTAssertTrue(fm.fileExists(atPath: to.path), "废纸篓里的不动")
    }

    func testRestoreReportsItemsNoLongerInTrash() {
        let r = CleanerStore.restore([Move(from: home.appendingPathComponent("Library/Caches/x").path,
                                           to: home.appendingPathComponent(".Trash/gone").path)])
        XCTAssertEqual(r.restored, 0)
        XCTAssertEqual(r.failures.first?.reason, "已经不在废纸篓里了")
    }

    func testRestoreRecreatesMissingParentFolder() throws {
        let f = try file("Library/Logs/AppX/sub/a.log", bytes: 300)
        let item = f.deletingLastPathComponent()
        let to = try XCTUnwrap(Safety.remove(item, kind: .logs, permanent: false))
        trashed.append(to)
        try fm.removeItem(at: home.appendingPathComponent("Library/Logs/AppX"))    // 上一层文件夹也没了
        XCTAssertEqual(CleanerStore.restore([Move(from: item.path, to: to.path)]).restored, 1)
        XCTAssertTrue(fm.fileExists(atPath: f.path))
    }

    func testUninstallUndoPutsAppBack() throws {
        let a = try app("Applications/Back.app", bundleID: "com.example.back")
        let pref = try file("Library/Preferences/com.example.back.plist")
        let moves = try [a, pref].map { u -> Move in
            let to = try XCTUnwrap(Uninstaller.trash(u, isApp: u.pathExtension == "app"))
            trashed.append(to)
            return Move(from: u.path, to: to.path)
        }
        let r = CleanerStore.restore(moves)
        XCTAssertEqual(r.restored, 2)
        XCTAssertTrue(fm.fileExists(atPath: a.appendingPathComponent("Contents/Info.plist").path))
        XCTAssertTrue(fm.fileExists(atPath: pref.path))
    }

    func testOldHistoryWithoutMovesStillLoads() throws {
        let old = #"[{"id":"6F1D8A3C-6B2E-4C11-9A2B-0E2B7C1D9F00","date":786000000,"bytes":1640000000,"count":3,"kinds":["废纸篓"]}]"#
        let recs = try JSONDecoder().decode([CleanRecord].self, from: Data(old.utf8))
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].moves, [])
        XCTAssertFalse(recs[0].undone)
        XCTAssertFalse(recs[0].canUndo, "永久删除的不能撤销")
    }

    func testCanUndo() {
        var r = CleanRecord(date: Date(), bytes: 1, count: 1, kinds: ["x"],
                            moves: [Move(from: "/nope/a", to: home.path)])     // home 存在 → 还能撤销
        XCTAssertTrue(r.canUndo)
        r.undone = true
        XCTAssertFalse(r.canUndo)
    }
}
