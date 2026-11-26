import Foundation
import XCTest
@testable import ToolulaCleaner

/// 完整流程: 扫描 → 勾选 → 清理 → 撤销, 走的是界面按钮调用的同一套代码 (CleanerStore)
@MainActor
final class StoreFlowTests: FakeHomeTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults.standard.removeObject(forKey: "history")
        UserDefaults.standard.removeObject(forKey: "deleteDirectly")
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "history")
        try super.tearDownWithError()
    }

    /// 等异步任务完成
    func wait(_ what: String, timeout: TimeInterval = 10, _ cond: @escaping () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !cond() {
            if Date() > end { XCTFail("超时: \(what)"); return }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    func testScanCleanUndo() async throws {
        let a = try file("Library/Caches/com.example.one/a.bin", bytes: 30_000)
        let b = try file("Library/Caches/com.example.two/b.bin", bytes: 60_000)
        let keep = try file("Library/Caches/com.example.keep/k.bin", bytes: 10_000)
        let store = CleanerStore()

        store.scan([.appCaches])
        try await wait("扫描") { store.state(.appCaches).scanned }
        XCTAssertEqual(store.state(.appCaches).items.count, 3)
        XCTAssertEqual(store.state(.appCaches).selectedCount, 3)

        // 取消勾选一项, 只清理另外两项
        let keepID = keep.deletingLastPathComponent().path
        store.toggle(.appCaches, keepID)
        XCTAssertEqual(store.state(.appCaches).selectedCount, 2)

        store.requestClean([.appCaches])
        XCTAssertEqual(store.pendingClean, [.appCaches], "先弹确认框")
        XCTAssertTrue(store.confirmText([.appCaches]).contains("2"))
        store.clean([.appCaches])
        try await wait("清理") { !store.cleaning }

        XCTAssertFalse(fm.fileExists(atPath: a.path))
        XCTAssertFalse(fm.fileExists(atPath: b.path))
        XCTAssertTrue(fm.fileExists(atPath: keep.path), "没勾选的不动")
        XCTAssertEqual(store.state(.appCaches).items.map(\.id), [keepID])
        let rec = try XCTUnwrap(store.history.first)
        XCTAssertEqual(rec.count, 2)
        XCTAssertEqual(rec.moves.count, 2)
        trashed += rec.moves.map { URL(fileURLWithPath: $0.to) }
        XCTAssertTrue(rec.canUndo)
        XCTAssertEqual(store.toast?.undoID, rec.id, "提示里有「撤销」")

        // 撤销
        var finished = false
        store.undo(rec.id) { finished = true }
        try await wait("撤销") { finished }
        XCTAssertTrue(fm.fileExists(atPath: a.path))
        XCTAssertTrue(fm.fileExists(atPath: b.path))
        XCTAssertTrue(store.history.first?.undone == true)
        XCTAssertFalse(store.history.first?.canUndo ?? true)

        // 记录保存下来了, 重新打开也在
        let reopened = CleanerStore()
        XCTAssertEqual(reopened.history.first?.id, rec.id)
        XCTAssertEqual(reopened.history.first?.undone, true)
    }

    func testFailuresAreReported() async throws {
        let f = try file("Library/Caches/com.example.locked/a.bin")
        let store = CleanerStore()
        store.scan([.appCaches])
        try await wait("扫描") { store.state(.appCaches).scanned }
        // 把文件夹设成不可写 → 移不动
        let dir = f.deletingLastPathComponent().deletingLastPathComponent()
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        store.clean([.appCaches])
        try await wait("清理") { !store.cleaning }
        XCTAssertEqual(store.failures.count, 1)
        XCTAssertTrue(store.failures[0].needsAccess)
        XCTAssertEqual(store.toast?.hasFailures, true, "提示里有「查看详情」")
        XCTAssertTrue(fm.fileExists(atPath: f.path))
    }

    func testUserFilesAlwaysGoToTrashEvenWithDeleteDirectly() {
        let store = CleanerStore()
        store.deleteDirectly = true
        XCTAssertTrue(store.permanent(.appCaches))
        XCTAssertFalse(store.permanent(.downloads), "下载永远只移到废纸篓")
        XCTAssertFalse(store.permanent(.largeFiles), "大文件永远只移到废纸篓")
        XCTAssertTrue(store.permanent(.trash))
        store.deleteDirectly = false
    }
}
