import AppKit
import Foundation

/// 清理的类别 (左侧栏每一项)
enum CategoryKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case appCaches, logs, developer, projects, browser, downloads, trash, largeFiles
    var id: String { rawValue }

    /// 左侧栏用的短名字
    var title: String {
        switch self {
        case .appCaches: return L("应用缓存")
        case .logs: return L("日志")
        case .developer: return L("开发者")
        case .projects: return L("项目")
        case .browser: return L("浏览器")
        case .downloads: return L("下载")
        case .trash: return L("废纸篓")
        case .largeFiles: return L("大文件")
        }
    }

    var longTitle: String {
        switch self {
        case .appCaches: return L("应用缓存")
        case .logs: return L("日志与崩溃报告")
        case .developer: return L("开发者垃圾")
        case .projects: return L("开发项目里的垃圾")
        case .browser: return L("浏览器缓存")
        case .downloads: return L("下载里的旧文件")
        case .trash: return L("废纸篓")
        case .largeFiles: return L("大文件")
        }
    }

    var icon: String {
        switch self {
        case .appCaches: return "archivebox"
        case .logs: return "doc.text.magnifyingglass"
        case .developer: return "hammer"
        case .projects: return "shippingbox"
        case .browser: return "safari"
        case .downloads: return "arrow.down.circle"
        case .trash: return "trash"
        case .largeFiles: return "square.stack.3d.up"
        }
    }

    var desc: String {
        switch self {
        case .appCaches: return L("应用为加速保存的临时文件，删了会自动重新生成")
        case .logs: return L("应用日志和崩溃报告，只用来排查问题")
        case .developer: return L("Xcode 编译缓存、模拟器缓存、Homebrew / npm / pip 等下载缓存")
        case .projects: return L("项目里的 node_modules、.venv、target、build 等文件夹，需要时能重新安装、重新编译")
        case .browser: return L("Safari、Chrome、Edge 等浏览器的网页缓存，不动书签和密码")
        case .downloads: return L("下载文件夹里很久没碰过的文件，需要你自己挑")
        case .trash: return L("清空废纸篓，才会真正腾出空间")
        case .largeFiles: return L("找出个人文件夹里占地方的大文件")
        }
    }

    /// 页面顶部的提示
    var notice: String {
        switch self {
        case .appCaches: return L("缓存删掉后应用会自动重新生成。正在运行的应用已自动取消勾选。")
        case .logs: return L("日志和崩溃报告只用来排查问题，可以放心清理。")
        case .developer: return L("删除后下次编译或安装会重新生成、重新下载。Xcode 归档里是你打包过的版本，默认不勾选。")
        case .projects: return L("只列出能重新生成的依赖包和编译产物，不动源代码。超过 30 天没改过的项目默认勾选。")
        case .browser: return L("只清理网页缓存，不会动书签、密码、历史记录和登录状态。正在运行的浏览器需要先退出。")
        case .downloads: return L("这些是你自己下载的文件，默认都不勾选，请看清楚再选。删除的文件会移到废纸篓。")
        case .trash: return L("清空后无法恢复，请确认里面没有还要用的东西。")
        case .largeFiles: return L("只找个人文件夹里的文件（不含资源库、隐藏文件夹和 Toolula 数据）。默认不勾选，删除的文件会移到废纸篓。")
        }
    }

    /// 是你自己的文件 (默认不勾选, 永远只移到废纸篓)
    var isUserData: Bool { self == .downloads || self == .largeFiles }
    /// 打开 App 时自动扫描的类别 (不会弹出文件夹访问授权)
    static let quick: [CategoryKind] = [.appCaches, .logs, .developer, .browser, .trash]
    /// 「全面扫描」的类别 (大文件扫描较慢, 进入它的页面才扫)
    static let full: [CategoryKind] = [.appCaches, .logs, .developer, .projects, .browser, .downloads, .trash]
}

