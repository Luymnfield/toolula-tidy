import AppKit
import CryptoKit
import Foundation
import SwiftUI

/// 一组内容完全一样的文件里的一个
struct DupFile: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    /// 实际占用
    let size: Int64
    let created: Date
    var selected: Bool
    /// 在开发项目里 (删了可能让项目跑不起来, 默认不勾选)
    var inProject = false
}

struct DupGroup: Identifiable, Hashable, Sendable {
    let id: String
    var files: [DupFile]
    /// 一个文件的实际占用
    var size: Int64 { files.first?.size ?? 0 }
    /// 删掉多余的能腾出的空间 (留一份)
    var wasted: Int64 { size * Int64(max(0, files.count - 1)) }
    var selectedSize: Int64 { files.filter(\.selected).reduce(0) { $0 + $1.size } }
    var keepsOne: Bool { files.contains { !$0.selected } }
}

/// 重复文件: 先按大小分组, 再比较开头结尾, 最后比较完整内容 (SHA-256). 内容完全一样才算重复
enum Duplicates {
    static let SF_DATALESS: UInt32 = 0x4000_0000

    static func find(minSize: Int64) -> [DupGroup] {
        // 1. 找出够大的文件 (和「大文件」一样的范围: 不碰资源库、隐藏文件夹、照片图库等)
        let paths = Locked<[String]>([])
        var opts = FastWalker.Options()
        opts.skipHidden = true
        opts.skipDir = { name, _, _ in Scanner.isPackage(name) || ProjectJunk.names.contains(name) }
        opts.fileThreshold = minSize
        opts.onFile = { _, path, _ in paths.mutate { $0.append(path) } }
        _ = FastWalker.sizes(Scanner.personalRoots().map(\.path), options: opts)

        // 2. 按文件真实长度分组. 同一个文件的硬链接只算一次; 没下载到本机的 iCloud 文件不读 (读了会触发下载)
        struct Info { let path: String; let length: Int64; let alloc: Int64; let created: Date }
        var byLength: [Int64: [Info]] = [:]
        var seen = Set<String>()
        for p in paths.value {
            var st = stat()
            guard lstat(p, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_flags & SF_DATALESS == 0 else { continue }
            guard seen.insert("\(st.st_dev):\(st.st_ino)").inserted else { continue }
            byLength[Int64(st.st_size), default: []].append(
                Info(path: p, length: Int64(st.st_size), alloc: Int64(st.st_blocks) * 512,
                     created: Date(timeIntervalSince1970: Double(st.st_birthtimespec.tv_sec))))
        }
        let sameLength = byLength.values.filter { $0.count > 1 }

        // 3. 先比开头和结尾各 64 KB (很快就能排除大部分), 再比完整内容. 多核一起算
        func refine(_ groups: [[Info]], _ hash: @escaping @Sendable (Info) -> String?) -> [[Info]] {
            let flat = groups.flatMap { $0 }
            var keys = [String?](repeating: nil, count: flat.count)
            keys.withUnsafeMutableBufferPointer { out in
                DispatchQueue.concurrentPerform(iterations: flat.count) { i in out[i] = hash(flat[i]) }
            }
            var buckets: [String: [Info]] = [:]
            for (i, f) in flat.enumerated() { if let k = keys[i] { buckets["\(f.length):\(k)", default: []].append(f) } }
            return buckets.values.filter { $0.count > 1 }
        }
        let partial = refine(sameLength) { digest($0.path, partial: true) }
        let full = refine(partial) { digest($0.path, partial: false) }

        return full.map { infos in
            var files = infos.map { DupFile(url: URL(fileURLWithPath: $0.path), size: $0.alloc, created: $0.created, selected: true) }
            files.sort(by: keepFirst)
            files[0].selected = false   // 默认留下最早的那份
            // 开发项目里的文件 (例如 dist 和 public 里同一个字体) 是项目要用的, 默认都不勾选
            for i in files.indices where inProject(files[i].url.path) {
                files[i].inProject = true
                files[i].selected = false
            }
            return DupGroup(id: files[0].id, files: files)
        }
        .filter { $0.size > 0 }
        .sorted { $0.wasted > $1.wasted }
    }

    /// 文件所在的某一层文件夹是开发项目 (有 .git 或项目文件)
    static let projectMarkers = [".git", "package.json", "Cargo.toml", "Package.swift", "pyproject.toml", "go.mod", "pom.xml",
                                 "build.gradle", "Podfile", "pubspec.yaml", "Gemfile", "composer.json"]
    static func inProject(_ path: String) -> Bool {
        let home = Scanner.home.path
        var dir = (path as NSString).deletingLastPathComponent
        let fm = FileManager.default
        while dir.hasPrefix(home + "/") {
            if projectMarkers.contains(where: { fm.fileExists(atPath: dir + "/" + $0) }) { return true }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return false
    }

    /// 默认留哪一份: 不在下载文件夹里的优先, 然后是最早创建的, 再然后是路径短的
    static func keepFirst(_ a: DupFile, _ b: DupFile) -> Bool {
        let dl = Scanner.home.path + "/Downloads/"
        let ad = a.url.path.hasPrefix(dl), bd = b.url.path.hasPrefix(dl)
        if ad != bd { return !ad }
        if a.created != b.created { return a.created < b.created }
        return a.url.path.count < b.url.path.count
    }

    /// 文件内容的指纹. partial: 只看开头和结尾各 64 KB
    static func digest(_ path: String, partial: Bool) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        var sha = SHA256()
        let chunk = partial ? 64 * 1024 : 1024 * 1024
        if partial {
            guard let head = try? h.read(upToCount: chunk), !head.isEmpty else { return nil }
            sha.update(data: head)
            if let end = try? h.seekToEnd(), end > UInt64(chunk) * 2 {
                try? h.seek(toOffset: end - UInt64(chunk))
                if let tail = try? h.read(upToCount: chunk) { sha.update(data: tail) }
            }
        } else {
            // 读到结尾时 read 返回 nil 或空数据; 真正出错时放弃这个文件
            while true {
                do {
                    guard let d = try h.read(upToCount: chunk), !d.isEmpty else { break }
                    sha.update(data: d)
                } catch { return nil }
            }
        }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class DuplicateStore: ObservableObject {
    weak var cleaner: CleanerStore?
    @Published var groups: [DupGroup] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var cleaning = false
    @Published var pendingClean = false
    @Published var minSizeMB = CleanerStore.defaults.object(forKey: "dupMinSizeMB") as? Int ?? 1 {
        didSet { CleanerStore.defaults.set(minSizeMB, forKey: "dupMinSizeMB"); if scanned { scan() } }
    }

    init() {
        NotificationCenter.default.addObserver(forName: .toolulaUndoFinished, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.scanned == true { self?.scan() } }
        }
    }

    var wasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }
    var selectedFiles: [DupFile] { groups.flatMap { $0.files.filter(\.selected) } }
    var selectedSize: Int64 { groups.reduce(0) { $0 + $1.selectedSize } }

    func scan() {
        guard !scanning else { return }
        scanning = true
        let min = Int64(minSizeMB) * 1_000_000
        Task.detached(priority: .userInitiated) {
            let g = Duplicates.find(minSize: min)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { self.groups = g }
                self.scanning = false
                self.scanned = true
            }
        }
    }

