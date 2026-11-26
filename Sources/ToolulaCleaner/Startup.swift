import AppKit
import Foundation
import SwiftUI

/// 一个开机 / 登录时自动启动的后台程序 (launchd 的 LaunchAgent / LaunchDaemon)
struct StartupItem: Identifiable, Hashable, Sendable {
    enum Scope: Int, CaseIterable, Sendable {
        /// ~/Library/LaunchAgents: 只对你自己, 可以开关、可以删除
        case user
        /// /Library/LaunchAgents: 所有用户登录时启动, 可以对你自己关掉
        case global
        /// /Library/LaunchDaemons: 系统后台服务, 要管理员权限, 这里只显示
        case daemon

        var title: String {
            switch self {
            case .user: return L("你的启动项")
            case .global: return L("所有用户的启动项")
            case .daemon: return L("系统后台服务")
            }
        }
        var note: String {
            switch self {
            case .user: return L("登录时为你启动。关掉后不再自动运行，随时可以再打开。")
            case .global: return L("所有用户登录时都会启动。这里关掉只对你自己生效。")
            case .daemon: return L("开机就运行，需要管理员权限才能更改，这里只显示。可以在系统设置的「登录项」里关掉。")
            }
        }
    }

    var id: String { "\(scope.rawValue):\(label)" }
    let label: String
    let plist: URL
    let scope: Scope
    /// 要运行的程序
    let program: String?
    /// 程序所属的应用 (程序在某个 .app 里面时)
    let app: URL?
    var name: String
    var disabled: Bool
    var running: Bool
    /// 程序已经不存在了 (应用删掉了但启动项还在)
    var programMissing: Bool
    var canToggle: Bool { scope != .daemon }
    var canRemove: Bool { scope == .user }
}

enum Startup {
    /// 执行 launchctl (测试和端到端测试时换成假的, 不改动真实的系统设置)
    nonisolated(unsafe) static var launchctl: ([String]) -> (Int32, String) = { SystemInfo.shell("/bin/launchctl", $0) }
    /// 所有用户的启动项和系统后台服务所在的文件夹 (测试时换掉)
    nonisolated(unsafe) static var systemDirs: [(URL, StartupItem.Scope)] = [
        (URL(fileURLWithPath: "/Library/LaunchAgents"), .global),
        (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
    ]
    static var userDir: URL { Scanner.u("Library/LaunchAgents") }
    static var domain: String { "gui/\(getuid())" }

    static func list() -> [StartupItem] {
        let disabled = parseDisabled(launchctl(["print-disabled", domain]).1)
        let running = parseList(launchctl(["list"]).1)
        var items: [StartupItem] = []
        for (dir, scope) in [(userDir, StartupItem.Scope.user)] + systemDirs {
            for f in Scanner.children(dir) where f.pathExtension == "plist" {
                guard var item = parse(f, scope: scope) else { continue }
                if let d = disabled[item.label] { item.disabled = d }
                item.running = running[item.label] ?? false
                items.append(item)
            }
        }
        return items.sorted { ($0.scope.rawValue, $0.name.lowercased()) < ($1.scope.rawValue, $1.name.lowercased()) }
    }

    /// 读一个启动项的 plist
    static func parse(_ url: URL, scope: StartupItem.Scope) -> StartupItem? {
        guard let d = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        let label = d["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
        let program = d["Program"] as? String ?? (d["ProgramArguments"] as? [String])?.first
        let app = program.flatMap(ownerApp)
        var missing = false
        if let program, program.hasPrefix("/") { missing = !FileManager.default.fileExists(atPath: program) }
        return StartupItem(label: label, plist: url, scope: scope, program: program, app: app,
                           name: displayName(label: label, app: app), disabled: d["Disabled"] as? Bool ?? false,
                           running: false, programMissing: missing)
    }

    /// 程序在哪个 .app 里 (取最外层的那个)
    static func ownerApp(_ program: String) -> URL? {
        guard let r = program.range(of: ".app/") ?? (program.hasSuffix(".app") ? program.range(of: ".app") : nil) else { return nil }
        return URL(fileURLWithPath: String(program[..<r.upperBound]).trimmingCharacters(in: CharacterSet(charactersIn: "/")).withSlash)
    }

    static func displayName(label: String, app: URL?) -> String {
        if let app {
            let n = FileManager.default.displayName(atPath: app.path)
            return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
        }
        // com.google.keystone.agent → 找 com.google.keystone 对应的应用
        let parts = label.split(separator: ".")
        if parts.count >= 3 {
            for n in stride(from: parts.count, through: 3, by: -1) {
                if let a = Scanner.appFor(bundleID: parts.prefix(n).joined(separator: ".")) { return a.name }
            }
        }
        return label
    }

    /// `launchctl print-disabled` 的输出 → 标签: 是否关掉
    static func parseDisabled(_ out: String) -> [String: Bool] {
        var r: [String: Bool] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let v = parts[1].trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            r[label] = v == "disabled" || v == "true"
        }
        return r
    }

    /// `launchctl list` 的输出 → 标签: 是否正在运行 (有进程号)
    static func parseList(_ out: String) -> [String: Bool] {
        var r: [String: Bool] = [:]
        for line in out.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            r[String(cols[2])] = Int(cols[0]) != nil
        }
        return r
    }