/// 可以清理的一项 (一个文件或文件夹)
struct CleanItem: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    var detail: String
    let size: Int64
    var selected: Bool
    var note: String? = nil
    /// 用这个路径取图标 (例如缓存对应的应用)
    var iconPath: String? = nil
}

struct ScanContext: Sendable {
    var running: Set<String>
    var largeThreshold: Int64
    var downloadsDays: Int
}

struct ScanOutput: Sendable {
    var items: [CleanItem] = []
    var error: String? = nil
}

enum Scanner {
    /// 个人文件夹. 测试时换成一个临时文件夹, 这样测试永远不会碰到真实的文件
    static var home = FileManager.default.homeDirectoryForCurrentUser
    static func u(_ p: String) -> URL { home.appendingPathComponent(p) }

    /// 浏览器缓存: (缓存文件夹, 名字, 应用 ID)
    static let browsers: [(String, String, String)] = [
        ("Library/Caches/com.apple.Safari", "Safari", "com.apple.Safari"),
        ("Library/Caches/Google/Chrome", "Google Chrome", "com.google.Chrome"),
        ("Library/Caches/Microsoft Edge", "Microsoft Edge", "com.microsoft.edgemac"),
        ("Library/Caches/Firefox", "Firefox", "org.mozilla.firefox"),
        ("Library/Caches/BraveSoftware", "Brave", "com.brave.Browser"),
        ("Library/Caches/Arc", "Arc", "company.thebrowser.Browser"),
    ]

    /// 开发者缓存 (每次现算: 切换语言后名字跟着变): (路径, 名字, 默认勾选)
    static var devItems: [(String, String, Bool)] { [
        ("Library/Developer/Xcode/Archives", L("Xcode 归档（打包过的版本）"), false),
        ("Library/Developer/CoreSimulator/Caches", L("模拟器缓存"), true),
        ("Library/Caches/com.apple.dt.Xcode", L("Xcode 缓存"), true),
        ("Library/Caches/Homebrew", L("Homebrew 下载缓存"), true),
        (".npm/_cacache", L("npm 缓存"), true),
        ("Library/Caches/Yarn", L("Yarn 缓存"), true),
        ("Library/Caches/pip", L("pip 缓存"), true),
        ("Library/Caches/CocoaPods", L("CocoaPods 缓存"), true),
        ("Library/Caches/org.swift.swiftpm", L("Swift Package 缓存"), true),
        ("Library/Caches/go-build", L("Go 编译缓存"), true),
        (".gradle/caches", L("Gradle 缓存"), true),
        (".cargo/registry/cache", L("Cargo 下载缓存"), true),
    ] }

    /// 「应用缓存」里不算的文件夹 (在浏览器 / 开发者里单独列出, 或属于本 App)
    static var excludedCacheNames: Set<String> {
        var s: Set<String> = ["Google", "com.google.Chrome", "com.microsoft.edgemac", "org.mozilla.firefox",
                              "com.brave.Browser", "company.thebrowser.Browser", "com.toolula.cleaner"]
        for (p, _, _) in browsers + devItems.map({ ($0.0, $0.1, "") }) where p.hasPrefix("Library/Caches/") {
            s.insert(String(p.dropFirst("Library/Caches/".count).split(separator: "/").first ?? ""))
        }
        return s
    }

    static func scan(_ kind: CategoryKind, _ ctx: ScanContext) -> ScanOutput {
        var r: ScanOutput
        switch kind {
        case .appCaches: r = appCaches(ctx)
        case .logs: r = ScanOutput(items: items(children(u("Library/Logs")).map { Candidate(url: $0, selected: true) }))
        case .developer: r = developer(ctx)
        case .projects: r = ProjectJunk.scan()
        case .browser: r = browser(ctx)
        case .downloads: r = downloads(ctx)
        case .trash: r = trash()
        case .largeFiles: r = largeFiles(ctx)
        }
        r.items.sort { $0.size > $1.size }
        return r
    }

    // MARK: 各类别

