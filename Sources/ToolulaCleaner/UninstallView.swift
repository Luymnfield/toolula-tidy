import AppKit
import SwiftUI

/// 卸载应用: 左边应用列表, 右边应用详情 (应用本身 + 找到的残留文件)
struct UninstallView: View {
    @EnvironmentObject var un: UninstallStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 320)
            Divider()
            Group {
                switch un.tab {
                case .apps:
                    if let app = un.selected { AppDetail(app: app).id(app.id) } else { placeholder }
                case .orphans: OrphanPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { un.loadIfNeeded() }
        .confirmationDialog(un.pendingUninstall.map { L("卸载「%@」？", "\($0.name)") } ?? "",
                            isPresented: Binding(get: { un.pendingUninstall != nil }, set: { if !$0 { un.pendingUninstall = nil } }),
                            presenting: un.pendingUninstall) { app in
            Button(L("卸载"), role: .destructive) { un.uninstall(app) }
            Button(L("取消"), role: .cancel) {}
        } message: { app in
            let n = un.leftovers.filter(\.selected).count
            Text(L("应用和 %@ 个相关文件（共 %@）会移到废纸篓，需要时可以从废纸篓放回去。", "\(n)", "\(Scanner.bytes((app.size ?? 0) + un.leftoverSelectedSize))"))
        }
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            Picker("", selection: $un.tab) {
                Text(L("已安装 %@", "\(un.apps.count)")).tag(UninstallStore.Tab.apps)
                Text(L("已删除应用的残留")).tag(UninstallStore.Tab.orphans)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            if un.tab == .apps {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(L("搜索应用"), text: $un.search).textFieldStyle(.plain)
                        if !un.search.isEmpty {
                            Button { un.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                    Menu {
                        Picker(L("排序"), selection: $un.sort) {
                            ForEach(UninstallStore.SortKey.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                        Divider()
                        Button(L("刷新列表")) { un.load() }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help(L("排序"))
                }
                .padding(.horizontal, 14).padding(.bottom, 8)

                if un.loading {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(un.visibleApps) { app in
                                AppRow(app: app, selected: app.id == un.selectedID, running: un.running.contains(app.bundleID))
                                    .equatable()
                                    .onTapGesture { un.select(app) }
                            }
                        }
                        .padding(.horizontal, 8).padding(.bottom, 8)
                        .overlayScrollers()
                    }
                }
                HStack {
                    Text(L("%@ 个应用 · %@", "\(un.apps.count)", "\(un.sizing ? L("正在计算大小…") : Scanner.bytes(un.appsTotal))"))
                    Spacer()
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(alignment: .top) { Divider() }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label(L("应用拖进废纸篓删掉后，它的设置、缓存和数据还会留在资源库里。"), systemImage: "info.circle")
                    Label(L("这里列出的文件，名字是某个应用的 ID，但电脑上已经找不到这个应用了。"), systemImage: "magnifyingglass")
                    Label(L("苹果自带的和你还装着的同一厂商的应用都已经排除。默认都不勾选，请看清再选。"), systemImage: "checkmark.shield")
                }
                .font(.callout).foregroundStyle(.secondary)
                .padding(16)
                Spacer()
            }
        }
        .background(Color.primary.opacity(0.02))
    }

    var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.app").font(.system(size: 48)).foregroundStyle(Color.toolula)
            Text(L("选择左边的应用")).font(.title2.weight(.semibold))
            Text(L("会找出它在资源库里留下的设置、缓存和数据，一起移到废纸篓")).foregroundStyle(.secondary)
        }
    }
}

struct AppRow: View, Equatable {
    let app: AppEntry
    let selected: Bool
    let running: Bool
    @State private var hover = false

    static func == (a: AppRow, b: AppRow) -> Bool { a.app == b.app && a.selected == b.selected && a.running == b.running }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.icon(app.url.path)).resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).lineLimit(1)
                Text(usedText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if running { Circle().fill(.green).frame(width: 6, height: 6).help(L("正在运行")) }
            Text(app.size.map(Scanner.bytes) ?? "…").font(.callout).monospacedDigit()
                .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.toolula.opacity(0.16) : (hover ? Color.primary.opacity(0.05) : .clear)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    var usedText: String {
        guard let d = app.lastUsed else { return L("没有使用记录") }
        let days = Int(Date().timeIntervalSince(d) / 86400)
        switch days {
        case ..<1: return L("今天用过")
        case ..<30: return L("%@ 天前用过", "\(days)")
        case ..<365: return L("%@ 个月前用过", "\(days / 30)")
        default: return L("%@ 年多没用过", "\(days / 365)")
        }
    }
}

