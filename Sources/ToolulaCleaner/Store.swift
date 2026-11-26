import AppKit
import SwiftUI

enum Section: Hashable {
    case home
    case category(CategoryKind)
    case uninstall
    case startup
    case duplicates
    case diskMap
    case memory
}

struct CategoryState {
    /// 改动 items 时顺手算好合计, 界面每次重绘不用再遍历几百项
    var items: [CleanItem] = [] { didSet { recount() } }
    var scanned = false
    var scanning = false
    var error: String?
    private(set) var total: Int64 = 0
    private(set) var selectedSize: Int64 = 0
    private(set) var selectedCount = 0
    var selected: [CleanItem] { items.filter(\.selected) }

    init(items: [CleanItem] = [], scanned: Bool = false, scanning: Bool = false, error: String? = nil) {
        self.items = items; self.scanned = scanned; self.scanning = scanning; self.error = error
        recount()
    }

    private mutating func recount() {
        var t: Int64 = 0, s: Int64 = 0, n = 0
        for i in items {
            t += i.size
            if i.selected { s += i.size; n += 1 }
        }
        total = t; selectedSize = s; selectedCount = n
    }
}

/// 一次移动: 原来的位置 → 废纸篓里的位置 (撤销时按这个搬回去)
struct Move: Codable, Hashable, Sendable {
    let from: String
    let to: String
}

/// 没能处理的一项, 以及原因
struct Failure: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let reason: String
    /// 是权限问题 (开启「完全磁盘访问权限」可能解决)
    var needsAccess = false
    var name: String { (path as NSString).lastPathComponent }

    init(path: String, reason: String) { self.path = path; self.reason = reason }
    init(path: String, error: Error) {
        self.path = path
        reason = Safety.reason(error)
        needsAccess = Safety.isPermission(error)
    }
}

struct CleanRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let bytes: Int64
    let count: Int
    let kinds: [String]
    /// 移到废纸篓的项目 (永久删除的没有, 也不能撤销)
    var moves: [Move] = []
    var undone = false

    init(date: Date, bytes: Int64, count: Int, kinds: [String], moves: [Move] = []) {
        self.date = date; self.bytes = bytes; self.count = count; self.kinds = kinds; self.moves = moves
    }

    // 兼容旧版本保存的记录 (没有 moves / undone)
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        bytes = try c.decode(Int64.self, forKey: .bytes)
        count = try c.decode(Int.self, forKey: .count)
        kinds = try c.decode([String].self, forKey: .kinds)
        moves = try c.decodeIfPresent([Move].self, forKey: .moves) ?? []
        undone = try c.decodeIfPresent(Bool.self, forKey: .undone) ?? false
    }

    /// 还能撤销: 没撤销过, 而且至少有一项还在废纸篓里
    var canUndo: Bool { !undone && moves.contains { FileManager.default.fileExists(atPath: $0.to) } }
}

/// 底部弹出的提示, 可以带「撤销」「查看详情」按钮
struct Toast: Equatable {
    let id = UUID()
    let text: String
    var undoID: UUID? = nil
    var hasFailures = false
}

@MainActor
final class CleanerStore: ObservableObject {
    /// 清理记录和清理设置存在这里. 端到端测试 (--fake-home) 时用单独的设置文件, 不混进真实记录
    nonisolated(unsafe) static var defaults = UserDefaults.standard

    @Published var section: Section = .home {
        didSet { if case .category(let k) = section { lastCategory = k } }
    }
    /// 上次看的清理类别 (左侧栏「清理」打开它)
    var lastCategory: CategoryKind = .appCaches
    @Published var states: [CategoryKind: CategoryState] =
        Dictionary(uniqueKeysWithValues: CategoryKind.allCases.map { ($0, CategoryState()) })
    @Published var history: [CleanRecord] = []
    @Published var lastScan: Date?
    @Published var cleaning = false
    @Published var toast: Toast?
    /// 最近一次操作里没能处理的项目 (「查看详情」里列出)
    @Published var failures: [Failure] = []
    @Published var showFailures = false
    /// 等待确认的清理 (弹出确认框)
    @Published var pendingClean: [CategoryKind]?
    @Published var hasFullDiskAccess = true

    @Published var deleteDirectly = CleanerStore.defaults.bool(forKey: "deleteDirectly") {
        didSet { CleanerStore.defaults.set(deleteDirectly, forKey: "deleteDirectly") }
    }
    @Published var largeThresholdMB = CleanerStore.defaults.object(forKey: "largeThresholdMB") as? Int ?? 500 {
        didSet { CleanerStore.defaults.set(largeThresholdMB, forKey: "largeThresholdMB"); scan([.largeFiles]) }
    }
    @Published var downloadsDays = CleanerStore.defaults.object(forKey: "downloadsDays") as? Int ?? 90 {
        didSet { CleanerStore.defaults.set(downloadsDays, forKey: "downloadsDays"); scan([.downloads]) }
    }

