import AppKit
import Darwin
import SwiftUI

/// 内存压力: 和「活动监视器」一样分三档
enum MemoryPressure: Int {
    case normal = 1, warning = 2, critical = 4

    var title: String {
        switch self {
        case .normal: return L("正常")
        case .warning: return L("偏高")
        case .critical: return L("紧张")
        }
    }
    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
    var advice: String {
        switch self {
        case .normal:
            return L("内存够用，什么都不用做。「已使用」看起来高是正常的：macOS 会把空闲的内存拿来缓存文件，应用要用时马上让出来。")
        case .warning:
            return L("系统正在大量压缩内存，可能偶尔会卡一下。可以退出下面暂时不用的应用，或者关掉一些浏览器标签页。")
        case .critical:
            return L("内存不够了，系统在频繁使用硬盘上的交换文件，会明显变慢。请退出下面占内存最多、暂时不用的应用。")
        }
    }
}

/// 一组进程 (同一个应用的所有进程算在一起, 例如 Chrome 和它的几十个 Helper)
struct MemoryGroup: Identifiable, Hashable {
    let id: String          // 应用路径或程序路径
    let name: String
    let iconPath: String?
    let bytes: Int64
    let pids: [pid_t]
    let isApp: Bool
    /// 可以退出 (不是系统进程, 也不是本 App)
    let canQuit: Bool
    /// 后台程序在跑什么 (例如 "vite · my-project")
    var detail: String? = nil
    /// 后台程序是哪个应用启动的 (例如 "Bionic")
    var parentApp: String? = nil
}

struct MemorySnapshot {
    var total: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    var app: Int64 = 0
    var wired: Int64 = 0
    var compressed: Int64 = 0
    var cached: Int64 = 0
    var swapUsed: Int64 = 0
    var swapTotal: Int64 = 0
    var pressure: MemoryPressure = .normal
    var used: Int64 { app + wired + compressed }
    var free: Int64 { max(0, total - used - cached) }
}

@MainActor
final class MemoryMonitor: ObservableObject {
    static let shared = MemoryMonitor()

    @Published var snap = MemorySnapshot()
    /// 最近 3 分钟「已使用」的比例 (每 2 秒一个点)
    @Published var history: [Double] = []
    @Published var groups: [MemoryGroup] = []
    @Published var pendingQuit: MemoryGroup?

