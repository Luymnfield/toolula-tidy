import AppKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: CleanerStore
    @EnvironmentObject var un: UninstallStore
    @ObservedObject var mem = MemoryMonitor.shared
    @State private var machineHover = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if !store.hasFullDiskAccess { AccessBanner() }
                scanPanel
                grid
                HStack(alignment: .top, spacing: 16) {
                    historyBox
                    safetyBox
                }
            }
            .padding(36)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
            .overlayScrollers()
        }
    }

    var header: some View {
        HStack(alignment: .center, spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text("Toolula Cleaner").font(.system(size: 34, weight: .bold))
                Text(L("先扫描给你看，确认了才清理，默认移到废纸篓")).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Circle().fill(store.isScanning ? Color.orange : Color.green).frame(width: 8, height: 8)
                    Group {
                        if store.isScanning { Text(L("正在扫描…")) }
                        else if let d = store.lastScan { Text(L("上次扫描 ")) + Text(d, style: .time) }
                        else { Text(L("准备就绪")) }
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 20)
            // 点电脑信息卡片 → 内存页面
            Button { store.section = .memory } label: {
                VStack(alignment: .leading, spacing: 12) {
                    MachineBadge(large: true)
                    HStack(spacing: 6) {
                        Circle().fill(mem.snap.pressure.color).frame(width: 8, height: 8)
                        Text(L("内存压力：%@", "\(mem.snap.pressure.title)")).font(.callout)
                        Spacer()
                        Text(L("查看内存")).font(.callout).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(20)
                .frame(width: 400)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(machineHover ? 0.07 : 0.045)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .onHover { machineHover = $0 }
        }
    }

    /// 扫描结果大卡片: 可清理多少 + 一键清理
    var scanPanel: some View {
        HStack(alignment: .center, spacing: 24) {
            ZStack {
                Circle().fill(Color.toolula.opacity(0.14))
                if store.isScanning {
                    ProgressView().controlSize(.large)
                } else {
                    Image(systemName: store.junkTotal > 0 ? "sparkles" : "checkmark.seal.fill")
                        .font(.system(size: 34, weight: .medium)).foregroundStyle(Color.toolula)
                }
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 4) {
                Text(store.isScanning ? L("正在扫描 %@…", "\(store.scanningTitle ?? "")") : L("可清理")).font(.callout).foregroundStyle(.secondary)
                Text(Scanner.bytes(store.junkTotal))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut, value: store.junkTotal)
                Group {
                    if store.selectedCount > 0 {
                        Text(L("已勾选 %@ 项，共 %@", "\(store.selectedCount)", "\(Scanner.bytes(store.selectedTotal))"))
                    } else if store.anyScanned && !store.isScanning {
                        Text(L("没有勾选要清理的项目"))
                    } else {
                        Text(" ")
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    store.requestClean(CategoryKind.allCases)
                } label: {
                    Label(store.cleaning ? L("正在清理…") : L("清理所选"), systemImage: "wand.and.stars")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent).tint(Color.toolula).controlSize(.large)
                .disabled(store.selectedCount == 0 || store.cleaning || store.isScanning)

                Button {
                    store.scan(CategoryKind.full)
                } label: {
                    Label(L("全面扫描"), systemImage: "arrow.clockwise").frame(minWidth: 140)
                }
                .controlSize(.large)
                .disabled(store.isScanning)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color.toolula.opacity(0.10), Color.toolula.opacity(0.03)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.toolula.opacity(0.18)))
    }

    var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            ForEach(CategoryKind.allCases) { k in
                CategoryCard(kind: k, state: store.state(k)) { store.section = .category(k) }
            }
            HomeCard(icon: "xmark.app", title: L("卸载应用"), desc: L("连同设置、缓存和数据一起删干净，也能清理已删除应用的残留")) {
                store.section = .uninstall
            } trailing: {
                if un.apps.isEmpty { Text(L("打开查看")).font(.callout).foregroundStyle(.tertiary) }
                else { Text(L("%@ 个应用", "\(un.apps.count)")).font(.headline).monospacedDigit() }
            }
        }
    }

    var historyBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("清理记录")).font(.headline)
                Spacer()
                if store.totalCleaned > 0 {
                    Text(L("累计 %@", "\(Scanner.bytes(store.totalCleaned))")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.history.isEmpty {
                Text(L("还没有清理过")).foregroundStyle(.secondary)
            }
            ForEach(store.history.prefix(4)) { r in
                HStack {
                    Image(systemName: "checkmark.circle").foregroundStyle(Color.toolula)
                    Text(r.kinds.joined(separator: L("、"))).lineLimit(1)
                    Spacer()
                    Text(Scanner.bytes(r.bytes)).monospacedDigit()
                    Text(r.date, style: .date).font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var safetyBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("安全说明")).font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                bullet(L("只清理你用户目录里的缓存和垃圾，不碰系统文件"))
                bullet(L("默认移到废纸篓，后悔了还能拿回来"))
                bullet(L("正在运行的应用和浏览器会自动跳过"))
                bullet(L("下载和大文件是你自己的文件，默认不勾选"))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func bullet(_ s: String) -> some View {
        Label { Text(s).font(.callout).foregroundStyle(.secondary) } icon: {
            Image(systemName: "checkmark.shield").foregroundStyle(Color.toolula)
        }
    }
}

/// 主页上的卡片 (图标 + 标题 + 说明 + 右侧信息)
struct HomeCard<Trailing: View>: View {
    let icon: String
    let title: String
    let desc: String
    let action: () -> Void
    @ViewBuilder let trailing: () -> Trailing
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.toolula)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.toolula.opacity(0.13)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(desc).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)   // 其他语言的说明更长
                }
                Spacer(minLength: 8)
                trailing()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(hover ? 0.07 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(hover ? 0.12 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// 主页上的类别卡片
struct CategoryCard: View {
    let kind: CategoryKind
    let state: CategoryState
    let action: () -> Void

    var body: some View {
        HomeCard(icon: kind.icon, title: kind.longTitle, desc: kind.desc, action: action) { trailing }
    }

    @ViewBuilder var trailing: some View {
        if state.scanning {
            ProgressView().controlSize(.small)
        } else if state.error != nil {
            Image(systemName: "lock").foregroundStyle(.orange)
        } else if state.scanned {
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.total > 0 ? Scanner.bytes(state.total) : L("很干净"))
                    .font(.headline).monospacedDigit()
                    .foregroundStyle(state.total > 0 ? Color.primary : Color.toolula)
                if state.total > 0, state.selectedSize != state.total {
                    Text(state.selectedSize == 0 ? L("未勾选") : L("已选 %@", "\(Scanner.bytes(state.selectedSize))")).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        } else {
            Text(L("未扫描")).font(.callout).foregroundStyle(.tertiary)
        }
    }
}
