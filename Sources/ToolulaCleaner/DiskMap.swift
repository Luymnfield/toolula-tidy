import AppKit
import Foundation
import SwiftUI

/// 空间地图里的一块: 一个文件或文件夹
struct MapNode: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let size: Int64
    let isDir: Bool
    /// 把很多小东西合成一块「其他」时, 合了几项
    var others = 0
}

enum DiskMap {
    /// 一个文件夹里每一项的实际占用, 从大到小 (包括隐藏的文件和文件夹)
    static func children(of url: URL) -> [MapNode] { twoLevels(of: url).0 }

    /// 一次遍历同时算出这一层和下一层: 点进子文件夹时马上就能显示, 不用再等
    static func twoLevels(of url: URL) -> ([MapNode], [String: [MapNode]]) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        func entries(_ u: URL) -> [(URL, Bool)] {
            ((try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: keys)) ?? []).map { e in
                let v = try? e.resourceValues(forKeys: Set(keys))
                return (e, v?.isDirectory == true && v?.isSymbolicLink != true && !Scanner.isPackage(e.lastPathComponent))
            }
        }
        let top = entries(url)
        // 子文件夹展开成它里面的每一项, 一起交给 FastWalker
        var subs: [[(URL, Bool)]] = []
        var paths: [String] = []
        for (u, dir) in top {
            let inner = dir ? entries(u) : []
            subs.append(inner)
            paths += dir ? inner.map(\.0.path) : [u.path]
        }
        let sizes = FastWalker.sizes(paths)
        var k = 0
        var nodes: [MapNode] = []
        var next: [String: [MapNode]] = [:]
        for (i, (u, dir)) in top.enumerated() {
            if dir {
                var list: [MapNode] = []
                for (cu, cdir) in subs[i] {
                    if sizes[k] > 0 { list.append(MapNode(url: cu, name: fm.displayName(atPath: cu.path), size: sizes[k], isDir: cdir)) }
                    k += 1
                }
                list.sort { $0.size > $1.size }
                next[u.path] = list
                let total = list.reduce(0) { $0 + $1.size }
                if total > 0 { nodes.append(MapNode(url: u, name: fm.displayName(atPath: u.path), size: total, isDir: true)) }
            } else {
                if sizes[k] > 0 { nodes.append(MapNode(url: u, name: fm.displayName(atPath: u.path), size: sizes[k], isDir: false)) }
                k += 1
            }
        }
        return (nodes.sorted { $0.size > $1.size }, next)
    }

    /// 地图上最多画多少块; 再小的合成一块「其他」
    static func forMap(_ nodes: [MapNode], max: Int = 40) -> [MapNode] {
        let total = nodes.reduce(0) { $0 + $1.size }
        var shown: [MapNode] = []
        var rest: Int64 = 0, restCount = 0
        for n in nodes {
            // 小于整体 0.4% 的块太小, 看不清也点不中
            if shown.count < max && (Double(n.size) >= Double(total) * 0.004 || shown.isEmpty) { shown.append(n) }
            else { rest += n.size; restCount += 1 }
        }
        if restCount == 1, let last = nodes.last { shown.append(last) }
        else if restCount > 1 {
            shown.append(MapNode(url: URL(fileURLWithPath: "/__others__"), name: L("其他 %@ 项", "\(restCount)"), size: rest, isDir: false, others: restCount))
        }
        return shown
    }

    /// 方块图排版 (squarified treemap): 每块面积和大小成正比, 尽量接近正方形.
    /// sizes 要从大到小排好
    static func layout(_ sizes: [Double], in rect: CGRect) -> [CGRect] {
        var out = [CGRect](repeating: .zero, count: sizes.count)
        let total = sizes.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return out }
        let scale = Double(rect.width * rect.height) / total
        let area = sizes.map { $0 * scale }
        var r = rect
        var i = 0
        while i < area.count {
            let side = Double(min(r.width, r.height))
            // 找一行: 再加一块会让这一行的方块更扁时就停
            var row = [i]
            var rowSum = area[i]
            func worst(_ sum: Double, _ lo: Double, _ hi: Double) -> Double {
                let s2 = side * side, sum2 = sum * sum
                return Swift.max(s2 * hi / sum2, sum2 / (s2 * Swift.max(lo, 1e-9)))
            }
            var lo = area[i], hi = area[i]
            while i + row.count < area.count {
                let next = area[i + row.count]
                let nlo = Swift.min(lo, next), nhi = Swift.max(hi, next)
                if worst(rowSum + next, nlo, nhi) > worst(rowSum, lo, hi) { break }
                row.append(i + row.count); rowSum += next; lo = nlo; hi = nhi
            }
            // 把这一行放在短边上
            let thick = CGFloat(rowSum / side)
            var offset: CGFloat = 0
            for j in row {
                let len = CGFloat(area[j] / Double(thick))
                if r.width >= r.height {
                    out[j] = CGRect(x: r.minX, y: r.minY + offset, width: thick, height: len)
                } else {
                    out[j] = CGRect(x: r.minX + offset, y: r.minY, width: len, height: thick)
                }
                offset += len
            }
            if r.width >= r.height { r = CGRect(x: r.minX + thick, y: r.minY, width: r.width - thick, height: r.height) }
            else { r = CGRect(x: r.minX, y: r.minY + thick, width: r.width, height: r.height - thick) }
            i += row.count
        }
        return out
    }
}