    private var timer: Timer?
    /// 内存页面打开时才列进程 (省电)
    var watchingProcesses = false {
        didSet { if watchingProcesses { refreshProcesses() } }
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                let m = MemoryMonitor.shared
                m.refresh()
                if m.watchingProcesses { m.refreshProcesses() }
            }
        }
    }

    func refresh() {
        let s = Self.read()
        snap = s
        history.append(Double(s.used) / Double(max(s.total, 1)))
        if history.count > 90 { history.removeFirst(history.count - 90) }
    }

    func refreshProcesses() {
        Task.detached(priority: .utility) {
            let g = Self.topGroups()
            await MainActor.run { self.groups = g }
        }
    }

    // MARK: 读取系统数据 (和活动监视器同样的算法)

    nonisolated static func read() -> MemorySnapshot {
        var s = MemorySnapshot()
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        if r == KERN_SUCCESS {
            let page = Int64(vm_kernel_page_size)
            s.app = (Int64(stats.internal_page_count) - Int64(stats.purgeable_count)) * page
            s.wired = Int64(stats.wire_count) * page
            s.compressed = Int64(stats.compressor_page_count) * page
            s.cached = (Int64(stats.external_page_count) + Int64(stats.purgeable_count)) * page
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            s.swapUsed = Int64(swap.xsu_used)
            s.swapTotal = Int64(swap.xsu_total)
        }
        var level: Int32 = 1
        size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            s.pressure = MemoryPressure(rawValue: Int(level)) ?? .normal
        }
        return s
    }

    /// 按应用汇总所有能看到的进程的内存 (和活动监视器「内存」一栏相同: phys_footprint)
    nonisolated static func topGroups(limit: Int = 15) -> [MemoryGroup] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        let me = getpid()
        var sums: [String: (name: String, icon: String?, bytes: Int64, pids: [pid_t], isApp: Bool)] = [:]
        var pathBuf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))

        for pid in pids.prefix(got) where pid > 0 {
            var info = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard ok == 0, info.ri_phys_footprint > 0 else { continue }
            guard proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 else { continue }
            let path = String(cString: pathBuf)
            // 在某个 .app 里面 → 算到最外层的应用上 (Chrome Helper 算 Chrome)
            let key: String, name: String, isApp: Bool
            if let r = path.range(of: ".app/") {
                key = String(path[..<r.lowerBound]) + ".app"
                var n = FileManager.default.displayName(atPath: key)
                if n.hasSuffix(".app") { n.removeLast(4) }
                name = n; isApp = true
            } else {
                key = path; name = (path as NSString).lastPathComponent; isApp = false
            }
            var e = sums[key] ?? (name, isApp ? key : nil, 0, [], isApp)
            e.bytes += Int64(info.ri_phys_footprint)
            e.pids.append(pid)
            sums[key] = e
        }
        let systemPrefixes = ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/", "/private/"]
        // 「应用」= 有窗口、出现在程序坞里的; 藏在别的应用里的 .app (例如 Claude Code) 算后台程序
        let regular = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap { $0.bundleURL?.path })
        let top = sums.sorted { $0.value.bytes > $1.value.bytes }.prefix(limit)
        return top.map { key, v in
            let system = systemPrefixes.contains { key.hasPrefix($0) }
            let isApp = v.isApp && regular.contains(key)
            var g = MemoryGroup(id: key, name: v.name, iconPath: v.icon, bytes: v.bytes, pids: v.pids, isApp: isApp,
                                canQuit: !system && !v.pids.contains(me))
            if !isApp, let pid = v.pids.first {
                g.detail = v.isApp ? nil : describe(args: procArgs(pid))
                g.parentApp = parentApp(of: pid)
            }
            return g
        }
    }

    // MARK: 后台程序是什么

    /// 进程的启动参数 (KERN_PROCARGS2)
    nonisolated static func procArgs(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return [] }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < size && buf[i] != 0 { i += 1 }     // 跳过程序路径
        while i < size && buf[i] == 0 { i += 1 }
        var args: [String] = []
        while args.count < argc && i < size {
            let start = i
            while i < size && buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    /// node / python 这类解释器: 找出它在跑的脚本, 以及脚本所在的项目
    nonisolated static func describe(args: [String]) -> String? {
        guard let exe = args.first.map({ ($0 as NSString).lastPathComponent.lowercased() }) else { return nil }
        let interpreters = ["node", "python", "ruby", "java", "bun", "deno", "perl", "php", "uv"]
        guard interpreters.contains(where: { exe.hasPrefix($0) }) else { return nil }
        var it = args.dropFirst().makeIterator()
        while let a = it.next() {
            if a == "-e" || a == "-c" || a == "--eval" { return nil }        // 直接写在命令里的代码, 没有脚本名
            if a == "-m", let mod = it.next() { return mod }                 // python -m 模块
            if a.hasPrefix("-") { continue }
            let parts = a.split(separator: "/").map(String.init)
            let file = parts.last ?? a
            if let nm = parts.firstIndex(of: "node_modules"), nm > 0 { return "\(file) · \(parts[nm - 1])" }
            return parts.count >= 2 ? "\(file) · \(parts[parts.count - 2])" : file
        }
        return nil
    }

    /// 往上找父进程, 找到启动它的应用 (例如 LM Studio 启动的 node)
    nonisolated static func parentApp(of pid: pid_t) -> String? {
        var cur = pid
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for _ in 0..<6 {
            var info = proc_bsdinfo()
            guard proc_pidinfo(cur, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { return nil }
            let ppid = pid_t(info.pbi_ppid)
            guard ppid > 1 else { return nil }
            if proc_pidpath(ppid, &buf, UInt32(buf.count)) > 0 {
                let path = String(cString: buf)
                if let r = path.range(of: ".app/") {
                    var n = FileManager.default.displayName(atPath: String(path[..<r.lowerBound]) + ".app")
                    if n.hasSuffix(".app") { n.removeLast(4) }
                    return n
                }
            }
            cur = ppid
        }
        return nil
    }

    // MARK: 退出

    func quit(_ g: MemoryGroup) {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == g.id }
        if !apps.isEmpty {
            apps.forEach { $0.terminate() }       // 正常退出, 应用会提示保存
        } else {
            for p in g.pids where p != getpid() { kill(p, SIGTERM) }   // 没有界面的后台程序
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            refresh(); refreshProcesses()
        }
    }
}