    init() {
        if let d = CleanerStore.defaults.data(forKey: "history"), let h = try? JSONDecoder().decode([CleanRecord].self, from: d) {
            history = h
        }
    }

    func state(_ k: CategoryKind) -> CategoryState { states[k] ?? CategoryState() }

    var isScanning: Bool { states.values.contains { $0.scanning } }
    /// 垃圾总量 (不含下载和大文件, 那些是你自己的文件)
    var junkTotal: Int64 { CategoryKind.allCases.filter { !$0.isUserData }.reduce(0) { $0 + state($1).total } }
    var selectedTotal: Int64 { CategoryKind.allCases.reduce(0) { $0 + state($1).selectedSize } }
    var selectedCount: Int { CategoryKind.allCases.reduce(0) { $0 + state($1).selectedCount } }
    var anyScanned: Bool { states.values.contains { $0.scanned } }
    var totalCleaned: Int64 { history.reduce(0) { $0 + $1.bytes } }
    var scanningTitle: String? { CategoryKind.allCases.first { state($0).scanning }?.longTitle }

    // MARK: 扫描

    func checkAccess() {
        hasFullDiskAccess = (try? FileManager.default.contentsOfDirectory(atPath: Scanner.u(".Trash").path)) != nil
    }

    func scan(_ kinds: [CategoryKind]) {
        checkAccess()
        let ctx = ScanContext(running: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
                              largeThreshold: Int64(largeThresholdMB) * 1_000_000,
                              downloadsDays: downloadsDays)
        for k in kinds where !state(k).scanning {
            states[k]?.scanning = true
            Task.detached(priority: .userInitiated) {
                let out = Scanner.scan(k, ctx)
                await self.finish(k, out)
            }
        }
    }

    private func finish(_ k: CategoryKind, _ out: ScanOutput) {
        withAnimation(.easeOut(duration: 0.25)) {
            states[k] = CategoryState(items: out.items, scanned: true, scanning: false, error: out.error)
        }
        if !isScanning { lastScan = Date() }
    }

    // MARK: 勾选

    func toggle(_ k: CategoryKind, _ id: String) {
        guard let i = states[k]?.items.firstIndex(where: { $0.id == id }) else { return }
        states[k]?.items[i].selected.toggle()
    }

    func selectAll(_ k: CategoryKind, _ on: Bool) {
        guard let items = states[k]?.items else { return }
        states[k]?.items = items.map { var x = $0; x.selected = on; return x }   // 一次赋值, 只重算一次合计
    }

    // MARK: 清理

    /// 是否永久删除: 废纸篓总是永久; 你自己的文件永远只移到废纸篓
    func permanent(_ k: CategoryKind) -> Bool { k == .trash || (deleteDirectly && !k.isUserData) }

    func requestClean(_ kinds: [CategoryKind]) {
        let ks = kinds.filter { state($0).selectedCount > 0 }
        guard !ks.isEmpty, !cleaning else { return }
        pendingClean = ks
    }

    func confirmText(_ kinds: [CategoryKind]) -> String {
        let items = kinds.flatMap { state($0).selected }
        let size = Scanner.bytes(items.reduce(0) { $0 + $1.size })
        let perm = kinds.filter { permanent($0) }
        let soft = kinds.filter { !permanent($0) }
        var parts: [String] = []
        if !soft.isEmpty { parts.append(L("移到废纸篓：%@", soft.map(\.longTitle).joined(separator: L("、")))) }
        if !perm.isEmpty { parts.append(L("永久删除（无法恢复）：%@", perm.map(\.longTitle).joined(separator: L("、")))) }
        return L("共 %@ 项，%@\n", "\(items.count)", "\(size)") + parts.joined(separator: "\n")
    }

    func clean(_ kinds: [CategoryKind]) {
        let jobs = kinds.flatMap { k in state(k).selected.map { (k, $0, permanent(k)) } }
        guard !jobs.isEmpty else { return }
        cleaning = true
        Task.detached(priority: .userInitiated) {
            var freed: Int64 = 0
            var done: [String] = []
            var moves: [Move] = []
            var failures: [Failure] = []
            for (k, item, perm) in jobs {
                do {
                    if let to = try Safety.remove(item.url, kind: k, permanent: perm) {
                        moves.append(Move(from: item.url.path, to: to.path))
                    }
                    freed += item.size
                    done.append(item.id)
                } catch {
                    failures.append(Failure(path: item.url.path, error: error))
                }
            }
            let result = (freed, done, moves, failures)
            await MainActor.run {
                self.cleaned(kinds: kinds, removed: Set(result.1), freed: result.0, moves: result.2, failures: result.3)
            }
        }
    }

