import Foundation
import XCTest
@testable import ToolulaCleaner

final class LocalizationTests: XCTestCase {
    func testFormatAndFallback() {
        // 测试进程里没有翻译表, 返回中文原文 (并正确填入参数)
        XCTAssertEqual(L("已选 %@ 项 · %@", "3", "2 GB"), "已选 3 项 · 2 GB")
        XCTAssertEqual(L("没有这个键"), "没有这个键")
    }

    /// translations.json: 每个键都有 9 种语言, 占位符数量一致
    func testTranslationsTableComplete() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Localization/translations.json")
        let table = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: [String: String]]
        let langs = ["en", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt", "ru"]
        let ph = try NSRegularExpression(pattern: #"%(\d+\$)?@"#)
        func count(_ s: String) -> Int { ph.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s)) }
        XCTAssertGreaterThan(table.count, 200)
        for (key, tr) in table {
            for l in langs {
                let v = try XCTUnwrap(tr[l], "缺少 [\(l)] \(key)")
                XCTAssertFalse(v.isEmpty, "[\(l)] \(key)")
                XCTAssertEqual(count(v), count(key), "占位符数量不对 [\(l)] \(key) → \(v)")
            }
        }
    }

    func testFormatWithPositionalPlaceholders() {
        let s = String(format: "%2$@ – %1$@", arguments: ["a" as NSString, "b" as NSString])
        XCTAssertEqual(s, "b – a")
    }
}

final class MemoryTests: XCTestCase {
    func testSnapshotIsSane() {
        let s = MemoryMonitor.read()
        XCTAssertGreaterThan(s.total, 1_000_000_000)
        XCTAssertGreaterThan(s.used, 0)
        XCTAssertLessThanOrEqual(s.used, s.total)
        XCTAssertGreaterThanOrEqual(s.free, 0)
    }

    func testDescribeBackgroundPrograms() {
        XCTAssertEqual(MemoryMonitor.describe(args: ["node", "/Users/a/proj-x/node_modules/.bin/vite"]), "vite · proj-x")
        XCTAssertEqual(MemoryMonitor.describe(args: ["/usr/bin/python3", "-u", "/Users/a/tools/server.py"]), "server.py · tools")
        XCTAssertEqual(MemoryMonitor.describe(args: ["python3", "-m", "http.server"]), "http.server")
        XCTAssertNil(MemoryMonitor.describe(args: ["node", "-e", "console.log(1)"]), "直接写在命令里的代码没有脚本名")
        XCTAssertNil(MemoryMonitor.describe(args: ["/Applications/Foo.app/Contents/MacOS/Foo"]), "不是解释器")
    }

    func testTopGroupsListsThisProcess() {
        let groups = MemoryMonitor.topGroups(limit: 500)
        XCTAssertFalse(groups.isEmpty)
        XCTAssertEqual(groups.map(\.bytes), groups.map(\.bytes).sorted(by: >))
        // 自己这个进程不能被「结束」
        let me = getpid()
        if let mine = groups.first(where: { $0.pids.contains(me) }) { XCTAssertFalse(mine.canQuit) }
    }
}
