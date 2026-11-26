import Foundation
import XCTest
@testable import ToolulaCleaner

/// 开发项目里的垃圾
final class ProjectJunkTests: FakeHomeTestCase {
    func old(_ days: Double) -> Date { Date().addingTimeInterval(-days * 86400) }

    func testFindsOnlyRealProjectFolders() throws {
        try file("Code/web/package.json", modified: old(100))
        try file("Code/web/node_modules/react/index.js", bytes: 40_000)
        try file("Code/web/node_modules/react/node_modules/x/y.js")      // 里面的不再单独列
        try file("Code/py/.venv/pyvenv.cfg")
        try file("Code/py/.venv/lib/big.so", bytes: 30_000)
        try file("Code/rust/Cargo.toml")
        try file("Code/rust/target/debug/app", bytes: 30_000)
        try file("Documents/build/my-notes.txt")                          // 你自己叫 build 的文件夹, 不是项目
        try file("Documents/node_modules/x.js")                           // 旁边没有 package.json
        try file("Code/fakevenv/venv/lib/x.py")                           // 没有 pyvenv.cfg
        try file("Library/Code/node_modules/x.js"); try file("Library/Code/package.json")
        try file("Toolula/app/node_modules/x.js"); try file("Toolula/app/package.json")
        let out = Scanner.scan(.projects, ctx)
        let paths = out.items.map { Scanner.short($0.url) }.sorted()
        XCTAssertEqual(paths, ["~/Code/py/.venv", "~/Code/rust/target", "~/Code/web/node_modules"])
        XCTAssertTrue(out.items.allSatisfy { Safety.allowed($0.url, kind: .projects) })
    }

    func testStaleProjectsSelectedRecentNot() throws {
        try file("Code/old/package.json", modified: old(90))
        try file("Code/old/node_modules/a.js", bytes: 20_000)
        try fm.setAttributes([.modificationDate: old(90)], ofItemAtPath: home.appendingPathComponent("Code/old").path)
        try file("Code/new/package.json")
        try file("Code/new/node_modules/a.js", bytes: 20_000)
        let out = Scanner.scan(.projects, ctx)
        let old = try XCTUnwrap(out.items.first { $0.url.path.contains("/old/") })
        let new = try XCTUnwrap(out.items.first { $0.url.path.contains("/new/") })
        XCTAssertTrue(old.selected)
        XCTAssertNil(old.note)
        XCTAssertFalse(new.selected, "最近在用的项目不勾选")
        XCTAssertNotNil(new.note)
    }

    func testSafetyRefusesSourceAndUnmatched() throws {
        try file("Code/web/package.json")
        try file("Code/web/src/main.js")
        try file("Code/web/node_modules/a.js")
        XCTAssertTrue(Safety.allowed(home.appendingPathComponent("Code/web/node_modules"), kind: .projects))
        XCTAssertFalse(Safety.allowed(home.appendingPathComponent("Code/web/src"), kind: .projects))
        XCTAssertFalse(Safety.allowed(home.appendingPathComponent("Code/web"), kind: .projects))
        try file("Documents/build/x.txt")
        XCTAssertFalse(Safety.allowed(home.appendingPathComponent("Documents/build"), kind: .projects))
        XCTAssertThrowsError(try Safety.remove(home.appendingPathComponent("Code/web/src"), kind: .projects, permanent: true))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("Code/web/src/main.js").path))
    }
}

/// 重复文件
final class DuplicatesTests: FakeHomeTestCase {
    func content(_ seed: UInt8, _ n: Int = 1_200_000) -> Data { Data((0..<n).map { UInt8(truncatingIfNeeded: Int($0) &* 31) ^ seed }) }

    func put(_ rel: String, _ d: Data) throws -> URL {
        let u = home.appendingPathComponent(rel)
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try d.write(to: u)
        return u
    }

    func testFindsIdenticalOnly() throws {
        let a = content(1)
        try put("Documents/a.bin", a)
        Thread.sleep(forTimeInterval: 1.1)   // 创建时间不同: 默认留下最早的
        try put("Downloads/a copy.bin", a)
        try put("Pictures/a again.bin", a)
        var b = a; b[b.count / 2] ^= 0xFF                    // 一样大, 只有中间一个字节不同
        try put("Documents/b.bin", b)
        try put("Documents/small1.txt", Data(repeating: 1, count: 1000))   // 太小
        try put("Documents/small2.txt", Data(repeating: 1, count: 1000))
        try put("Library/a.bin", a)                                        // 资源库不看
        let groups = Duplicates.find(minSize: 1_000_000)
        XCTAssertEqual(groups.count, 1)
        let g = try XCTUnwrap(groups.first)
        XCTAssertEqual(g.files.count, 3)
        XCTAssertEqual(g.files[0].url.lastPathComponent, "a.bin", "留下不在下载里的那份")
        XCTAssertFalse(g.files[0].selected)
        XCTAssertTrue(g.files.dropFirst().allSatisfy(\.selected))
        XCTAssertTrue(g.keepsOne)
        XCTAssertEqual(g.wasted, g.size * 2)
    }

