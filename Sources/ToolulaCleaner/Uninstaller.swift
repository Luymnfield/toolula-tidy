import AppKit
import Foundation
import SwiftUI

/// 一个已安装的应用
struct AppEntry: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let isAppStore: Bool
    var size: Int64?
    var lastUsed: Date?
}

/// 应用的「残留文件」放在 ~/Library 下的这些地方 (文件夹, 显示名)
enum LeftoverPlace {
    static var places: [(String, String)] { [
        ("Application Support", L("应用数据")),
        ("Caches", L("缓存")),
        ("Preferences", L("偏好设置")),
        ("Preferences/ByHost", L("偏好设置")),
        ("Containers", L("沙盒数据")),
        ("Group Containers", L("共享数据")),
        ("Saved Application State", L("窗口状态")),
        ("Logs", L("日志")),
        ("HTTPStorages", L("网络数据")),
        ("WebKit", L("网页数据")),
        ("Cookies", "Cookies"),
        ("LaunchAgents", L("开机启动项")),
        ("Application Scripts", L("脚本")),
    ] }
    static func root(_ p: String) -> URL { Scanner.home.appendingPathComponent("Library").appendingPathComponent(p) }
    /// 只按名字匹配的地方 (名字太泛的不匹配, 避免误删同厂商其他应用的数据)
    static let nameMatchPlaces: Set<String> = ["Application Support", "Caches", "Logs"]
    static let genericNames: Set<String> = ["google", "microsoft", "adobe", "apple", "electron", "helper", "update", "updater",
                                            "crashpad", "crashreporter", "plugins", "data", "cache", "logs", "app", "setup", "installer"]
    static let suffixes = [".plist", ".savedstate", ".binarycookies"]

    static func base(_ name: String) -> String {
        var n = name.lowercased()
        for s in suffixes where n.hasSuffix(s) { n.removeLast(s.count) }
        return n
    }

    /// 常见的反向域名开头 (日志文件 "xxx15.3.1.log" 这种带版本号的名字就不会被当成应用 ID)
    static let tlds: Set<String> = ["com", "org", "net", "io", "ai", "co", "app", "dev", "me", "de", "cn", "jp", "uk", "us",
                                    "tv", "fr", "it", "nl", "ru", "kr", "ch", "se", "at", "cc", "so", "sh", "xyz", "info", "pro",
                                    "edu", "eu", "ca", "au", "in", "tw", "hk", "company", "technology", "studio"]

    /// 看起来是应用 ID (反向域名, 至少两个点, 没有纯数字的段)
    static func looksLikeBundleID(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, tlds.contains(String(parts[0])) else { return false }
        return parts.allSatisfy { p in
            !p.isEmpty && p.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } && !p.allSatisfy(\.isNumber)
        }
    }

    /// 不是应用、而是开发工具或第三方 SDK 留下的 (不算残留)
    static let notApps = ["org.swift.", "com.firebase.", "com.crashlytics.", "io.sentry.", "org.sparkle-project.",
                          "com.google.", "com.microsoft.", "org.python.", "org.nodejs.", "com.github.electron"]

    /// 有名的应用把数据放在厂商文件夹里, 名字匹配找不到, 单独列出
    static let knownPaths: [String: [String]] = [
        "com.google.chrome": ["Application Support/Google/Chrome", "Caches/Google/Chrome"],
        "com.google.chrome.canary": ["Application Support/Google/Chrome Canary", "Caches/Google/Chrome Canary"],
        "com.microsoft.edgemac": ["Application Support/Microsoft Edge", "Caches/Microsoft Edge"],
        "com.brave.browser": ["Application Support/BraveSoftware/Brave-Browser", "Caches/BraveSoftware/Brave-Browser"],
        "org.mozilla.firefox": ["Application Support/Firefox", "Caches/Firefox"],
        "com.spotify.client": ["Application Support/Spotify", "Caches/com.spotify.client"],
        "com.tinyspeck.slackmacgap": ["Application Support/Slack"],
        "com.microsoft.vscode": ["Application Support/Code"],
    ]
}

enum Uninstaller {
    static let appDirs: [URL] = [URL(fileURLWithPath: "/Applications"), Scanner.u("Applications")]

    // MARK: 列出应用

