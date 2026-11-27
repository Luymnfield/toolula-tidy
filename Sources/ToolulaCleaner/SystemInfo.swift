import CoreGraphics
import Foundation
import SwiftUI

/// 一个磁盘 (系统盘 / 外接硬盘)
struct DiskInfo: Identifiable, Hashable {
    let id: String          // 挂载路径
    let name: String
    let total: Int64
    let free: Int64
    let isSystem: Bool
    let isInternal: Bool
    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

/// 自动检测当前电脑: 型号、芯片 (Apple 芯片或 Intel)、内存、CPU/GPU、所有磁盘; 实时更新内存和磁盘占用
@MainActor
final class SystemInfo: ObservableObject {
    static let shared = SystemInfo()

    @Published var machine = "Mac"
    @Published var chip = ""
    @Published var memory = ""
    @Published var modelId = ""
    @Published var cores = ""
    @Published var gpuCores = ""
    @Published var usedGB: Double = 0
    @Published var totalGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    @Published var disks: [DiskInfo] = []

    var summary: String { [machine, chip, memory].filter { !$0.isEmpty }.joined(separator: " · ") }
    var systemDisk: DiskInfo? { disks.first { $0.isSystem } ?? disks.first }

    /// 给 AI 的一句话描述
    var promptText: String {
        var s = summary
        if !cores.isEmpty { s += " · " + cores }
        if !gpuCores.isEmpty { s += " · " + gpuCores }
        for d in disks {
            s += L("；磁盘「%@」%@ 共 %@，可用 %@", "\(d.name)", "\(d.isSystem ? L("(系统盘)") : "")", "\(Self.size(d.total))", "\(Self.size(d.free))")
        }
        return s
    }

    /// 内置屏幕尺寸 (英寸): 13.6"→13, 14.2"→14, 15.3"→15, 16.2"→16, iMac 23.5"→24.
    /// 合盖接外接显示器时内置屏不在线, 用上次记住的值
    nonisolated static func builtInScreenInches(isLaptop: Bool) -> String? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        for d in ids.prefix(Int(n)) where CGDisplayIsBuiltin(d) != 0 {
            let s = CGDisplayScreenSize(d)  // 毫米
            let diag = (s.width * s.width + s.height * s.height).squareRoot() / 25.4
            guard diag > 5 else { continue }
            let v = isLaptop ? Int((diag + 0.2).rounded(.down)) : Int(diag.rounded())
            UserDefaults.standard.set(v, forKey: "builtInScreenInches")
            return "\(v)"
        }
        let saved = UserDefaults.standard.integer(forKey: "builtInScreenInches")
        return saved > 0 ? "\(saved)" : nil
    }

    nonisolated static func size(_ bytes: Int64) -> String {
        // 和访达一样用十进制 (1 TB = 1000 GB)
        let gb = Double(bytes) / 1e9
        if gb >= 1000 { return String(format: "%.2f TB", locale: .current, gb / 1000) }
        return String(format: "%.0f GB", locale: .current, gb)
    }

    nonisolated static func shell(_ path: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private var timer: Timer?
    private var tick = 0

    /// 读取硬件信息 (切换语言后再调用一次, 让「14 核 CPU」这类文字跟着变)
    func loadHardware() {
        if Demo.on {
            machine = L("%@ %@ 英寸", "MacBook Pro", "16")
            modelId = "Mac16,5"
            chip = "Apple M4 Max"
            memory = "128 GB"
            totalGB = 128
            cores = L("%@ 核 CPU", "16") + L("（%@ 性能 + %@ 能效）", "12", "4")
            gpuCores = L("%@ 核 GPU", "40")
            return
        }
        Task.detached {
            let (code, out) = SystemInfo.shell("/usr/sbin/system_profiler", ["SPHardwareDataType", "SPDisplaysDataType", "-json"])
            guard code == 0, let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any] else { return }
            let hw = (obj["SPHardwareDataType"] as? [[String: Any]])?.first ?? [:]
            let gpus = (obj["SPDisplaysDataType"] as? [[String: Any]]) ?? []

            // 芯片: Apple 芯片有 chip_type; Intel Mac 用 cpu_type + 主频
            var chip = hw["chip_type"] as? String ?? ""
            if chip.isEmpty, let cpu = hw["cpu_type"] as? String {
                chip = cpu
                if let speed = hw["current_processor_speed"] as? String { chip += " \(speed)" }
            }
            // CPU 核心: Apple 芯片是 "proc 14:10:4", Intel 是数字
            var coreText = ""
            if let s = hw["number_processors"] as? String {
                let parts = s.replacingOccurrences(of: "proc ", with: "").split(separator: ":").compactMap { Int($0) }
                if let total = parts.first {
                    coreText = L("%@ 核 CPU", "\(total)")
                    if parts.count >= 3 { coreText += L("（%@ 性能 + %@ 能效）", "\(parts[parts.count - 2])", "\(parts[parts.count - 1])") }
                }
            } else if let n = hw["number_processors"] as? Int {
                coreText = L("%@ 核 CPU", "\(n)")
            }
            // GPU: Apple 芯片显示核心数; 独立显卡显示型号
            let gpuText = gpus.compactMap { g -> String? in
                if let c = g["sppci_cores"] as? String { return L("%@ 核 GPU", "\(c)") }
                return g["sppci_model"] as? String
            }.joined(separator: " + ")

            let name = hw["machine_name"] as? String ?? "Mac"
            let inches = SystemInfo.builtInScreenInches(isLaptop: name.contains("Book"))
            let modelId = hw["machine_model"] as? String ?? ""
            await MainActor.run {
                self.machine = inches.map { L("%@ %@ 英寸", "\(name)", "\($0)") } ?? name
                self.modelId = modelId
                self.chip = chip
                self.memory = hw["physical_memory"] as? String ?? String(format: "%.0f GB", self.totalGB)
                self.cores = coreText
                self.gpuCores = gpuText
            }
        }
    }