    private func cleaned(kinds: [CategoryKind], removed: Set<String>, freed: Int64, moves: [Move], failures: [Failure]) {
        cleaning = false
        withAnimation {
            for k in kinds { states[k]?.items.removeAll { removed.contains($0.id) } }
        }
        var undoID: UUID?
        if !removed.isEmpty { undoID = record(bytes: freed, count: removed.count, kinds: kinds.map(\.longTitle), moves: moves) }
        var msg = L("已清理 %@ 项，%@", "\(removed.count)", "\(Scanner.bytes(freed))")
        if !moves.isEmpty { msg += L("（在废纸篓里，清空后才真正腾出空间）") }
        if !failures.isEmpty { msg += L("；%@ 项没能处理", "\(failures.count)") }
        report(msg, undoID: moves.isEmpty ? nil : undoID, failures: failures)
        // 废纸篓的内容变了, 重新看一下
        if !moves.isEmpty || kinds.contains(.trash) { scan([.trash]) }
    }

    /// 记一笔清理记录 (主页「清理记录」里显示), 返回它的 ID (撤销用)
    @discardableResult
    func record(bytes: Int64, count: Int, kinds: [String], moves: [Move] = []) -> UUID {
        let r = CleanRecord(date: Date(), bytes: bytes, count: count, kinds: kinds, moves: moves)
        history.insert(r, at: 0)
        history = Array(history.prefix(50))
        saveHistory()
        return r.id
    }

    private func saveHistory() {
        if let d = try? JSONEncoder().encode(history) { CleanerStore.defaults.set(d, forKey: "history") }
    }

    func show(_ text: String) { report(text) }

    /// 显示结果提示. 有撤销 / 失败时多停留一会儿
    func report(_ text: String, undoID: UUID? = nil, failures: [Failure] = []) {
        self.failures = failures
        let t = Toast(text: text, undoID: undoID, hasFailures: !failures.isEmpty)
        withAnimation { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(undoID != nil || !failures.isEmpty ? 12 : 6))
            if toast == t { withAnimation { toast = nil } }
        }
    }

    // MARK: 撤销

    /// 把一次清理 / 卸载移到废纸篓的东西全部放回原处.
    /// 原来的位置已经有同名的东西 (例如应用已经重新生成了缓存) 时跳过, 并说明原因
    func undo(_ id: UUID, then: (@MainActor () -> Void)? = nil) {
        guard let rec = history.first(where: { $0.id == id }), !rec.undone else { return }
        withAnimation { toast = nil }
        Task.detached(priority: .userInitiated) {
            let r = Self.restore(rec.moves)
            await MainActor.run {
                if let i = self.history.firstIndex(where: { $0.id == id }) {
                    self.history[i].undone = true
                    self.saveHistory()
                }
                var msg = L("已放回 %@ 项", "\(r.restored)")
                if !r.failures.isEmpty { msg += L("；%@ 项没能处理", "\(r.failures.count)") }
                self.report(msg, failures: r.failures)
                self.scan(CategoryKind.allCases.filter { self.state($0).scanned })
                NotificationCenter.default.post(name: .toolulaUndoFinished, object: nil)
                then?()
            }
        }
    }

    /// 真正搬回去 (测试也直接调用这个)
    nonisolated static func restore(_ moves: [Move]) -> (restored: Int, failures: [Failure]) {
        let fm = FileManager.default
        var restored = 0
        var failures: [Failure] = []
        for m in moves {
            guard fm.fileExists(atPath: m.to) else {
                failures.append(Failure(path: m.from, reason: L("已经不在废纸篓里了"))); continue
            }
            guard !fm.fileExists(atPath: m.from) else {
                failures.append(Failure(path: m.from, reason: L("原来的位置已经有同名的东西（可能已经重新生成）"))); continue
            }
            do {
                try fm.createDirectory(at: URL(fileURLWithPath: m.from).deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(atPath: m.to, toPath: m.from)
                restored += 1
            } catch {
                failures.append(Failure(path: m.from, error: error))
            }
        }
        return (restored, failures)
    }

    /// 切换语言后: 已经扫描过的类别重新扫一遍 (名字、提示用新语言)
    func relocalize() {
        scan(CategoryKind.allCases.filter { state($0).scanned })
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}

extension Notification.Name {
    /// 撤销完成 (卸载页面收到后刷新应用列表)
    static let toolulaUndoFinished = Notification.Name("ToolulaUndoFinished")
}