struct AppDetail: View {
    let app: AppEntry
    @EnvironmentObject var un: UninstallStore
    var running: Bool { un.running.contains(app.bundleID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if running { runningBanner.padding(.horizontal, 28).padding(.bottom, 12) }
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    if un.leftovers.contains(where: { $0.detail.hasPrefix(L("应用数据")) || $0.detail.hasPrefix(L("沙盒数据")) }) {
                        Label(L("「应用数据」「沙盒数据」里可能有你的文档、书签或登录信息。以后还想用这些数据，就取消勾选。"),
                              systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.bottom, 6)
                    }
                    appBundleRow
                    if un.leftoversLoading {
                        HStack { ProgressView().controlSize(.small); Text(L("正在查找相关文件…")).foregroundStyle(.secondary) }
                            .padding(16)
                    } else if un.leftovers.isEmpty {
                        Text(L("没有找到它在资源库里留下的文件")).foregroundStyle(.secondary).padding(16)
                    }
                    ForEach(un.leftovers) { item in
                        ItemRow(item: item, toggle: { un.toggleLeftover(item.id) }).equatable()
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .overlayScrollers()
            }
            footer
        }
    }

    var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: IconCache.icon(app.url.path)).resizable().frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.name).font(.system(size: 26, weight: .bold)).lineLimit(1)
                    if app.isAppStore {
                        Text("App Store").font(.caption.weight(.medium)).foregroundStyle(.blue)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.12)))
                    }
                }
                Text([app.version.isEmpty ? nil : L("版本 %@", "\(app.version)"), app.bundleID].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Scanner.bytes((app.size ?? 0) + un.leftoverSelectedSize))
                    .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(L("卸载后可腾出")).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
    }

    var runningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(L("「%@」正在运行，卸载前需要先退出。", "\(app.name)"))
            Spacer()
            Button(L("退出应用")) { un.quit(app) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
    }

    var appBundleRow: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: .constant(true)).toggleStyle(.checkbox).labelsHidden().disabled(true)
            Image(nsImage: IconCache.icon(app.url.path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(app.name).app")
                Text(L("应用本身 · %@", "\(Scanner.short(app.url.deletingLastPathComponent()))")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { NSWorkspace.shared.activateFileViewerSelecting([app.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help(L("在访达中显示"))
            Text(app.size.map(Scanner.bytes) ?? "…").font(.body.weight(.medium)).monospacedDigit()
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    var footer: some View {
        HStack(spacing: 12) {
            Text(L("应用 + %@ 个相关文件", "\(un.leftovers.filter(\.selected).count)")).foregroundStyle(.secondary)
            Spacer()
            Text(L("移到废纸篓")).font(.caption).foregroundStyle(.tertiary)
            Button {
                un.pendingUninstall = app
            } label: {
                Label(un.busy ? L("正在卸载…") : L("卸载"), systemImage: "trash").frame(minWidth: 90)
            }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            .disabled(running || un.busy || un.leftoversLoading)
        }
        .padding(.horizontal, 28).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// 已删除应用的残留
struct OrphanPane: View {
    @EnvironmentObject var un: UninstallStore
    var st: CategoryState { un.orphans }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 24, weight: .medium)).foregroundStyle(Color.toolula)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Color.toolula.opacity(0.13)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("已删除应用的残留")).font(.system(size: 26, weight: .bold))
                    Text(L("应用删掉了，它的设置和数据还留在资源库里")).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(st.scanned ? Scanner.bytes(st.total) : "—").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(st.scanned ? L("共 %@ 项", "\(st.items.count)") : " ").font(.callout).foregroundStyle(.secondary)
                }
                Button { un.scanOrphans() } label: { Label(L("重新扫描"), systemImage: "arrow.clockwise") }
                    .disabled(st.scanning)
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
            Divider()
            Group {
                if st.scanning && st.items.isEmpty {
                    VStack(spacing: 12) { ProgressView().controlSize(.large); Text(L("正在查找…")).foregroundStyle(.secondary) }
                } else if st.scanned && st.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(Color.toolula)
                        Text(L("没有找到残留")).font(.title2.weight(.semibold))
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(st.items) { item in
                                ItemRow(item: item, toggle: { un.toggleOrphan(item.id) }).equatable()
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .overlayScrollers()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !st.items.isEmpty {
                HStack(spacing: 12) {
                    let allOn = st.selectedCount == st.items.count
                    Button(allOn ? L("全不选") : L("全选")) { un.selectAllOrphans(!allOn) }
                    Text(L("已选 %@ 项 · %@", "\(st.selectedCount)", "\(Scanner.bytes(st.selectedSize))")).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Text(L("移到废纸篓")).font(.caption).foregroundStyle(.tertiary)
                    Button { un.pendingOrphanClean = true } label: {
                        Label(un.busy ? L("正在清理…") : L("清理所选"), systemImage: "wand.and.stars").frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.toolula).controlSize(.large)
                    .disabled(st.selectedCount == 0 || un.busy)
                }
                .padding(.horizontal, 28).padding(.vertical, 12)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
        .onAppear { if !st.scanned { un.scanOrphans() } }
        .confirmationDialog(L("清理残留文件？"), isPresented: $un.pendingOrphanClean) {
            Button(L("清理"), role: .destructive) { un.cleanOrphans() }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("%@ 个文件（%@）会移到废纸篓。", "\(st.selectedCount)", "\(Scanner.bytes(st.selectedSize))"))
        }
    }
}