    static func appCaches(_ ctx: ScanContext) -> ScanOutput {
        let excluded = excludedCacheNames
        let dirs = children(u("Library/Caches")).filter { !excluded.contains($0.lastPathComponent) }
        // 查应用名字 (LaunchServices) 也并行做
        var cands = [Candidate?](repeating: nil, count: dirs.count)
        cands.withUnsafeMutableBufferPointer { out in
            DispatchQueue.concurrentPerform(iterations: dirs.count) { i in
                let c = dirs[i], n = c.lastPathComponent
                let app = appFor(bundleID: n)
                let running = ctx.running.contains(n)
                out[i] = Candidate(url: c, name: n.hasPrefix("com.apple.SwiftUI.Drag-") ? L("拖放产生的临时文件") : app?.name,
                                   selected: !running, note: running ? L("正在运行") : nil, iconPath: app?.path)
            }
        }
        return ScanOutput(items: items(cands.compactMap { $0 }))
    }

    static func developer(_ ctx: ScanContext) -> ScanOutput {
        let xcodeRunning = ctx.running.contains("com.apple.dt.Xcode")
        let xcode = appFor(bundleID: "com.apple.dt.Xcode")?.path
        var cands: [Candidate] = []
        for c in children(u("Library/Developer/Xcode/DerivedData")) {
            let proj = c.lastPathComponent.split(separator: "-").dropLast().joined(separator: "-")
            cands.append(Candidate(url: c, name: L("Xcode 编译缓存 · %@", proj.isEmpty ? c.lastPathComponent : proj),
                                   selected: !xcodeRunning, note: xcodeRunning ? L("Xcode 正在运行") : nil, iconPath: xcode))
        }
        for platform in ["iOS", "watchOS", "tvOS", "visionOS"] {
            for c in children(u("Library/Developer/Xcode/\(platform) DeviceSupport")) {
                cands.append(Candidate(url: c, name: L("%@ 设备调试文件 · %@", "\(platform)", "\(c.lastPathComponent)"), selected: true, iconPath: xcode))
            }
        }
        for (p, name, sel) in devItems where FileManager.default.fileExists(atPath: u(p).path) {
            cands.append(Candidate(url: u(p), name: name, selected: sel))
        }
        return ScanOutput(items: items(cands))
    }

    static func browser(_ ctx: ScanContext) -> ScanOutput {
        let cands = browsers.filter { FileManager.default.fileExists(atPath: u($0.0).path) }.map { p, name, id in
            let running = ctx.running.contains(id)
            return Candidate(url: u(p), name: name, selected: !running, note: running ? L("正在运行，先退出") : nil,
                             iconPath: appFor(bundleID: id)?.path)
        }
        return ScanOutput(items: items(cands))
    }