    func start() {
        loadHardware()
        updateMemory()
        updateDisks()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                let s = SystemInfo.shared
                s.updateMemory()
                s.tick += 1
                if s.tick % 10 == 0 { s.updateDisks() }  // 磁盘每 30 秒刷新 (也能发现新插的硬盘)
            }
        }
    }

    func updateMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return }
        if Demo.on { usedGB = Double(Demo.memorySnapshot().used) / 1_073_741_824; return }
        let page = Double(vm_kernel_page_size)
        // 和活动监视器一样: 应用内存 + 系统固定 + 已压缩
        let used = (Double(stats.internal_page_count) - Double(stats.purgeable_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        usedGB = used / 1_073_741_824
    }

    func updateDisks() {
        if Demo.on {
            disks = [DiskInfo(id: "/", name: "Macintosh HD", total: Demo.diskTotal, free: Demo.diskFree, isSystem: true, isInternal: true)]
            return
        }
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var list: [DiskInfo] = []
        for u in urls {
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.volumeIsBrowsable != false,
                  let total = v.volumeTotalCapacity, total > 2_000_000_000 else { continue }
            let isRoot = v.volumeIsRootFileSystem ?? (u.path == "/")
            // 系统盘用"重要用途可用空间" (包含可清除空间, 和访达显示一致)
            let free = isRoot ? (v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0))
                              : Int64(v.volumeAvailableCapacity ?? 0)
            list.append(DiskInfo(id: u.path, name: v.volumeName ?? u.lastPathComponent, total: Int64(total), free: free,
                                 isSystem: isRoot, isInternal: v.volumeIsInternal ?? isRoot))
        }
        disks = list.sorted { ($0.isSystem ? 0 : 1, $0.name) < ($1.isSystem ? 0 : 1, $1.name) }
    }
}

// MARK: - 显示

struct UsageBar: View {
    let fraction: Double
    var height: CGFloat? = nil     // 设了就画成圆角粗条（主页大卡片用）
    var color: Color { fraction > 0.9 ? .red : fraction > 0.75 ? .orange : .green }
    var body: some View {
        if let h = height {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(color).frame(width: g.size.width * min(1, max(0, fraction)))
                }
            }
            .frame(height: h)
        } else {
            ProgressView(value: min(1, max(0, fraction))).tint(color)
        }
    }
}

/// 电脑信息卡片 (compact = 左侧窄栏用)
struct MachineBadge: View {
    @ObservedObject var info = SystemInfo.shared
    var compact = false
    var large = false      // 主页右上角的大卡片

    var body: some View {
        if compact { compactBody } else { fullBody }
    }

    var compactBody: some View {
        VStack(spacing: 3) {
            Image(systemName: info.machine.contains("Book") ? "laptopcomputer" : "desktopcomputer").foregroundStyle(.secondary)
            Text(info.chip.replacingOccurrences(of: "Apple ", with: "")).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Text(info.memory).font(.caption2).foregroundStyle(.secondary)
            UsageBar(fraction: info.usedGB / max(info.totalGB, 1))
            Text(L("内存 %@ GB", "\(Int(info.usedGB.rounded()))")).font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
            if let d = info.systemDisk {
                UsageBar(fraction: d.usedFraction).padding(.top, 3)
                Text(L("硬盘剩 %@", "\(SystemInfo.size(d.free))")).font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .help(helpText)
    }

    var fullBody: some View {
        VStack(alignment: .leading, spacing: large ? 12 : 6) {
            HStack(spacing: large ? 10 : 6) {
                Image(systemName: info.machine.contains("Book") ? "laptopcomputer" : "desktopcomputer")
                    .font(large ? .title2 : .body).foregroundStyle(.secondary)
                Text(info.summary).font(large ? .headline : .caption.bold()).lineLimit(1).minimumScaleFactor(0.8)
            }
            if !info.cores.isEmpty || !info.gpuCores.isEmpty {
                Text([info.cores, info.gpuCores].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(large ? .callout : .caption2).foregroundStyle(.secondary)
            }
            row(icon: "memorychip", title: L("内存"), detail: L("已用 %@ / %@ GB", "\(Int(info.usedGB.rounded()))", "\(Int(info.totalGB.rounded()))"),
                fraction: info.usedGB / max(info.totalGB, 1))
            ForEach(info.disks) { d in
                row(icon: d.isInternal ? "internaldrive" : "externaldrive",
                    title: d.isSystem ? L("硬盘（%@）", "\(d.name)") : d.name,
                    detail: L("可用 %@ / 共 %@", "\(SystemInfo.size(d.free))", "\(SystemInfo.size(d.total))"),
                    fraction: d.usedFraction)
            }
        }
        .help(helpText)
    }

    func row(icon: String, title: String, detail: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: large ? 6 : 2) {
            HStack {
                Label(title, systemImage: icon).font(large ? .body : .caption2)
                Spacer()
                Text(detail).font(large ? .callout : .caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            UsageBar(fraction: fraction, height: large ? 8 : nil)
        }
    }

    var helpText: String {
        var s = "\(info.summary) (\(info.modelId))\n\(info.cores) \(info.gpuCores)\n" + L("内存已用 %@ / %@ GB", "\(Int(info.usedGB))", "\(Int(info.totalGB))")
        for d in info.disks { s += "\n\(d.name): " + L("可用 %@ / 共 %@", "\(SystemInfo.size(d.free))", "\(SystemInfo.size(d.total))") }
        return s
    }
}
