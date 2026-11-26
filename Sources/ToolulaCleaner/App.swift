import AppKit
import SwiftUI

@main
struct ToolulaCleanerApp: App {
    @StateObject private var store = CleanerStore()
    @StateObject private var uninstall = UninstallStore()
    @StateObject private var duplicates = DuplicateStore()
    @StateObject private var startup = StartupStore()
    @StateObject private var diskMap = DiskMapStore()
    /// 界面语言 (改了之后整个界面重画, 菜单栏也跟着变)
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system

    init() {
        // 端到端测试: --fake-home <临时文件夹>  把这个文件夹当成个人文件夹 (scripts/e2e.swift 用).
        // 只接受系统临时目录里的文件夹, 不可能被指到别的地方; 清理记录也存到单独的设置文件里
        if let i = CommandLine.arguments.firstIndex(of: "--fake-home"), i + 1 < CommandLine.arguments.count,
           let real = realpath(CommandLine.arguments[i + 1], nil) {
            let path = String(cString: real)
            free(real)
            let tmp = realpath(NSTemporaryDirectory(), nil).map { p in defer { free(p) }; return String(cString: p) } ?? "/nonexistent"
            guard path.hasPrefix(tmp + "/") else {
                FileHandle.standardError.write(Data("--fake-home 只能用系统临时目录里的文件夹\n".utf8))
                exit(2)
            }
            Scanner.home = URL(fileURLWithPath: path, isDirectory: true)
            CleanerStore.defaults = UserDefaults(suiteName: "com.toolula.cleaner.e2e") ?? .standard
            // 启动项: 只看假个人文件夹里的, 开关也只记在内存里, 不改真实的系统设置
            Startup.systemDirs = []
            Startup.launchctl = FakeLaunchctl.run
        }
        // 命令行自测: ToolulaCleaner --report  只扫描并打印结果, 不删除任何东西
        if CommandLine.arguments.contains("--report") {
            let ctx = ScanContext(running: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
                                  largeThreshold: 500_000_000, downloadsDays: 90)
            for k in CategoryKind.allCases {
                let start = Date()
                let r = Scanner.scan(k, ctx)
                let total = r.items.reduce(0) { $0 + $1.size }
                print("\(k.longTitle): \(r.items.count) 项, \(Scanner.bytes(total)), \(String(format: "%.1f", Date().timeIntervalSince(start)))s \(r.error ?? "")")
                for i in r.items.prefix(4) {
                    print("    \(i.selected ? "☑" : "☐") \(i.name)  \(Scanner.bytes(i.size))  \(i.note ?? "")  safe=\(Safety.allowed(i.url, kind: k))")
                }
            }
            // 卸载: 列应用 / 算大小 / 找残留
            var t = Date()
            let apps = Uninstaller.listApps()
            print(String(format: "应用列表: %d 个, %.2fs", apps.count, Date().timeIntervalSince(t)))
            t = Date()
            let sizes = FastWalker.sizes(apps.map(\.url.path))
            print(String(format: "应用大小: %@, %.2fs", Scanner.bytes(sizes.reduce(0, +)), Date().timeIntervalSince(t)))
            for name in ["Google Chrome", "Claude", "Lightroom Classic"] {
                guard let a = apps.first(where: { $0.name.contains(name) }) else { continue }
                t = Date()
                let l = Uninstaller.leftovers(for: a, others: apps.map(\.bundleID))
                print(String(format: "  %@ (%@): %d 个残留, %@, %.2fs", a.name, a.bundleID, l.count,
                             Scanner.bytes(l.reduce(0) { $0 + $1.size }), Date().timeIntervalSince(t)))
                for i in l.prefix(6) { print("      \(i.detail) / \(i.name)  \(Scanner.bytes(i.size))  safe=\(Uninstaller.allowed(i.url, isApp: false))") }
            }
            t = Date()
            let o = Uninstaller.orphans(installed: apps)
            print(String(format: "已删除应用残留: %d 项, %@, %.2fs", o.count, Scanner.bytes(o.reduce(0) { $0 + $1.size }), Date().timeIntervalSince(t)))
            for i in o.prefix(12) { print("      \(i.name)  \(i.detail)  \(Scanner.bytes(i.size))") }
            t = Date()
            let d = Duplicates.find(minSize: 1_000_000)
            print(String(format: "重复文件: %d 组, 可腾出 %@, %.2fs", d.count, Scanner.bytes(d.reduce(0) { $0 + $1.wasted }), Date().timeIntervalSince(t)))
            for g in d.prefix(5) { print("      \(g.files.count) × \(Scanner.bytes(g.size))  \(g.files.map { Scanner.short($0.url) }.joined(separator: " | "))") }
            t = Date()
            let s = Startup.list()
            print(String(format: "启动项: %d 个, %.2fs", s.count, Date().timeIntervalSince(t)))
            for i in s { print("      [\(i.scope)] \(i.disabled ? "关" : "开") \(i.running ? "运行中" : "") \(i.name) (\(i.label)) \(i.programMissing ? "程序不存在" : "")") }
            t = Date()
            let m = DiskMap.children(of: Scanner.home)
            print(String(format: "空间地图 (个人文件夹): %@, %.2fs", Scanner.bytes(m.reduce(0) { $0 + $1.size }), Date().timeIntervalSince(t)))
            for n in m.prefix(6) { print("      \(n.name)  \(Scanner.bytes(n.size))") }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(language)
                .environment(\.locale, Locale(identifier: AppLanguage.resolved))
                .environmentObject(store)
                .environmentObject(uninstall)
                .environmentObject(duplicates)
                .environmentObject(startup)
                .environmentObject(diskMap)
                .frame(minWidth: 980, minHeight: 560)
                .background(WindowAccessor { WindowSetup.apply(to: $0) })
                .onAppear {
                    AppAppearance.apply(.current)
                    uninstall.cleaner = store
                    duplicates.cleaner = store
                    startup.cleaner = store
                    diskMap.cleaner = store
                    SystemInfo.shared.start()
                    MemoryMonitor.shared.start()
                    store.scan(CategoryKind.quick)
                    // 调试: --section largeFiles 直接打开某一页
                    if let i = CommandLine.arguments.firstIndex(of: "--section"), i + 1 < CommandLine.arguments.count,
                       let arg = Optional(CommandLine.arguments[i + 1]) {
                        if arg == "uninstall" { store.section = .uninstall }
                        else if arg == "memory" { store.section = .memory }
                        else if arg == "startup" { store.section = .startup }
                        else if arg == "duplicates" { store.section = .duplicates }
                        else if arg == "diskMap" { store.section = .diskMap }
                        else if let k = CategoryKind(rawValue: arg) { store.section = .category(k) }
                    }
                }
        }
        .onChange(of: language) {
            // 已经扫描出来的结果和电脑信息里也有文字 (例如「正在运行」「14 核 CPU」), 用新语言重新整理一遍
            store.relocalize()
            uninstall.relocalize()
            SystemInfo.shared.loadHardware()
        }
        .defaultSize(width: WindowSetup.size.width, height: WindowSetup.size.height)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(L("清理")) {
                Button(L("全面扫描")) { store.scan(CategoryKind.full) }.keyboardShortcut("r")
                Button(L("清理所选")) { store.requestClean(CategoryKind.allCases) }.keyboardShortcut(.delete, modifiers: .command)
            }
        }
    }
}

/// Toolula 的品牌绿 (取自变色龙 logo)
extension Color {
    static let toolula = Color(red: 0.29, green: 0.78, blue: 0.52)
}

// MARK: - 白天 / 夜间模式

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return L("跟随系统")
        case .light: return L("白天模式")
        case .dark: return L("夜间模式")
        }
    }
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
    static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
    }
    static func apply(_ a: AppAppearance) {
        UserDefaults.standard.set(a.rawValue, forKey: "appearance")
        switch a {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