    static func downloads(_ ctx: ScanContext) -> ScanOutput {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .addedToDirectoryDateKey]
        guard let list = try? FileManager.default.contentsOfDirectory(at: u("Downloads"), includingPropertiesForKeys: Array(keys)) else {
            return ScanOutput(error: L("没有权限读取下载文件夹。请在「系统设置 › 隐私与安全性 › 文件与文件夹」里允许 Toolula Tidy。"))
        }
        let cutoff = Date().addingTimeInterval(-Double(ctx.downloadsDays) * 86400)
        let cands = list.filter { !$0.lastPathComponent.hasPrefix(".") }.compactMap { f -> Candidate? in
            let v = try? f.resourceValues(forKeys: keys)
            let last = [v?.contentModificationDate, v?.addedToDirectoryDate].compactMap { $0 }.max() ?? .distantPast
            guard last < cutoff else { return nil }
            return Candidate(url: f, selected: false, detail: L("%@ 天前 · %@", "\(Int(Date().timeIntervalSince(last) / 86400))", "\(short(f))"))
        }
        return ScanOutput(items: items(cands))
    }

    static func trash() -> ScanOutput {
        guard let list = try? FileManager.default.contentsOfDirectory(at: u(".Trash"), includingPropertiesForKeys: nil) else {
            return ScanOutput(error: L("需要「完全磁盘访问权限」才能查看和清空废纸篓。"))
        }
        return ScanOutput(items: items(list.filter { $0.lastPathComponent != ".DS_Store" }
            .map { Candidate(url: $0, selected: true, detail: L("废纸篓")) }))
    }

    /// 当成一个整体、不拆开看的「包」(照片图库、App、工程文件等)
    static let packageExts: Set<String> = ["app", "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle",
                                           "logicx", "band", "bundle", "framework", "xcarchive", "plugin", "kext", "lrlibrary",
                                           "lrdata", "photolibrary", "aplibrary", "migratedphotolibrary", "xcodeproj", "xcworkspace",
                                           "pages", "numbers", "key", "rtfd", "sparsebundle", "dSYM"]

    static func largeFiles(_ ctx: ScanContext) -> ScanOutput {
        let roots = personalRoots()
        let found = Locked<[(String, Int64)]>([])
        var opts = FastWalker.Options()
        opts.skipHidden = true
        opts.skipDir = { name, _, _ in isPackage(name) }
        opts.fileThreshold = ctx.largeThreshold
        opts.onFile = { _, path, size in
            found.mutate { $0.append((path, size)) }
        }
        _ = FastWalker.sizes(roots.map(\.path), options: opts)

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let items = found.value.sorted { $0.1 > $1.1 }.prefix(300).map { path, size -> CleanItem in
            let f = URL(fileURLWithPath: path)
            let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate.map { df.string(from: $0) } ?? ""
            return CleanItem(url: f, name: f.lastPathComponent, detail: "\(date) · \(short(f.deletingLastPathComponent()))",
                             size: size, selected: false, note: modelExts.contains(f.pathExtension.lowercased()) ? L("AI 模型") : nil)
        }
        return ScanOutput(items: items)
    }

    /// 个人文件夹里「你自己的文件」所在的第一层文件夹.
    /// 不含: 资源库 (应用数据)、Toolula AI 的数据和模型、应用程序、隐藏文件夹
    static func personalRoots() -> [URL] {
        let skipTop: Set<String> = ["Library", "Toolula", "Applications"]
        return children(home).filter { !$0.lastPathComponent.hasPrefix(".") && !skipTop.contains($0.lastPathComponent) }
    }

    static func isPackage(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        return packageExts.contains(String(name[name.index(after: dot)...]))
    }

    /// AI 模型文件 (可能正在被 Toolula AI / ComfyUI 使用, 标出来提醒)
    static let modelExts: Set<String> = ["safetensors", "gguf", "ckpt", "pth", "pt", "onnx", "mlpackage", "npz"]

    // MARK: 工具

    /// 还没算大小的候选项
    struct Candidate {
        let url: URL
        var name: String? = nil
        var selected: Bool
        var detail: String? = nil
        var note: String? = nil
        var iconPath: String? = nil
    }

    /// 一次性并行算出所有候选项的大小, 去掉空的
    static func items(_ cands: [Candidate]) -> [CleanItem] {
        let sizes = FastWalker.sizes(cands.map(\.url.path))
        return zip(cands, sizes).compactMap { c, size in
            guard size > 0 else { return nil }
            return CleanItem(url: c.url, name: c.name ?? c.url.lastPathComponent, detail: c.detail ?? short(c.url),
                             size: size, selected: c.selected, note: c.note, iconPath: c.iconPath)
        }
    }

    static func children(_ url: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent != ".DS_Store" }
    }

    /// 实际占用的磁盘空间 (文件夹递归计算, 不跟随链接, 硬链接只算一次)
    static func allocatedSize(_ url: URL) -> Int64 { FastWalker.size(url.path) }

    /// 缓存文件夹名是应用 ID 时, 找到对应的应用名字和位置
    static func appFor(bundleID: String) -> (name: String, path: String)? {
        guard bundleID.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return (name.hasSuffix(".app") ? String(name.dropLast(4)) : name, url.path)
    }

    static func short(_ url: URL) -> String {
        let p = url.path
        return p.hasPrefix(home.path) ? "~" + p.dropFirst(home.path.count) : p
    }

    static func bytes(_ b: Int64) -> String {
        let d = Double(b)
        if d < 1e3 { return "\(b) B" }
        if d < 1e6 { return String(format: "%.0f KB", locale: .current, d / 1e3) }
        if d < 1e8 { return String(format: "%.1f MB", locale: .current, d / 1e6) }
        if d < 1e9 { return String(format: "%.0f MB", locale: .current, d / 1e6) }
        return String(format: "%.2f GB", locale: .current, d / 1e9)
    }
}

