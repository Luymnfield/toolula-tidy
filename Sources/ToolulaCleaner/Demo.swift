import Foundation

/// 产品截图用的展示模式: ToolulaCleaner --demo
/// 只改显示的电脑信息 (MacBook Pro 16 英寸 · M4 Max · 128 GB 内存 · 2 TB 硬盘), 不读也不改真实设置
enum Demo {
    static let on = CommandLine.arguments.contains("--demo")

    static let memoryTotal: Int64 = 128 * 1_073_741_824
    static let diskTotal: Int64 = 2_000_000_000_000
    static let diskFree: Int64 = 1_412_000_000_000

    /// 内存使用随时间轻轻波动, 内存页面的曲线看起来是活的
    static func memorySnapshot(at time: TimeInterval? = nil) -> MemorySnapshot {
        let t = time ?? Date().timeIntervalSince1970
        let wave = (sin(t / 9) + sin(t / 3.7) * 0.4) * 1.6
        var s = MemorySnapshot()
        s.total = memoryTotal
        s.app = Int64((26.0 + wave) * 1_073_741_824)
        s.wired = Int64(6.4 * 1_073_741_824)
        s.compressed = Int64(1.8 * 1_073_741_824)
        s.cached = Int64(33.5 * 1_073_741_824)
        s.pressure = .normal
        return s
    }

    /// 内存页面「占用内存最多的应用」(不显示真实的进程)
    static func memoryGroups() -> [MemoryGroup] {
        let gb: Int64 = 1_073_741_824
        func app(_ name: String, _ path: String, _ size: Double, _ count: Int) -> MemoryGroup {
            MemoryGroup(id: path, name: name, iconPath: FileManager.default.fileExists(atPath: path) ? path : nil,
                        bytes: Int64(size * Double(gb)), pids: Array(repeating: 0, count: count), isApp: true, canQuit: true)
        }
        var node = MemoryGroup(id: "node", name: "node", iconPath: nil, bytes: Int64(1.4 * Double(gb)), pids: [0], isApp: false, canQuit: true)
        node.detail = "vite · website"
        node.parentApp = "Visual Studio Code"
        return [
            app("Xcode", "/Applications/Xcode.app", 6.8, 3),
            app("Google Chrome", "/Applications/Google Chrome.app", 4.6, 22),
            app("Blender", "/Applications/Blender.app", 3.2, 1),
            app("Adobe Lightroom Classic", "/Applications/Adobe Lightroom Classic/Adobe Lightroom Classic.app", 2.7, 2),
            app("Visual Studio Code", "/Applications/Visual Studio Code.app", 1.9, 11),
            node,
            app("Safari", "/Applications/Safari.app", 1.2, 6),
            app("Claude", "/Applications/Claude.app", 0.9, 8),
        ]
    }
}