@MainActor
final class DiskMapStore: ObservableObject {
    weak var cleaner: CleanerStore?
    /// 从个人文件夹一路点进来的路径
    @Published var trail: [URL] = []
    @Published var nodes: [MapNode] = []
    @Published var loading = false
    @Published var pendingTrash: MapNode?
    private var cache: [String: [MapNode]] = [:]

    init() {
        NotificationCenter.default.addObserver(forName: .toolulaUndoFinished, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.trail.isEmpty else { return }
                self.cache.removeAll()
                self.load(self.current)
            }
        }
    }

    var current: URL { trail.last ?? Scanner.home }
    var total: Int64 { nodes.reduce(0) { $0 + $1.size } }

    func start() {
        if trail.isEmpty { trail = [Scanner.home]; load(Scanner.home) }
    }

    func open(_ n: MapNode) {
        guard n.isDir, n.others == 0 else { return }
        trail.append(n.url)
        load(n.url)
    }

    func back(to index: Int) {
        guard index < trail.count else { return }
        trail = Array(trail.prefix(index + 1))
        load(current)
    }

    func refresh() {
        cache.removeAll()
        prefetched.removeAll()
        load(current)
    }

    private func load(_ url: URL) {
        if let c = cache[url.path] {
            nodes = c
            loading = false
            prefetch(url)
            return
        }
        loading = true
        Task.detached(priority: .userInitiated) {
            let (list, next) = DiskMap.twoLevels(of: url)
            await MainActor.run {
                self.cache[url.path] = list
                for (k, v) in next where self.cache[k] == nil { self.cache[k] = v }
                guard self.current == url else { return }   // 已经点到别处了
                withAnimation(.easeOut(duration: 0.2)) { self.nodes = list }
                self.loading = false
            }
        }
    }

    /// 显示的是缓存里的一层时, 在后台把它的下一层也准备好
    private var prefetched = Set<String>()
    private func prefetch(_ url: URL) {
        guard prefetched.insert(url.path).inserted else { return }
        let dirs = (cache[url.path] ?? []).filter { $0.isDir && cache[$0.url.path] == nil }.prefix(12).map(\.url)
        guard !dirs.isEmpty else { return }
        Task.detached(priority: .utility) {
            var found: [String: [MapNode]] = [:]
            for d in dirs { found[d.path] = DiskMap.children(of: d) }
            let result = found
            await MainActor.run { for (k, v) in result where self.cache[k] == nil { self.cache[k] = v } }
        }
    }

    /// 可以从空间地图里直接移到废纸篓的: 和「大文件」一样, 只限个人文件夹里你自己的文件
    func canTrash(_ n: MapNode) -> Bool { n.others == 0 && Safety.allowed(n.url, kind: .largeFiles) }

    func trash(_ n: MapNode) {
        guard canTrash(n) else { return }
        Task.detached(priority: .userInitiated) {
            var moves: [Move] = []
            var failures: [Failure] = []
            do {
                if let to = try Safety.remove(n.url, kind: .largeFiles, permanent: false) { moves.append(Move(from: n.url.path, to: to.path)) }
            } catch {
                failures.append(Failure(path: n.url.path, error: error))
            }
            let result = (moves, failures)
            await MainActor.run {
                if result.1.isEmpty {
                    // 这一层和上面每一层的大小都变了
                    self.cache.removeAll()
                    self.prefetched.removeAll()
                    withAnimation { self.nodes.removeAll { $0.id == n.id } }
                    let id = self.cleaner?.record(bytes: n.size, count: 1, kinds: [L("空间地图")], moves: result.0)
                    self.cleaner?.report(L("已把「%@」移到废纸篓，%@", "\(n.name)", "\(Scanner.bytes(n.size))"), undoID: id)
                    self.cleaner?.scan([.trash])
                } else {
                    self.cleaner?.report(L("没能处理「%@」", "\(n.name)"), failures: result.1)
                }
            }
        }
    }
}
