import Darwin
import Foundation

/// 高速目录遍历: getattrlistbulk 一次系统调用拿到一批文件的名字 / 类型 / 实际占用,
/// 所有 CPU 核心同时从一个共享的文件夹队列里取活干 (一个大文件夹也会被拆开并行).
/// 比 FileManager.enumerator + resourceValues 快很多, 且不会为每个文件创建 URL 对象.
enum FastWalker {
    struct Options {
        /// 跳过隐藏文件夹 (名字以 . 开头)
        var skipHidden = false
        /// 不进入的文件夹 (名字, 深度: 根下第一层为 1, 所在的文件夹). 会被多个线程同时调用
        var skipDir: (@Sendable (_ name: String, _ depth: Int, _ parent: String) -> Bool)? = nil
        /// 大于等于这个大小的普通文件会回调 onFile
        var fileThreshold: Int64 = .max
        /// 会被多个线程同时调用
        var onFile: (@Sendable (_ root: Int, _ path: String, _ size: Int64) -> Void)? = nil
    }

    // <sys/attr.h> 常量 (写死, 避免 Swift 导入宏时的有符号问题)
    private static let CMN_NAME: UInt32 = 0x0000_0001
    private static let CMN_OBJTYPE: UInt32 = 0x0000_0008
    private static let CMN_FILEID: UInt32 = 0x0200_0000
    private static let CMN_ERROR: UInt32 = 0x2000_0000
    private static let CMN_RETURNED_ATTRS: UInt32 = 0x8000_0000
    private static let FILE_LINKCOUNT: UInt32 = 0x0000_0001
    private static let FILE_ALLOCSIZE: UInt32 = 0x0000_0004
    private static let VREG: UInt32 = 1, VDIR: UInt32 = 2

    private struct Job { let root: Int; let path: String; let depth: Int }

    /// 同一时间只做一次遍历 (多个类别同时扫描时排队, 避免几十个线程抢磁盘)
    private static let gate = NSLock()

    /// 每个路径的实际占用 (字节). 路径可以是文件或文件夹; 不跟随链接, 硬链接只算一次.
    static func sizes(_ paths: [String], options: Options = Options()) -> [Int64] {
        gate.lock()
        defer { gate.unlock() }
        var totals = [Int64](repeating: 0, count: paths.count)
        var stack: [Job] = []
        for (i, p) in paths.enumerated() {
            var st = stat()
            guard lstat(p, &st) == 0 else { continue }
            if (st.st_mode & S_IFMT) == S_IFDIR {
                stack.append(Job(root: i, path: p, depth: 0))
            } else {
                totals[i] = Int64(st.st_blocks) * 512
                if (st.st_mode & S_IFMT) == S_IFREG, totals[i] >= options.fileThreshold { options.onFile?(i, p, totals[i]) }
            }
        }
        guard !stack.isEmpty else { return totals }

        let cond = NSCondition()
        var active = 0
        var seenLinks = Set<UInt64>()      // 硬链接 (很少见) 去重
        // 实测 M3 Max: 1 线程 1.15s, 4 线程 0.42s, 14 线程反而 0.90s (APFS 内部锁竞争). 所以固定 4 个
        let workers = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount))

        DispatchQueue.concurrentPerform(iterations: workers) { _ in
            var local = [Int64](repeating: 0, count: paths.count)
            let bufSize = 256 * 1024
            let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 16)
            defer { buf.deallocate() }
            var found: [Job] = []
            var links: [(UInt64, Int64)] = []

            while true {
                cond.lock()
                while stack.isEmpty && active > 0 { cond.wait() }
                if stack.isEmpty { cond.broadcast(); cond.unlock(); break }
                let job = stack.removeLast()
                active += 1
                cond.unlock()

                found.removeAll(keepingCapacity: true)
                links.removeAll(keepingCapacity: true)
                local[job.root] += scanDir(job, buf: buf, bufSize: bufSize, options: options, found: &found, links: &links)

                cond.lock()
                for (id, alloc) in links where !seenLinks.insert(id).inserted {
                    local[job.root] -= alloc   // 同一个文件的另一个硬链接, 已经算过了
                }
                stack.append(contentsOf: found)
                active -= 1
                if !found.isEmpty || (active == 0 && stack.isEmpty) { cond.broadcast() }
                cond.unlock()
            }
            cond.lock()
            for i in local.indices { totals[i] += local[i] }
            cond.unlock()
        }
        return totals
    }

    /// 读一个文件夹: 返回这一层文件的占用之和, 子文件夹放进 found
    private static func scanDir(_ job: Job, buf: UnsafeMutableRawPointer, bufSize: Int, options: Options,
                                found: inout [Job], links: inout [(UInt64, Int64)]) -> Int64 {
        let fd = open(job.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return 0 }
        defer { close(fd) }
        var al = attrlist()
        al.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        al.commonattr = CMN_RETURNED_ATTRS | CMN_NAME | CMN_ERROR | CMN_OBJTYPE | CMN_FILEID
        al.fileattr = FILE_LINKCOUNT | FILE_ALLOCSIZE
        var total: Int64 = 0
        let depth = job.depth + 1

        while true {
            let count = getattrlistbulk(fd, &al, buf, bufSize, 0)
            if count <= 0 { break }
            var entry = buf
            for _ in 0..<count {
                let len = Int(entry.loadUnaligned(as: UInt32.self))
                var f = entry + 4
                let returned = f.loadUnaligned(as: attribute_set_t.self)
                f += MemoryLayout<attribute_set_t>.size
                defer { entry += len }
                if returned.commonattr & CMN_ERROR != 0 {
                    if f.loadUnaligned(as: UInt32.self) != 0 { continue }
                    f += 4
                }
                var name: UnsafePointer<CChar>?
                if returned.commonattr & CMN_NAME != 0 {
                    let ref = f.loadUnaligned(as: attrreference_t.self)
                    name = UnsafePointer((f + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                    f += MemoryLayout<attrreference_t>.size
                }
                var type: UInt32 = 0
                if returned.commonattr & CMN_OBJTYPE != 0 { type = f.loadUnaligned(as: UInt32.self); f += 4 }
                var fileID: UInt64 = 0
                if returned.commonattr & CMN_FILEID != 0 { fileID = f.loadUnaligned(as: UInt64.self); f += 8 }
                var linkCount: UInt32 = 1
                if returned.fileattr & FILE_LINKCOUNT != 0 { linkCount = f.loadUnaligned(as: UInt32.self); f += 4 }
                var alloc: Int64 = 0
                if returned.fileattr & FILE_ALLOCSIZE != 0 { alloc = f.loadUnaligned(as: Int64.self) }

                if type == VDIR {
                    guard let name else { continue }
                    if options.skipHidden && name.pointee == 0x2E { continue }   // "."
                    let n = String(cString: name)
                    if let skip = options.skipDir, skip(n, depth, job.path) { continue }
                    found.append(Job(root: job.root, path: job.path + "/" + n, depth: depth))
                } else {
                    if linkCount > 1 { links.append((fileID, alloc)) }
                    total += alloc
                    if type == VREG, alloc >= options.fileThreshold, let name, let cb = options.onFile {
                        if options.skipHidden && name.pointee == 0x2E { continue }
                        cb(job.root, job.path + "/" + String(cString: name), alloc)
                    }
                }
            }
        }
        return total
    }

    static func size(_ path: String) -> Int64 { sizes([path])[0] }
}
