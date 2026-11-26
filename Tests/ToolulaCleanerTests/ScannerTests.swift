import Foundation
import XCTest
@testable import ToolulaCleaner

/// 每个清理类别在假个人文件夹里的扫描结果
final class ScannerTests: FakeHomeTestCase {

    func names(_ out: ScanOutput) -> [String] { out.items.map { $0.url.lastPathComponent }.sorted() }

    func testAppCachesExcludesBrowserAndDeveloperFolders() throws {
        try file("Library/Caches/com.example.notes/c.bin", bytes: 20_000)
        try file("Library/Caches/com.example.running/c.bin", bytes: 20_000)
        try file("Library/Caches/Google/Chrome/c.bin")          // 属于「浏览器」
        try file("Library/Caches/Homebrew/x.tar.gz")             // 属于「开发者」
        try dir("Library/Caches/com.example.empty")              // 空的不列
        let out = Scanner.scan(.appCaches, ScanContext(running: ["com.example.running"], largeThreshold: 0, downloadsDays: 90))
        XCTAssertEqual(names(out), ["com.example.notes", "com.example.running"])
        let running = try XCTUnwrap(out.items.first { $0.url.lastPathComponent == "com.example.running" })
        XCTAssertFalse(running.selected, "正在运行的应用默认不勾选")
        XCTAssertNotNil(running.note)
        XCTAssertEqual(out.items.first { $0.url.lastPathComponent == "com.example.notes" }?.selected, true)
        XCTAssertEqual(out.items.map(\.size), out.items.map(\.size).sorted(by: >), "按大小排序")
    }

    func testDeveloper() throws {
        try file("Library/Developer/Xcode/DerivedData/MyApp-abcdef/Build/x.o", bytes: 30_000)
        try file("Library/Developer/Xcode/Archives/2026-01-01/a.xcarchive/x", bytes: 30_000)
        try file(".npm/_cacache/index/x", bytes: 30_000)
        let out = Scanner.scan(.developer, ctx)
        let derived = try XCTUnwrap(out.items.first { $0.url.lastPathComponent == "MyApp-abcdef" })
        XCTAssertTrue(derived.name.contains("MyApp"))
        XCTAssertTrue(derived.selected)
        XCTAssertEqual(out.items.first { $0.url.lastPathComponent == "Archives" }?.selected, false, "归档默认不勾选")
        XCTAssertTrue(out.items.contains { $0.url.path.hasSuffix(".npm/_cacache") })
    }

    func testBrowserRunningIsDeselected() throws {
        try file("Library/Caches/com.apple.Safari/c.bin")
        try file("Library/Caches/Google/Chrome/c.bin")
        let out = Scanner.scan(.browser, ScanContext(running: ["com.google.Chrome"], largeThreshold: 0, downloadsDays: 90))
        XCTAssertEqual(out.items.count, 2)
        XCTAssertEqual(out.items.first { $0.name == "Google Chrome" }?.selected, false)
        XCTAssertEqual(out.items.first { $0.name == "Safari" }?.selected, true)
    }

    func testDownloadsOnlyOldFilesAndUnselected() throws {
        try file("Downloads/old.dmg", bytes: 5000, modified: Date().addingTimeInterval(-200 * 86400))
        try file("Downloads/new.dmg", bytes: 5000)
        let out = Scanner.scan(.downloads, ctx)
        XCTAssertEqual(names(out), ["old.dmg"])
        XCTAssertFalse(out.items.first?.selected ?? true, "你自己的文件默认不勾选")
    }

    func testLargeFilesSkipsProtectedPlaces() throws {
        try file("Movies/big.mov", bytes: 2_000_000)
        try file("Movies/small.mov", bytes: 1000)
        try file("Library/big.bin", bytes: 2_000_000)
        try file("Toolula/models/m.safetensors", bytes: 2_000_000)
        try file(".cache/big.bin", bytes: 2_000_000)
        try file("Pictures/Photos Library.photoslibrary/originals/big.heic", bytes: 2_000_000)
        try file("Projects/model.safetensors", bytes: 2_000_000)
        let out = Scanner.scan(.largeFiles, ctx)
        XCTAssertEqual(names(out), ["big.mov", "model.safetensors"])
        XCTAssertTrue(out.items.allSatisfy { !$0.selected })
        XCTAssertNotNil(out.items.first { $0.url.lastPathComponent == "model.safetensors" }?.note, "AI 模型要标出来")
    }

    func testLogsAndTrash() throws {
        try file("Library/Logs/AppA/a.log")
        try file("Library/Logs/AppB/b.log")
        XCTAssertEqual(names(Scanner.scan(.logs, ctx)), ["AppA", "AppB"])
        try file(".Trash/thing.zip")
        try file(".Trash/.DS_Store")
        XCTAssertEqual(names(Scanner.scan(.trash, ctx)), ["thing.zip"])
    }

    func testBytesFormatting() {
        XCTAssertEqual(Scanner.bytes(512), "512 B")
        XCTAssertTrue(Scanner.bytes(2_790_000_000).hasSuffix("GB"))
        XCTAssertTrue(Scanner.bytes(45_000_000).hasSuffix("MB"))
    }
}
