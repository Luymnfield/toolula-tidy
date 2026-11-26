import AppKit
import SwiftUI

/// 内存页面: 内存压力、内存都用在哪、谁占得最多
struct MemoryView: View {
    @ObservedObject var mon = MemoryMonitor.shared
    @State private var showWhy = false
    var s: MemorySnapshot { mon.snap }

    static let appColor = Color.toolula
    static let wiredColor = Color.orange
    static let compressedColor = Color.purple
    static let cachedColor = Color.blue.opacity(0.45)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                advice
                breakdown
                topApps
                why
            }
            .padding(.horizontal, 32).padding(.vertical, 26)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
            .overlayScrollers()
        }
        .onAppear { mon.watchingProcesses = true }
        .onDisappear { mon.watchingProcesses = false }
        .confirmationDialog(mon.pendingQuit.map { L("退出「%@」？", "\($0.name)") } ?? "",
                            isPresented: Binding(get: { mon.pendingQuit != nil }, set: { if !$0 { mon.pendingQuit = nil } }),
                            presenting: mon.pendingQuit) { g in
            Button(L("退出"), role: .destructive) { mon.quit(g) }
            Button(L("取消"), role: .cancel) {}
        } message: { g in
            if g.isApp {
                Text(L("应用会正常退出，有没保存的内容时它会提醒你。可以腾出约 %@。", "\(Scanner.bytes(g.bytes))"))
            } else if let p = g.parentApp {
                Text(L("这是「%@」启动的后台程序（%@ 个进程）。结束后「%@」里正在用的功能会停止（例如已加载的模型）。可以腾出约 %@。", "\(p)", "\(g.pids.count)", "\(p)", "\(Scanner.bytes(g.bytes))"))
            } else {
                Text(L("这是一个后台程序（%@ 个进程），结束后它正在做的事会中断。可以腾出约 %@。", "\(g.pids.count)", "\(Scanner.bytes(g.bytes))"))
            }
        }
    }

    var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "memorychip")
                .font(.system(size: 24, weight: .medium)).foregroundStyle(Color.toolula)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.toolula.opacity(0.13)))
            VStack(alignment: .leading, spacing: 4) {
                Text(L("内存")).font(.system(size: 26, weight: .bold))
                Text(L("macOS 会自动管理内存。这里帮你看清楚：内存够不够用，被谁占着")).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Circle().fill(s.pressure.color).frame(width: 12, height: 12)
                    Text(L("压力%@", "\(s.pressure.title)")).font(.system(size: 26, weight: .bold))
                }
                Text(L("内存压力")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    var advice: some View {
        Label {
            Text(s.pressure.advice).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: s.pressure == .normal ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(s.pressure.color)
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(s.pressure.color.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(s.pressure.color.opacity(0.2)))
    }

    // MARK: 内存都用在哪

    var breakdown: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("已使用")).font(.callout).foregroundStyle(.secondary)
                Text(gb(s.used)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText()).animation(.easeOut, value: s.used)
                Text("/ \(gb(s.total))").font(.title3).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("交换文件 %@", "\(gb(s.swapUsed))")).font(.callout.weight(.medium)).monospacedDigit()
                        .foregroundStyle(s.swapUsed > s.total / 10 && s.pressure != .normal ? Color.orange : Color.primary)
                    Text(L("写到硬盘上的内存")).font(.caption).foregroundStyle(.secondary)
                }
            }
            stackedBar
            HStack(alignment: .top, spacing: 12) {
                legend(MemoryView.appColor, L("应用"), s.app, L("应用和网页正在用的"))
                legend(MemoryView.wiredColor, L("系统固定"), s.wired, L("系统内核和显卡用的，不能挪走"))
                legend(MemoryView.compressedColor, L("已压缩"), s.compressed, L("暂时不用、压缩起来的"))
                legend(MemoryView.cachedColor, L("文件缓存"), s.cached, L("随时可以让出来"))
                legend(Color.primary.opacity(0.12), L("空闲"), s.free, L("完全没用上的"))
            }
            sparkline.frame(height: 54)
            Text(L("最近 3 分钟的「已使用」")).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.06)))
    }

    var stackedBar: some View {
        GeometryReader { g in
            let total = Double(max(s.total, 1))
            HStack(spacing: 2) {
                ForEach(Array([(s.app, MemoryView.appColor), (s.wired, MemoryView.wiredColor),
                               (s.compressed, MemoryView.compressedColor), (s.cached, MemoryView.cachedColor)].enumerated()), id: \.offset) { _, seg in
                    Rectangle().fill(seg.1).frame(width: max(0, g.size.width * Double(seg.0) / total - 2))
                }
                Spacer(minLength: 0)
            }
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .animation(.easeOut(duration: 0.4), value: s.used)
        }
        .frame(height: 22)
    }

    func legend(_ color: Color, _ title: String, _ bytes: Int64, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
                Text(title).font(.callout.weight(.medium))
            }
            Text(gb(bytes)).font(.title3.weight(.semibold)).monospacedDigit()
            Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var sparkline: some View {
        GeometryReader { g in
            let h = mon.history
            let step = g.size.width / CGFloat(max(89, 1))
            let x0 = g.size.width - CGFloat(max(h.count - 1, 0)) * step
            let pts = h.enumerated().map { CGPoint(x: x0 + CGFloat($0.offset) * step, y: g.size.height * (1 - CGFloat($0.element))) }
            ZStack {
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: CGPoint(x: f.x, y: g.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height))
                }
                .fill(LinearGradient(colors: [Color.toolula.opacity(0.3), Color.toolula.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(Color.toolula, lineWidth: 1.5)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
    }

    // MARK: 谁占得最多

    var topApps: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("占用内存最多的应用")).font(.headline)
                Spacer()
                Text(L("同一个应用的多个进程合在一起算 · 系统进程不显示")).font(.caption).foregroundStyle(.tertiary)
            }
            if mon.groups.isEmpty {
                HStack { ProgressView().controlSize(.small); Text(L("正在统计…")).foregroundStyle(.secondary) }.padding(8)
            }
            let maxBytes = Double(mon.groups.first?.bytes ?? 1)
            VStack(spacing: 2) {
                ForEach(mon.groups) { g in
                    MemoryRow(group: g, fraction: Double(g.bytes) / maxBytes) { mon.pendingQuit = g }
                }
            }
        }
    }

    var why: some View {
        DisclosureGroup(isExpanded: $showWhy) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Windows 上的「释放内存」在 Mac 上没有意义，甚至有害："))
                Text(L("· 这类工具其实是把「文件缓存」清空。数字是降下来了，但应用要重新从硬盘读文件，电脑反而会慢一阵，过一会儿缓存又满了。"))
                Text(L("· macOS 会自动把暂时不用的内存压缩，或者让出缓存，比手动清理聪明得多。"))
                Text(L("· 真正该看的是上面的「内存压力」：绿色就不用管；变黄或变红时，退出占内存最多、暂时不用的应用才有效。"))
            }
            .font(.callout).foregroundStyle(.secondary)
            .padding(.top, 8)
        } label: {
            Text(L("为什么没有「释放内存」按钮？")).font(.callout.weight(.medium))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    func gb(_ b: Int64) -> String {
        let g = Double(b) / 1_073_741_824   // 内存用 1024 进制, 和活动监视器一致
        return g >= 10 ? String(format: "%.0f GB", locale: .current, g) : String(format: "%.1f GB", locale: .current, g)
    }
}