    /// 列出 /Applications 和 ~/Applications (含一层子文件夹, 如 Utilities、Adobe xxx) 里能卸载的应用
    static func listApps() -> [AppEntry] {
        var urls: [URL] = []
        for dir in appDirs {
            for c in Scanner.children(dir) {
                if c.pathExtension == "app" { urls.append(c) }
                else if isDir(c) { urls += Scanner.children(c).filter { $0.pathExtension == "app" } }
            }
        }
        let me = Bundle.main.bundleIdentifier ?? "com.toolula.cleaner"
        var out = [AppEntry?](repeating: nil, count: urls.count)
        out.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in
                let u = urls[i]
                guard !isSystemProtected(u),
                      let info = NSDictionary(contentsOf: u.appendingPathComponent("Contents/Info.plist")),
                      let bid = info["CFBundleIdentifier"] as? String, bid != me else { return }
                var name = FileManager.default.displayName(atPath: u.path)
                if name.hasSuffix(".app") { name.removeLast(4) }
                buf[i] = AppEntry(url: u, name: name, bundleID: bid,
                                  version: info["CFBundleShortVersionString"] as? String ?? "",
                                  isAppStore: FileManager.default.fileExists(atPath: u.appendingPathComponent("Contents/_MASReceipt").path),
                                  size: nil, lastUsed: lastUsed(u))
            }
        }
        return out.compactMap { $0 }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 受系统完整性保护 (SIP) 的应用, 例如 Safari: 不能也不该卸载
    static func isSystemProtected(_ url: URL) -> Bool {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return true }
        if (st.st_mode & S_IFMT) == S_IFLNK { return true }          // 链接 (例如指向系统里的应用)
        return st.st_flags & UInt32(SF_RESTRICTED) != 0
    }

    static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    static func isDir(_ u: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
    }

    // MARK: 残留文件

    /// 找一个应用在 ~/Library 里留下的文件 (按应用 ID 精确匹配; 少数地方再按完整的应用名匹配)
    /// others: 其他已安装应用的 ID (例如 Chrome 和 Chrome Canary, 不能把别人的数据当成残留)
    static func leftovers(for app: AppEntry, others: [String] = []) -> [CleanItem] {
        let bid = app.bundleID.lowercased()
        let other = others.map { $0.lowercased() }.filter { $0 != bid && $0.hasPrefix(bid + ".") }
        guard LeftoverPlace.looksLikeBundleID(bid) || bid.split(separator: ".").count >= 2 else { return [] }
        let exec = (NSDictionary(contentsOf: app.url.appendingPathComponent("Contents/Info.plist"))?["CFBundleExecutable"] as? String ?? "").lowercased()
        let names = Set([app.name.lowercased(), exec].filter { $0.count >= 4 && !LeftoverPlace.genericNames.contains($0) })

        var found: [(URL, String)] = []
        for (place, label) in LeftoverPlace.places {
            for c in Scanner.children(LeftoverPlace.root(place)) {
                let b = LeftoverPlace.base(c.lastPathComponent)
                var hit = b == bid || b.hasPrefix(bid + ".")
                if place == "Group Containers" { hit = hit || b.hasSuffix("." + bid) || b == "group." + bid || b.hasPrefix("group." + bid + ".") }
                if !hit, LeftoverPlace.nameMatchPlaces.contains(place) { hit = names.contains(b) }
                if place == "Preferences", c.lastPathComponent == "ByHost" { hit = false }
                if hit, other.contains(where: { b == $0 || b.hasPrefix($0 + ".") }) { hit = false }
                if hit { found.append((c, label)) }
            }
        }
        for rel in LeftoverPlace.knownPaths[bid] ?? [] {
            let u = LeftoverPlace.root(rel)
            guard FileManager.default.fileExists(atPath: u.path), !found.contains(where: { $0.0 == u }) else { continue }
            let label = LeftoverPlace.places.first { rel.hasPrefix($0.0 + "/") }?.1 ?? L("应用数据")
            found.append((u, label))
        }
        let sizes = FastWalker.sizes(found.map(\.0.path))
        return zip(found, sizes).map { f, size in
            CleanItem(url: f.0, name: f.0.lastPathComponent, detail: "\(f.1) · \(Scanner.short(f.0.deletingLastPathComponent()))",
                      size: size, selected: true)
        }.sorted { $0.size > $1.size }
    }

    /// 已经删掉的应用留下的文件: 名字是应用 ID, 但电脑上找不到这个应用 (也找不到同一厂商的应用)
    static func orphans(installed: [AppEntry]) -> [CleanItem] {
        let ids = installed.map { $0.bundleID.lowercased() }
        let vendors = Set(ids.map { $0.split(separator: ".").prefix(2).joined(separator: ".") })
        var found: [(URL, String, String)] = []
        // 不看: 共享数据 (多个应用共用)、开机启动项 (可能是你自己写的脚本)
        for (place, label) in LeftoverPlace.places where place != "Group Containers" && place != "LaunchAgents" {
            for c in Scanner.children(LeftoverPlace.root(place)) {
                var b = LeftoverPlace.base(c.lastPathComponent)
                if b.hasPrefix("group.") { b.removeFirst("group.".count) }
                guard LeftoverPlace.looksLikeBundleID(b), !b.hasPrefix("com.apple."), !b.hasPrefix("com.toolula."),
                      !LeftoverPlace.notApps.contains(where: { b.hasPrefix($0) }) else { continue }
                let vendor = b.split(separator: ".").prefix(2).joined(separator: ".")
                if vendors.contains(vendor) { continue }
                if ids.contains(where: { b == $0 || b.hasPrefix($0 + ".") }) { continue }
                found.append((c, label, b))
            }
        }
        // LaunchServices 还认识的应用 (装在别处) 也不算残留
        var keep = [Bool](repeating: false, count: found.count)
        keep.withUnsafeMutableBufferPointer { k in
            DispatchQueue.concurrentPerform(iterations: found.count) { i in
                k[i] = NSWorkspace.shared.urlForApplication(withBundleIdentifier: found[i].2) == nil
            }
        }
        let list = zip(found, keep).filter(\.1).map(\.0)
        let sizes = FastWalker.sizes(list.map(\.0.path))
        return zip(list, sizes).map { f, size in
            CleanItem(url: f.0, name: f.2, detail: "\(f.1) · \(Scanner.short(f.0))", size: size, selected: false)
        }.sorted { $0.size > $1.size }
    }

    // MARK: 卸载

    /// 删除前的保险: 应用本身只能是「应用程序」文件夹里的 .app; 残留只能在上面那些 ~/Library 文件夹 *里面*
    static func allowed(_ url: URL, isApp: Bool) -> Bool {
        let p = url.standardizedFileURL.path
        if isApp {
            guard url.pathExtension == "app", !isSystemProtected(url) else { return false }
            return appDirs.contains { d in p.hasPrefix(d.path + "/") && url.pathComponents.count <= d.pathComponents.count + 2 }
        }
        return LeftoverPlace.places.contains { p.hasPrefix(LeftoverPlace.root($0.0).path + "/") }
    }

    /// 移到废纸篓. 应用文件夹没有权限时 (例如 App Store 安装的), 交给访达处理, 访达会要求输入密码
    static func trash(_ url: URL, isApp: Bool) throws {
        guard allowed(url, isApp: isApp) else {
            throw NSError(domain: "ToolulaCleaner", code: 1, userInfo: [NSLocalizedDescriptionKey: L("不在允许删除的位置：%@", "\(url.path)")])
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch where isApp {
            let path = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "tell application \"Finder\" to delete (POSIX file \"\(path)\" as alias)"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            if FileManager.default.fileExists(atPath: url.path) { throw error }
        }
    }
}