/// 删除前的最后一道保险: 只允许删除这些文件夹 *里面* 的东西
enum Safety {
    static var roots: [String] { ["Library/Caches", "Library/Logs", "Library/Developer/Xcode", "Library/Developer/CoreSimulator/Caches",
                        ".npm/_cacache", ".gradle/caches", ".cargo/registry/cache", ".Trash", "Downloads"]
        .map { Scanner.home.appendingPathComponent($0).path } }

    /// 只处理 "." 和 "..", 不做别的 (系统的 standardizedFileURL 会悄悄去掉 /private, 两边写法就对不上了)
    static func normalized(_ path: String) -> String {
        var out: [Substring] = []
        for c in path.split(separator: "/") {
            if c == "." { continue }
            if c == ".." { if !out.isEmpty { out.removeLast() }; continue }
            out.append(c)
        }
        return "/" + out.joined(separator: "/")
    }

    static func allowed(_ url: URL, kind: CategoryKind) -> Bool {
        let p = normalized(url.path)
        let home = normalized(Scanner.home.path)
        if kind == .largeFiles {
            return p.hasPrefix(home + "/") && !p.hasPrefix(home + "/Library/") && !p.hasPrefix(home + "/Toolula/")
                && p.split(separator: "/").count > home.split(separator: "/").count + 1
        }
        if kind == .projects { return ProjectJunk.allowed(p, home: home) }
        // 开发者里的整个缓存文件夹 (例如 ~/.npm/_cacache) 本身也可以删
        if kind == .developer, Scanner.devItems.contains(where: { normalized(Scanner.u($0.0).path) == p }) { return true }
        return roots.contains { p.hasPrefix(normalized($0) + "/") }
    }

    /// 删除一项. 移到废纸篓时返回它在废纸篓里的位置 (用来撤销), 永久删除返回 nil
    @discardableResult
    static func remove(_ url: URL, kind: CategoryKind, permanent: Bool) throws -> URL? {
        guard allowed(url, kind: kind) else {
            throw NSError(domain: "ToolulaCleaner", code: 1, userInfo: [NSLocalizedDescriptionKey: L("不在允许清理的位置：%@", "\(url.path)")])
        }
        if permanent {
            try FileManager.default.removeItem(at: url)
            return nil
        }
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }

    /// 是不是权限问题
    static func isPermission(_ error: Error) -> Bool {
        let ns = error as NSError
        let posix = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? $0.code : nil }
            ?? (ns.domain == NSPOSIXErrorDomain ? ns.code : nil)
        return posix == Int(EPERM) || posix == Int(EACCES)
            || (ns.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code))
    }

    /// 把系统的错误变成一句看得懂的原因
    static func reason(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == "ToolulaCleaner" { return ns.localizedDescription }
        let posix = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? $0.code : nil }
            ?? (ns.domain == NSPOSIXErrorDomain ? ns.code : nil)
        if ns.domain == NSCocoaErrorDomain, [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(ns.code) || posix == Int(ENOENT) {
            return L("文件已经不存在了")
        }
        if posix == Int(EBUSY) { return L("正在被使用") }
        if posix == Int(EPERM) || posix == Int(EACCES)
            || (ns.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code)) {
            return L("没有权限（可能需要「完全磁盘访问权限」，或者是系统保护的文件）")
        }
        return ns.localizedDescription
    }
}