    func testHardLinksAreNotDuplicates() throws {
        let a = try put("Documents/a.bin", content(2))
        try fm.linkItem(at: a, to: home.appendingPathComponent("Documents/link.bin"))
        XCTAssertTrue(Duplicates.find(minSize: 1_000_000).isEmpty)
    }

    func testFilesInProjectsNotSelected() throws {
        let a = content(3)
        try put("Code/site/package.json", Data("{}".utf8))
        try put("Code/site/dist/font.ttf", a)
        try put("Code/site/public/font.ttf", a)
        let g = try XCTUnwrap(Duplicates.find(minSize: 1_000_000).first)
        XCTAssertTrue(g.files.allSatisfy { $0.inProject && !$0.selected })
    }

    @MainActor func testStoreKeepsAtLeastOneAndCleansWithUndo() async throws {
        let a = content(4)
        try put("Documents/a.bin", a)
        Thread.sleep(forTimeInterval: 1.1)
        let copy = try put("Documents/copy.bin", a)
        let store = DuplicateStore()
        let cleaner = CleanerStore()
        store.cleaner = cleaner
        store.groups = Duplicates.find(minSize: 1_000_000)
        let g = try XCTUnwrap(store.groups.first)
        store.toggle(g.id, g.files[0].id)   // 最后一个保留的不能勾上
        XCTAssertFalse(store.groups[0].files[0].selected)
        store.clean()
        for _ in 0..<100 where store.groups.count > 0 || store.cleaning { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(fm.fileExists(atPath: copy.path))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("Documents/a.bin").path))
        let rec = try XCTUnwrap(cleaner.history.first)
        trashed += rec.moves.map { URL(fileURLWithPath: $0.to) }
        XCTAssertEqual(CleanerStore.restore(rec.moves).restored, 1)
        XCTAssertTrue(fm.fileExists(atPath: copy.path))
    }
}

/// 启动项
final class StartupTests: FakeHomeTestCase {
    var saved: (([String]) -> (Int32, String), [(URL, StartupItem.Scope)])!

    override func setUpWithError() throws {
        try super.setUpWithError()
        saved = (Startup.launchctl, Startup.systemDirs)
        Startup.launchctl = FakeLaunchctl.run
        Startup.systemDirs = [(home.appendingPathComponent("SysAgents"), .global), (home.appendingPathComponent("SysDaemons"), .daemon)]
        FakeLaunchctl.disabled = [:]
        FakeLaunchctl.calls = []
    }

    override func tearDownWithError() throws {
        Startup.launchctl = saved.0
        Startup.systemDirs = saved.1
        try super.tearDownWithError()
    }

    func agent(_ dir: String, _ label: String, program: String, args: Bool = true, disabled: Bool? = nil) throws {
        try fm.createDirectory(at: home.appendingPathComponent(dir), withIntermediateDirectories: true)
        var d: [String: Any] = ["Label": label]
        if args { d["ProgramArguments"] = [program, "--flag"] } else { d["Program"] = program }
        if let disabled { d["Disabled"] = disabled }
        (d as NSDictionary).write(to: home.appendingPathComponent("\(dir)/\(label).plist"), atomically: true)
    }

    func testListParsesAndMarksMissingPrograms() throws {
        let appURL = try app("Applications/Helper Host.app", bundleID: "com.example.host", executable: "Host")
        try agent("Library/LaunchAgents", "com.example.host.agent", program: appURL.path + "/Contents/MacOS/Host")
        try agent("Library/LaunchAgents", "com.gone.agent", program: "/nonexistent/bin/gone", args: false)
        try agent("SysAgents", "com.example.global", program: "/bin/sh", disabled: true)
        try agent("SysDaemons", "com.example.daemon", program: "/bin/sh")
        let items = Startup.list()
        XCTAssertEqual(items.map(\.scope), [.user, .user, .global, .daemon])
        let host = try XCTUnwrap(items.first { $0.label == "com.example.host.agent" })
        XCTAssertEqual(host.name, "Helper Host")
        XCTAssertEqual(host.app?.lastPathComponent, "Helper Host.app")
        XCTAssertFalse(host.programMissing)
        let gone = try XCTUnwrap(items.first { $0.label == "com.gone.agent" })
        XCTAssertTrue(gone.programMissing)
        XCTAssertTrue(gone.canRemove)
        XCTAssertTrue(items.first { $0.label == "com.example.global" }!.disabled, "plist 里写了 Disabled")
        XCTAssertFalse(items.first { $0.label == "com.example.daemon" }!.canToggle)
    }

