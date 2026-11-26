import AppKit
import SwiftUI

enum Section: Hashable {
    case home
    case category(CategoryKind)
    case uninstall
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

struct CleanRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let bytes: Int64
    let count: Int
    let kinds: [String]
}

@MainActor
final class CleanerStore: ObservableObject {
    @Published var section: Section = .home
    @Published var states: [CategoryKind: CategoryState] =
        Dictionary(uniqueKeysWithValues: CategoryKind.allCases.map { ($0, CategoryState()) })
    @Published var history: [CleanRecord] = []
    @Published var lastScan: Date?
    @Published var cleaning = false
    @Published var toast: String?
    /// 等待确认的清理 (弹出确认框)
    @Published var pendingClean: [CategoryKind]?
    @Published var hasFullDiskAccess = true

    @Published var deleteDirectly = UserDefaults.standard.bool(forKey: "deleteDirectly") {
        didSet { UserDefaults.standard.set(deleteDirectly, forKey: "deleteDirectly") }
    }
    @Published var largeThresholdMB = UserDefaults.standard.object(forKey: "largeThresholdMB") as? Int ?? 500 {
        didSet { UserDefaults.standard.set(largeThresholdMB, forKey: "largeThresholdMB"); scan([.largeFiles]) }
    }
    @Published var downloadsDays = UserDefaults.standard.object(forKey: "downloadsDays") as? Int ?? 90 {
        didSet { UserDefaults.standard.set(downloadsDays, forKey: "downloadsDays"); scan([.downloads]) }
    }

    init() {
        if let d = UserDefaults.standard.data(forKey: "history"), let h = try? JSONDecoder().decode([CleanRecord].self, from: d) {
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
            var failed = 0
            for (k, item, perm) in jobs {
                do {
                    try Safety.remove(item.url, kind: k, permanent: perm)
                    freed += item.size
                    done.append(item.id)
                } catch {
                    failed += 1
                }
            }
            let movedToTrash = jobs.contains { !$0.2 }
            await self.cleaned(kinds: kinds, removed: Set(done), freed: freed, failed: failed, movedToTrash: movedToTrash)
        }
    }

    private func cleaned(kinds: [CategoryKind], removed: Set<String>, freed: Int64, failed: Int, movedToTrash: Bool) {
        cleaning = false
        withAnimation {
            for k in kinds { states[k]?.items.removeAll { removed.contains($0.id) } }
        }
        if !removed.isEmpty { record(bytes: freed, count: removed.count, kinds: kinds.map(\.longTitle)) }
        var msg = L("已清理 %@ 项，%@", "\(removed.count)", "\(Scanner.bytes(freed))")
        if movedToTrash { msg += L("（在废纸篓里，清空后才真正腾出空间）") }
        if failed > 0 { msg += L("；%@ 项没有权限或正在使用，已跳过", "\(failed)") }
        show(msg)
        // 废纸篓的内容变了, 重新看一下
        if movedToTrash || kinds.contains(.trash) { scan([.trash]) }
    }

    /// 记一笔清理记录 (主页「清理记录」里显示)
    func record(bytes: Int64, count: Int, kinds: [String]) {
        history.insert(CleanRecord(date: Date(), bytes: bytes, count: count, kinds: kinds), at: 0)
        history = Array(history.prefix(50))
        if let d = try? JSONEncoder().encode(history) { UserDefaults.standard.set(d, forKey: "history") }
    }

    func show(_ text: String) {
        withAnimation { toast = text }
        let t = text
        Task {
            try? await Task.sleep(for: .seconds(6))
            if toast == t { withAnimation { toast = nil } }
        }
    }

    /// 切换语言后: 已经扫描过的类别重新扫一遍 (名字、提示用新语言)
    func relocalize() {
        scan(CategoryKind.allCases.filter { state($0).scanned })
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}