    /// 勾选 / 取消一个文件. 每组至少要留一个不勾选
    func toggle(_ groupID: String, _ fileID: String) {
        guard let g = groups.firstIndex(where: { $0.id == groupID }),
              let f = groups[g].files.firstIndex(where: { $0.id == fileID }) else { return }
        if !groups[g].files[f].selected && groups[g].files.filter({ !$0.selected }).count <= 1 {
            cleaner?.show(L("每组至少要留下一个文件"))
            return
        }
        groups[g].files[f].selected.toggle()
    }

    /// 每组只留一份 (默认的那份), 其余全选
    func selectAllButOne() {
        groups = groups.map { g in
            var g = g
            for i in g.files.indices { g.files[i].selected = i != 0 && !g.files[i].inProject }
            return g
        }
    }

    func selectNone() {
        groups = groups.map { g in var g = g; for i in g.files.indices { g.files[i].selected = false }; return g }
    }

    func clean() {
        // 最后再检查一次: 每组都留着至少一个
        let files = groups.filter(\.keepsOne).flatMap { $0.files.filter(\.selected) }
        guard !files.isEmpty, !cleaning else { return }
        cleaning = true
        Task.detached(priority: .userInitiated) {
            var freed: Int64 = 0
            var moves: [Move] = []
            var failures: [Failure] = []
            var done = Set<String>()
            for f in files {
                do {
                    if let to = try Safety.remove(f.url, kind: .largeFiles, permanent: false) {
                        moves.append(Move(from: f.url.path, to: to.path))
                    }
                    freed += f.size
                    done.insert(f.id)
                } catch {
                    failures.append(Failure(path: f.url.path, error: error))
                }
            }
            let result = (freed, moves, failures, done)
            await MainActor.run {
                self.cleaning = false
                withAnimation {
                    self.groups = self.groups.compactMap { g in
                        var g = g
                        g.files.removeAll { result.3.contains($0.id) }
                        return g.files.count > 1 ? g : nil
                    }
                }
                var id: UUID?
                if !result.3.isEmpty {
                    id = self.cleaner?.record(bytes: result.0, count: result.3.count, kinds: [L("重复文件")], moves: result.1)
                }
                var msg = L("已把 %@ 个重复文件移到废纸篓，%@", "\(result.3.count)", "\(Scanner.bytes(result.0))")
                if !result.2.isEmpty { msg += L("；%@ 项没能处理", "\(result.2.count)") }
                self.cleaner?.report(msg, undoID: result.1.isEmpty ? nil : id, failures: result.2)
                self.cleaner?.scan([.trash])
            }
        }
    }
}