// MARK: - 状态

@MainActor
final class UninstallStore: ObservableObject {
    enum Tab: Hashable { case apps, orphans }
    enum SortKey: String, CaseIterable, Identifiable {
        case size = "按大小", name = "按名字", lastUsed = "按最近使用"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .size: return L("按大小")
            case .name: return L("按名字")
            case .lastUsed: return L("按最近使用")
            }
        }
    }

    @Published var apps: [AppEntry] = []
    @Published var loading = false
    @Published var sizing = false
    @Published var selectedID: String?
    @Published var leftovers: [CleanItem] = []
    @Published var leftoversLoading = false
    @Published var search = ""
    @Published var sort: SortKey = .size
    @Published var tab: Tab = .apps
    @Published var orphans = CategoryState()
    @Published var running: Set<String> = []
    @Published var busy = false
    @Published var pendingUninstall: AppEntry?
    @Published var pendingOrphanClean = false
    weak var cleaner: CleanerStore?
    private var observers: [NSObjectProtocol] = []

    init() {
        refreshRunning()
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunning() }
            })
        }
    }

    func refreshRunning() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    var selected: AppEntry? { apps.first { $0.id == selectedID } }

    var visibleApps: [AppEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? apps : apps.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
        switch sort {
        case .size: return list.sorted { ($0.size ?? -1) > ($1.size ?? -1) }
        case .name: return list
        case .lastUsed: return list.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        }
    }

    var appsTotal: Int64 { apps.reduce(0) { $0 + ($1.size ?? 0) } }
    var leftoverSelectedSize: Int64 { leftovers.filter(\.selected).reduce(0) { $0 + $1.size } }

    func loadIfNeeded() { if apps.isEmpty && !loading { load() } }

    /// 先出列表 (很快), 再在后台算每个应用的大小
    func load() {
        loading = true
        Task.detached(priority: .userInitiated) {
            let list = Uninstaller.listApps()
            await MainActor.run {
                self.apps = list
                self.loading = false
                self.sizing = true
                if self.selectedID == nil || !list.contains(where: { $0.id == self.selectedID }) { self.selectedID = nil }
                // 调试: --select 应用ID  直接选中某个应用
                if let i = CommandLine.arguments.firstIndex(of: "--select"), i + 1 < CommandLine.arguments.count,
                   let a = list.first(where: { $0.bundleID == CommandLine.arguments[i + 1] }) { self.select(a) }
            }
            let sizes = FastWalker.sizes(list.map(\.url.path))
            await MainActor.run {
                var dict: [String: Int64] = [:]
                for (a, s) in zip(list, sizes) { dict[a.id] = s }
                withAnimation { self.apps = self.apps.map { var a = $0; a.size = dict[a.id] ?? a.size; return a } }
                self.sizing = false
            }
        }
    }

    func select(_ app: AppEntry) {
        selectedID = app.id
        leftovers = []
        leftoversLoading = true
        refreshRunning()
        let others = apps.map(\.bundleID)
        Task.detached(priority: .userInitiated) {
            let items = Uninstaller.leftovers(for: app, others: others)
            await MainActor.run {
                guard self.selectedID == app.id else { return }
                self.leftovers = items
                self.leftoversLoading = false
            }
        }
    }

    func toggleLeftover(_ id: String) {
        if let i = leftovers.firstIndex(where: { $0.id == id }) { leftovers[i].selected.toggle() }
    }

    func quit(_ app: AppEntry) {
        for r in NSWorkspace.shared.runningApplications where r.bundleIdentifier == app.bundleID { r.terminate() }
    }

    func uninstall(_ app: AppEntry) {
        let items = leftovers.filter(\.selected)
        busy = true
        Task.detached(priority: .userInitiated) {
            var freed: Int64 = 0, failed = 0, count = 0
            var appGone = false
            do {
                try Uninstaller.trash(app.url, isApp: true)
                freed += app.size ?? 0; count += 1; appGone = true
            } catch { failed += 1 }
            if appGone {
                for i in items {
                    do { try Uninstaller.trash(i.url, isApp: false); freed += i.size; count += 1 } catch { failed += 1 }
                }
            }
            await MainActor.run {
                self.busy = false
                guard appGone else {
                    self.cleaner?.show(L("没能卸载「%@」：没有权限，或者应用正在使用", "\(app.name)"))
                    return
                }
                withAnimation { self.apps.removeAll { $0.id == app.id } }
                self.selectedID = nil
                self.leftovers = []
                self.cleaner?.record(bytes: freed, count: count, kinds: [L("卸载 %@", "\(app.name)")])
                var msg = L("已卸载「%@」，%@ 移到了废纸篓", "\(app.name)", "\(Scanner.bytes(freed))")
                if failed > 0 { msg += L("；%@ 个文件没有权限，已跳过", "\(failed)") }
                self.cleaner?.show(msg)
                self.cleaner?.scan([.trash])
            }
        }
    }

    /// 切换语言后: 重新找当前应用的残留 / 已删除应用的残留 (位置名称用新语言)
    func relocalize() {
        if let a = selected { select(a) }
        if orphans.scanned {
            orphans = CategoryState()
            scanOrphans()
        }
    }

    // MARK: 残留 (已删除应用)

    func scanOrphans() {
        guard !orphans.scanning else { return }
        orphans.scanning = true
        let installed = apps
        Task.detached(priority: .userInitiated) {
            let list = installed.isEmpty ? Uninstaller.listApps() : installed
            let items = Uninstaller.orphans(installed: list)
            await MainActor.run { withAnimation { self.orphans = CategoryState(items: items, scanned: true) } }
        }
    }

    func toggleOrphan(_ id: String) {
        if let i = orphans.items.firstIndex(where: { $0.id == id }) { orphans.items[i].selected.toggle() }
    }

    func selectAllOrphans(_ on: Bool) {
        orphans.items = orphans.items.map { var x = $0; x.selected = on; return x }
    }

    func cleanOrphans() {
        let items = orphans.selected
        busy = true
        Task.detached(priority: .userInitiated) {
            var done = Set<String>(), freed: Int64 = 0
            for i in items {
                if (try? Uninstaller.trash(i.url, isApp: false)) != nil { done.insert(i.id); freed += i.size }
            }
            await MainActor.run {
                self.busy = false
                withAnimation { self.orphans.items.removeAll { done.contains($0.id) } }
                if !done.isEmpty { self.cleaner?.record(bytes: freed, count: done.count, kinds: [L("应用残留")]) }
                self.cleaner?.show(L("已清理 %@ 个残留文件，%@ 移到了废纸篓", "\(done.count)", "\(Scanner.bytes(freed))")
                                   + (done.count < items.count ? L("；%@ 个没有权限，已跳过", "\(items.count - done.count)") : ""))
                self.cleaner?.scan([.trash])
            }
        }
    }
}