struct MemoryRow: View {
    let group: MemoryGroup
    let fraction: Double
    let quit: () -> Void
    @State private var hover = false

    var subtitle: String {
        var parts: [String] = []
        if let d = group.detail { parts.append(d) }
        if let p = group.parentApp { parts.append(L("由 %@ 启动", "\(p)")) }
        if group.pids.count > 1 { parts.append(L("%@ 个进程", "\(group.pids.count)")) }
        if parts.isEmpty { parts.append(group.isApp ? L("应用") : L("后台程序")) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: group.iconPath.map(IconCache.icon) ?? IconCache.icon("/System/Applications/Utilities/Terminal.app"))
                .resizable().frame(width: 28, height: 28)
                .opacity(group.iconPath == nil ? 0.6 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 300, alignment: .leading)
            GeometryReader { g in
                Capsule().fill(Color.toolula.opacity(0.75)).frame(width: max(4, g.size.width * fraction), height: 8)
                    .frame(maxHeight: .infinity)
            }
            .frame(height: 28)
            Text(String(format: "%.1f GB", locale: .current, Double(group.bytes) / 1_073_741_824)).monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            Group {
                if group.canQuit {
                    Button(group.isApp ? L("退出") : L("结束"), action: quit).controlSize(.small)
                } else {
                    Text(L("系统")).font(.caption).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 56)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hover ? 0.06 : 0.025)))
        .onHover { hover = $0 }
    }
}
