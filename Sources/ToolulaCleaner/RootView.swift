import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: CleanerStore
    @EnvironmentObject var un: UninstallStore
    @EnvironmentObject var dup: DuplicateStore
    @EnvironmentObject var startup: StartupStore
    @EnvironmentObject var map: DiskMapStore
    @ObservedObject var mem = MemoryMonitor.shared

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            Group {
                switch store.section {
                case .home: HomeView()
                case .category(let k): CleanView(kind: k)
                case .uninstall: UninstallView()
                case .startup: StartupView()
                case .duplicates: DuplicatesView()
                case .diskMap: DiskMapView()
                case .memory: MemoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .overlay(alignment: .bottom) {
            if let t = store.toast {
                HStack(spacing: 12) {
                    Label(t.text, systemImage: t.hasFailures ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    if t.hasFailures {
                        Button(L("查看详情")) { store.showFailures = true }.controlSize(.small)
                            .accessibilityIdentifier("toast-details")
                    }
                    if let id = t.undoID {
                        Button(L("撤销")) { store.undo(id) }.controlSize(.small).keyboardShortcut("z", modifiers: .command)
                            .accessibilityIdentifier("toast-undo")
                    }
                }
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { store.toast = nil }
            }
        }
        .sheet(isPresented: $store.showFailures) { FailureSheet() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { SettingsMenu() }
        }
        .navigationTitle("Toolula Tidy")
        .navigationSubtitle(subtitle)
        .confirmationDialog(L("确认清理？"), isPresented: Binding(get: { store.pendingClean != nil },
                                                          set: { if !$0 { store.pendingClean = nil } }),
                            presenting: store.pendingClean) { kinds in
            Button(kinds.contains { store.permanent($0) } ? L("清理（含永久删除）") : L("清理"), role: .destructive) { store.clean(kinds) }
            Button(L("取消"), role: .cancel) {}
        } message: { kinds in
            Text(store.confirmText(kinds))
        }
    }

    var isCleaning: Bool { if case .category = store.section { return true }; return false }

    var subtitle: String {
        if store.cleaning { return L("正在清理…") }
        if store.isScanning { return L("正在扫描…") }
        if store.anyScanned { return L("可清理 %@", "\(Scanner.bytes(store.junkTotal))") }
        return L("安全清理你的 Mac")
    }

    /// 左侧栏: 按窗口高度分几档, 保证底部总有东西, 不留空白
    ///   1. 完整的机器信息  2. 小的硬盘圆环  3. 按钮缩小 + 硬盘圆环  4. 按钮缩小, 不显示底部
    var rail: some View {
        ViewThatFits(in: .vertical) {
            railBody(compact: false, bottom: .full)
            railBody(compact: false, bottom: .medium)
            railBody(compact: false, bottom: .mini)
            railBody(compact: true, bottom: .medium)
            railBody(compact: true, bottom: .mini)
            railBody(compact: true, bottom: .none)
        }
        .frame(width: 86)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    enum RailBottom { case full, medium, mini, none }

    func railBody(compact: Bool, bottom: RailBottom) -> some View {
        VStack(spacing: compact ? 1 : 3) {
            Button { store.section = .home } label: {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: compact ? 40 : 46, height: compact ? 40 : 46)
                    .shadow(color: .black.opacity(store.section == .home ? 0.25 : 0.1), radius: store.section == .home ? 4 : 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help(L("概览"))
            .accessibilityLabel(L("概览"))
            .accessibilityIdentifier("rail-home")
            .padding(.top, compact ? 8 : 10).padding(.bottom, compact ? 3 : 6)

            RailButton(icon: "sparkles", title: L("清理"), selected: isCleaning,
                       sub: store.isScanning ? L("扫描中") : !store.anyScanned ? L("未扫描")
                            : store.junkTotal > 0 ? Scanner.bytes(store.junkTotal) : L("很干净"),
                       dimSub: !store.anyScanned || store.junkTotal == 0, compact: compact) {
                if !isCleaning { store.section = .category(store.lastCategory) }
            }
            RailButton(icon: "xmark.app", title: L("卸载"), selected: store.section == .uninstall,
                       sub: un.apps.isEmpty ? L("应用") : L("%@ 个", "\(un.apps.count)"), dimSub: un.apps.isEmpty, compact: compact) {
                store.section = .uninstall
            }
            RailButton(icon: "power", title: L("启动项"), selected: store.section == .startup,
                       sub: startup.loaded ? L("%@ 个开启", "\(startup.enabledCount)") : L("登录时"), dimSub: !startup.loaded,
                       compact: compact) { store.section = .startup }
            RailButton(icon: "doc.on.doc", title: L("重复项"), selected: store.section == .duplicates,
                       sub: dup.scanning ? L("扫描中") : !dup.scanned ? L("未扫描") : dup.wasted > 0 ? Scanner.bytes(dup.wasted) : L("很干净"),
                       dimSub: !dup.scanned || dup.wasted == 0, compact: compact) { store.section = .duplicates }
            RailButton(icon: "square.grid.2x2", title: L("空间"), selected: store.section == .diskMap,
                       sub: SystemInfo.shared.systemDisk.map { L("剩 %@", "\(SystemInfo.size($0.free))") }, dimSub: true,
                       compact: compact) { store.section = .diskMap }
            RailButton(icon: "memorychip", title: L("内存"), selected: store.section == .memory,
                       sub: L("压力%@", mem.snap.pressure.title), subColor: mem.snap.pressure == .normal ? nil : mem.snap.pressure.color,
                       compact: compact) { store.section = .memory }
            Spacer(minLength: 6)
            switch bottom {
            case .full:
                MachineBadge(compact: true).frame(width: 70).padding(.bottom, 10)
            case .medium:
                DiskRing(showChip: true).padding(.bottom, 10)
            case .mini:
                DiskRing().padding(.bottom, 10)
            case .none:
                EmptyView()
            }
        }
    }
}

/// 左侧栏底部的小硬盘圆环: 用了多少 + 还剩多少
struct DiskRing: View {
    @ObservedObject var info = SystemInfo.shared
    /// 上面再显示芯片和内存 (例如 "M3 Max · 96 GB")
    var showChip = false
    var body: some View {
        if let d = info.systemDisk {
            VStack(spacing: 3) {
                if showChip, !info.chip.isEmpty {
                    Image(systemName: info.machine.contains("Book") ? "laptopcomputer" : "desktopcomputer")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Text(info.chip.replacingOccurrences(of: "Apple ", with: "")).font(.system(size: 10, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(info.memory).font(.system(size: 9)).foregroundStyle(.secondary).padding(.bottom, 4)
                }
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
                    Circle().trim(from: 0, to: d.usedFraction)
                        .stroke(UsageBar(fraction: d.usedFraction).color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "internaldrive").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(width: 36, height: 36)
                Text(L("剩 %@", "\(SystemInfo.size(d.free))")).font(.system(size: 9.5, weight: .medium)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(.secondary)
            }
            .help(L("硬盘（%@）可用 %@ / 共 %@", "\(d.name)", "\(SystemInfo.size(d.free))", "\(SystemInfo.size(d.total))"))
        }
    }
}

/// 左侧栏按钮: 图标 + 名字 + 下面一行小字 (大小 / 数量)
struct RailButton: View {
    let icon: String
    let title: String
    let selected: Bool
    let sub: String?
    /// 小字用浅色 (未扫描 / 很干净)
    var dimSub = false
    /// 小字用特别的颜色 (例如内存压力偏高时的橙色)
    var subColor: Color? = nil
    var compact = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: compact ? 16 : 19, weight: selected ? .semibold : .regular))
                    .frame(height: compact ? 18 : 22)
                // 其他语言的词可能更长 (例如德文), 放不下时自动缩小字号
                Text(title).font(.system(size: compact ? 11 : 11.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text(sub ?? " ")
                    .font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(subColor ?? (selected ? Color.toolula : Color.secondary.opacity(dimSub ? 0.5 : 0.85)))
            }
            .frame(width: 70, height: compact ? 48 : 60)
            .foregroundStyle(selected ? Color.toolula : (hover ? Color.primary : Color.secondary))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.toolula.opacity(0.14) : (hover ? Color.primary.opacity(0.06) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(title)
        .accessibilityIdentifier("rail-" + icon)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// 右上角的设置菜单
struct SettingsMenu: View {
    @EnvironmentObject var store: CleanerStore
    @EnvironmentObject var un: UninstallStore
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system

    /// 「语言」后面总带上英文 Language, 看不懂当前语言的人也能找到
    var languageTitle: String {
        AppLanguage.resolved == "en" ? "Language" : L("语言") + " · Language"
    }

    var body: some View {
        Menu {
            Toggle(L("清理时直接删除（不经过废纸篓）"), isOn: $store.deleteDirectly)
            Text(L("下载和大文件永远只移到废纸篓"))
            Divider()
            Picker(L("外观"), selection: Binding(get: { appearance }, set: {
                appearance = $0
                AppAppearance.apply(AppAppearance(rawValue: $0) ?? .system)
            })) {
                ForEach(AppAppearance.allCases) { a in Label(a.title, systemImage: a.icon).tag(a.rawValue) }
            }
            Picker(selection: Binding(get: { language }, set: { code in
                AppLanguage.set(code)
                language = code
            })) {
                Text(L("跟随系统")).tag(AppLanguage.system)
                Divider()
                ForEach(AppLanguage.supported, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
            } label: {
                Label(languageTitle, systemImage: "globe")
            }
            Divider()
            Button(L("打开「完全磁盘访问权限」设置…")) { store.openFullDiskAccessSettings() }
        } label: {
            Label(L("设置"), systemImage: "gearshape")
        }
        .focusEffectDisabled()   // 启动时不要显示蓝色的焦点框
        .help(L("设置"))
    }
}

/// 没有完全磁盘访问权限时的提示条
struct AccessBanner: View {
    @EnvironmentObject var store: CleanerStore
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("开启「完全磁盘访问权限」")).font(.headline)
                Text(L("开启后才能查看和清空废纸篓，并清理部分受保护的缓存。")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("重新检查")) { store.scan([.trash]) }
            Button(L("去开启")) { store.openFullDiskAccessSettings() }.buttonStyle(.borderedProminent).tint(.orange)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.25)))
    }
}
