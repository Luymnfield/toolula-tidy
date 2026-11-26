import Foundation
import XCTest
@testable import ToolulaCleaner

/// 卸载: 找残留文件、已删除应用的残留、删除前的保险
final class UninstallerTests: FakeHomeTestCase {

    func testLooksLikeBundleID() {
        XCTAssertTrue(LeftoverPlace.looksLikeBundleID("com.example.app"))
        XCTAssertTrue(LeftoverPlace.looksLikeBundleID("io.some-vendor.my_app"))
        XCTAssertFalse(LeftoverPlace.looksLikeBundleID("nglclient_hdesd15.3.1.470.log"), "带版本号的日志不是应用 ID")
        XCTAssertFalse(LeftoverPlace.looksLikeBundleID("Claude"))
        XCTAssertFalse(LeftoverPlace.looksLikeBundleID("com.example"))
        XCTAssertFalse(LeftoverPlace.looksLikeBundleID("com.example.1.2"))
    }

    func testLeftoversForApp() throws {
        let appURL = try app("Applications/Dummy Notes.app", bundleID: "com.example.dummynotes", executable: "DummyNotes")
        try file("Library/Preferences/com.example.dummynotes.plist")
        try file("Library/Preferences/com.example.dummynotes.helper.plist")
        try file("Library/Caches/com.example.dummynotes/c.bin")
        try file("Library/Application Support/Dummy Notes/db.sqlite", bytes: 40_000)     // 按应用名
        try file("Library/Containers/com.example.dummynotes/Data/x")
        try file("Library/Group Containers/TEAM123.com.example.dummynotes/x")
        try file("Library/Saved Application State/com.example.dummynotes.savedState/x")
        // 不该算进来的
        try file("Library/Preferences/com.example.dummynotes.canary.plist")   // 另一个已安装的应用
        try file("Library/Preferences/com.example.other.plist")
        try file("Library/Keychains/com.example.dummynotes.keychain")         // 不在残留位置里
        try file("Library/Application Support/Dummy/x")                        // 名字不完全一样

        let entry = AppEntry(url: appURL, name: "Dummy Notes", bundleID: "com.example.dummynotes", version: "1.2", isAppStore: false)
        let found = Uninstaller.leftovers(for: entry, others: ["com.example.dummynotes.canary"]).map { $0.url.lastPathComponent }.sorted()
        XCTAssertEqual(found, ["Dummy Notes", "TEAM123.com.example.dummynotes", "com.example.dummynotes", "com.example.dummynotes",
                               "com.example.dummynotes.helper.plist", "com.example.dummynotes.plist",
                               "com.example.dummynotes.savedState"].sorted())
        let all = Uninstaller.leftovers(for: entry, others: [])
        XCTAssertTrue(all.allSatisfy(\.selected))
        XCTAssertTrue(all.allSatisfy { Uninstaller.allowed($0.url, isApp: false) })
    }

    func testKnownVendorPaths() throws {
        let appURL = try app("Applications/Google Chrome.app", bundleID: "com.google.Chrome")
        try file("Library/Application Support/Google/Chrome/Default/Bookmarks", bytes: 9000)
        try file("Library/Application Support/Google/Drive/x")      // 同一厂商的另一个应用, 不能算
        let entry = AppEntry(url: appURL, name: "Google Chrome", bundleID: "com.google.Chrome", version: "", isAppStore: false)
        let found = Uninstaller.leftovers(for: entry).map(\.url.path)
        XCTAssertTrue(found.contains { $0.hasSuffix("Application Support/Google/Chrome") })
        XCTAssertFalse(found.contains { $0.contains("Google/Drive") })
    }

    func testOrphans() throws {
        try file("Library/Application Support/com.gone.vendorapp/data")          // 残留
        try file("Library/Preferences/com.gone.vendorapp.plist")                  // 残留
        try file("Library/Preferences/com.apple.finder.plist")                    // 苹果的, 不算
        try file("Library/Preferences/com.installed.thing.helper.plist")          // 已安装应用的
        try file("Library/Preferences/com.installed.other.plist")                 // 同一厂商, 保守不算
        try file("Library/LaunchAgents/com.gone.vendorapp.agent.plist")           // 启动项永远不算
        try file("Library/Group Containers/group.com.gone.vendorapp/x")           // 共享数据不看
        try file("Library/Logs/NGLClient_HDESD15.3.1.470.log")                    // 不是应用 ID
        let installed = [AppEntry(url: home.appendingPathComponent("Applications/T.app"), name: "T",
                                  bundleID: "com.installed.thing", version: "", isAppStore: false)]
        let found = Uninstaller.orphans(installed: installed).map { $0.url.lastPathComponent }.sorted()
        XCTAssertEqual(found, ["com.gone.vendorapp", "com.gone.vendorapp.plist"])
        XCTAssertTrue(Uninstaller.orphans(installed: installed).allSatisfy { !$0.selected }, "默认不勾选")
    }

    func testAppAllowedOnlyInApplicationsFolders() throws {
        let ok = try app("Applications/Tool.app", bundleID: "com.example.tool")
        XCTAssertTrue(Uninstaller.allowed(ok, isApp: true))
        let nested = try app("Applications/Vendor/Tool2.app", bundleID: "com.example.tool2")
        XCTAssertTrue(Uninstaller.allowed(nested, isApp: true))
        let deep = try app("Applications/A/B/Deep.app", bundleID: "com.example.deep")
        XCTAssertFalse(Uninstaller.allowed(deep, isApp: true))
        let elsewhere = try app("Documents/Copy.app", bundleID: "com.example.copy")
        XCTAssertFalse(Uninstaller.allowed(elsewhere, isApp: true))
        XCTAssertFalse(Uninstaller.allowed(URL(fileURLWithPath: "/Applications/Safari.app"), isApp: true), "系统保护的应用")
        XCTAssertFalse(Uninstaller.allowed(home.appendingPathComponent("Library/Keychains/x"), isApp: false))
    }

    func testUninstallMovesToTrashAndReturnsLocation() throws {
        let a = try app("Applications/Bye.app", bundleID: "com.example.bye")
        let to = try XCTUnwrap(Uninstaller.trash(a, isApp: true))
        trashed.append(to)
        XCTAssertFalse(fm.fileExists(atPath: a.path))
        XCTAssertTrue(fm.fileExists(atPath: to.appendingPathComponent("Contents/Info.plist").path))
    }
}