    /// 打开 / 关掉 (只对你自己的登录会话). 返回出错原因
    static func setEnabled(_ item: StartupItem, _ on: Bool) -> String? {
        guard item.canToggle else { return L("需要管理员权限") }
        let target = "\(domain)/\(item.label)"
        let (code, out) = launchctl([on ? "enable" : "disable", target])
        guard code == 0 else { return out.isEmpty ? L("launchctl 出错（%@）", "\(code)") : out }
        if on {
            _ = launchctl(["bootstrap", domain, item.plist.path])   // 马上启动 (已经在运行时会报错, 不要紧)
        } else {
            _ = launchctl(["bootout", target])                       // 马上停掉
        }
        return nil
    }

    /// 只允许删除你自己的启动项文件夹里的 plist
    static func removable(_ url: URL) -> Bool {
        Safety.normalized(url.deletingLastPathComponent().path) == Safety.normalized(userDir.path) && url.pathExtension == "plist"
    }
}

private extension String {
    var withSlash: String { hasPrefix("/") ? self : "/" + self }
}

@MainActor
final class StartupStore: ObservableObject {
    weak var cleaner: CleanerStore?
    @Published var items: [StartupItem] = []
    @Published var loading = false
    @Published var loaded = false
    @Published var busy: Set<String> = []
    @Published var pendingRemove: StartupItem?

    init() {
        NotificationCenter.default.addObserver(forName: .toolulaUndoFinished, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.loaded == true { self?.load() } }
        }
    }

    var enabledCount: Int { items.filter { !$0.disabled }.count }

    func loadIfNeeded() { if !loaded && !loading { load() } }

    func load() {
        loading = true
        Task.detached(priority: .userInitiated) {
            let list = Startup.list()
            await MainActor.run {
                self.items = list
                self.loading = false
                self.loaded = true
            }
        }
    }

    func setEnabled(_ item: StartupItem, _ on: Bool) {
        busy.insert(item.id)
        Task.detached(priority: .userInitiated) {
            let err = Startup.setEnabled(item, on)
            let fresh = Startup.list()
            await MainActor.run {
                self.busy.remove(item.id)
                self.items = fresh
                if let err {
                    self.cleaner?.report(L("没能更改「%@」", "\(item.name)"), failures: [Failure(path: item.plist.path, reason: err)])
                } else {
                    self.cleaner?.show(on ? L("已打开「%@」", "\(item.name)") : L("已关掉「%@」，下次登录不会再自动运行", "\(item.name)"))
                }
            }
        }
    }

    /// 删除 (移到废纸篓): 只用于你自己的、程序已经不存在的启动项
    func remove(_ item: StartupItem) {
        guard item.canRemove, Startup.removable(item.plist) else { return }
        busy.insert(item.id)
        Task.detached(priority: .userInitiated) {
            _ = Startup.launchctl(["bootout", "\(Startup.domain)/\(item.label)"])
            var moves: [Move] = []
            var failures: [Failure] = []
            do {
                var to: NSURL?
                try FileManager.default.trashItem(at: item.plist, resultingItemURL: &to)
                if let to = to as URL? { moves.append(Move(from: item.plist.path, to: to.path)) }
            } catch {
                failures.append(Failure(path: item.plist.path, error: error))
            }
            let fresh = Startup.list()
            let result = (moves, failures)
            await MainActor.run {
                self.busy.remove(item.id)
                self.items = fresh
                if result.1.isEmpty {
                    let id = self.cleaner?.record(bytes: 0, count: 1, kinds: [L("启动项 %@", "\(item.name)")], moves: result.0)
                    self.cleaner?.report(L("已把「%@」的启动项移到废纸篓", "\(item.name)"), undoID: id)
                } else {
                    self.cleaner?.report(L("没能删除「%@」", "\(item.name)"), failures: result.1)
                }
            }
        }
    }

    func openLoginItemsSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
    }
}

/// 假的 launchctl (端到端测试和单元测试用): 只把开关状态记在内存里
enum FakeLaunchctl {
    nonisolated(unsafe) static var disabled: [String: Bool] = [:]
    nonisolated(unsafe) static var calls: [[String]] = []
    private static let lock = NSLock()

    static func run(_ args: [String]) -> (Int32, String) {
        lock.lock(); defer { lock.unlock() }
        calls.append(args)
        switch args.first {
        case "print-disabled":
            return (0, "disabled services = {\n" + disabled.map { "\t\"\($0.key)\" => \($0.value ? "disabled" : "enabled")" }.joined(separator: "\n") + "\n}")
        case "list": return (0, "PID\tStatus\tLabel\n")
        case "enable", "disable":
            guard args.count > 1, let label = args[1].split(separator: "/").last else { return (1, "bad target") }
            disabled[String(label)] = args[0] == "disable"
            return (0, "")
        default: return (0, "")
        }
    }
}