    func testToggleUsesLaunchctlAndOverridesPlist() throws {
        try agent("Library/LaunchAgents", "com.example.a", program: "/bin/sh")
        var item = try XCTUnwrap(Startup.list().first)
        XCTAssertNil(Startup.setEnabled(item, false))
        XCTAssertTrue(FakeLaunchctl.calls.contains(["disable", "gui/\(getuid())/com.example.a"]))
        XCTAssertTrue(FakeLaunchctl.calls.contains(["bootout", "gui/\(getuid())/com.example.a"]))
        item = try XCTUnwrap(Startup.list().first)
        XCTAssertTrue(item.disabled)
        XCTAssertNil(Startup.setEnabled(item, true))
        XCTAssertFalse(try XCTUnwrap(Startup.list().first).disabled)
        let daemon = StartupItem(label: "d", plist: URL(fileURLWithPath: "/Library/LaunchDaemons/d.plist"), scope: .daemon, program: nil,
                                 app: nil, name: "d", disabled: false, running: false, programMissing: false)
        XCTAssertNotNil(Startup.setEnabled(daemon, false), "系统后台服务不能改")
    }

    func testParsers() {
        let d = Startup.parseDisabled("disabled services = {\n\t\t\"com.a\" => enabled\n\t\t\"com.b\" => disabled\n\t\t\"com.c\" => true\n\t}")
        XCTAssertEqual(d, ["com.a": false, "com.b": true, "com.c": true])
        let l = Startup.parseList("PID\tStatus\tLabel\n123\t0\tcom.run\n-\t0\tcom.idle\n")
        XCTAssertEqual(l, ["com.run": true, "com.idle": false])
        XCTAssertEqual(Startup.ownerApp("/Applications/X.app/Contents/MacOS/x")?.path, "/Applications/X.app")
        XCTAssertNil(Startup.ownerApp("/usr/local/bin/tool"))
    }

    func testOnlyUserAgentsRemovable() {
        XCTAssertTrue(Startup.removable(home.appendingPathComponent("Library/LaunchAgents/a.plist")))
        XCTAssertFalse(Startup.removable(URL(fileURLWithPath: "/Library/LaunchAgents/a.plist")))
        XCTAssertFalse(Startup.removable(home.appendingPathComponent("Library/LaunchAgents/../Preferences/a.plist")))
    }
}

/// 空间地图
final class DiskMapTests: FakeHomeTestCase {
    func testTwoLevelsMatchesStat() throws {
        try file("Big/a/x.bin", bytes: 500_000)
        try file("Big/b.bin", bytes: 200_000)
        try file("Small/c.bin", bytes: 10_000)
        try file(".hidden/d.bin", bytes: 300_000)
        try file("top.bin", bytes: 50_000)
        let (nodes, next) = DiskMap.twoLevels(of: home)
        XCTAssertEqual(nodes.map(\.name), ["Big", ".hidden", "top.bin", "Small"])
        XCTAssertEqual(nodes.first?.size, statSize(home.appendingPathComponent("Big")))
        XCTAssertEqual(next[home.appendingPathComponent("Big").path]?.map(\.name), ["a", "b.bin"])
        XCTAssertEqual(DiskMap.children(of: home.appendingPathComponent("Big")).map(\.size),
                       next[home.appendingPathComponent("Big").path]?.map(\.size))
    }

    func testTreemapLayoutAreasAndBounds() {
        let sizes: [Double] = [60, 25, 10, 3, 1, 1]
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let rects = DiskMap.layout(sizes, in: rect)
        let total = sizes.reduce(0, +)
        for (s, r) in zip(sizes, rects) {
            XCTAssertEqual(Double(r.width * r.height), s / total * 120_000, accuracy: 1)
            XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(r))
        }
        for i in rects.indices { for j in rects.indices where i < j {
            XCTAssertLessThan(rects[i].intersection(rects[j]).width * rects[i].intersection(rects[j]).height, 1, "不能重叠")
        } }
    }

    func testSmallNodesMergedIntoOthers() {
        var nodes = [MapNode(url: URL(fileURLWithPath: "/a"), name: "a", size: 1_000_000, isDir: true)]
        for i in 0..<50 { nodes.append(MapNode(url: URL(fileURLWithPath: "/s\(i)"), name: "s\(i)", size: 10, isDir: false)) }
        let shown = DiskMap.forMap(nodes)
        XCTAssertEqual(shown.count, 2)
        XCTAssertEqual(shown.last?.others, 50)
        XCTAssertEqual(shown.reduce(0) { $0 + $1.size }, nodes.reduce(0) { $0 + $1.size })
    }
}
