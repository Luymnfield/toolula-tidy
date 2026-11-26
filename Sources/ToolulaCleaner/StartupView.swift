import AppKit
import SwiftUI

/// 启动项: 登录 / 开机时自动运行的后台程序, 可以开关
struct StartupView: View {
    @EnvironmentObject var st: StartupStore

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(icon: "power", title: L("启动项"), desc: L("登录或开机时自动运行的后台程序。关掉不用的，登录更快，也更省内存。")) {
                BigNumber(value: st.loaded ? "\(st.enabledCount)" : "—", sub: st.loaded ? L("个开启中") : " ")
            } bar: {
                Label(L("关掉只是不再自动运行，不删除任何东西，随时可以再打开。"), systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button(L("打开「登录项」设置…")) { st.openLoginItemsSettings() }
                Button { st.load() } label: { Label(L("刷新"), systemImage: "arrow.clockwise") }.disabled(st.loading)
            }
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { st.loadIfNeeded() }
        .confirmationDialog(st.pendingRemove.map { L("删除「%@」的启动项？", "\($0.name)") } ?? "",
                            isPresented: Binding(get: { st.pendingRemove != nil }, set: { if !$0 { st.pendingRemove = nil } }),
                            presenting: st.pendingRemove) { item in
            Button(L("移到废纸篓"), role: .destructive) { st.remove(item) }
            Button(L("取消"), role: .cancel) {}
        } message: { item in
            Text(L("它要运行的程序已经不存在了。启动项文件会移到废纸篓，需要时可以放回去。"))
        }
    }

    @ViewBuilder var content: some View {
        if st.loading && st.items.isEmpty {
            ProgressView().controlSize(.large)
        } else if st.items.isEmpty {
            CenterNote(icon: "checkmark.seal.fill", title: L("很干净"), text: L("没有找到自动启动的后台程序"))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(StartupItem.Scope.allCases, id: \.self) { scope in
                        let list = st.items.filter { $0.scope == scope }
                        if !list.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(scope.title).font(.headline)
                                    Text("\(list.count)").font(.callout).foregroundStyle(.secondary)
                                }
                                Text(scope.note).font(.caption).foregroundStyle(.secondary).padding(.bottom, 4)
                                ForEach(list) { StartupRow(item: $0) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 16)
                .overlayScrollers()
            }
        }
    }
}

struct StartupRow: View {
    let item: StartupItem
    @EnvironmentObject var st: StartupStore
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let app = item.app, FileManager.default.fileExists(atPath: app.path) { Image(nsImage: IconCache.icon(app.path)).resizable() }
                else { Image(systemName: "gearshape.2").font(.system(size: 18)).foregroundStyle(.secondary) }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                Text(item.program.map { "\(item.label) · \($0)" } ?? item.label)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 10)
            if item.programMissing { Badge(text: L("程序已不存在")) }
            if item.running { Badge(text: L("运行中"), color: .green) }
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.plist]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help(L("在访达中显示")).opacity(hover ? 1 : 0)
            if item.canRemove && item.programMissing {
                Button { st.pendingRemove = item } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help(L("删除这个启动项"))
                    .accessibilityIdentifier("startup-remove-" + item.label)
            }
            if st.busy.contains(item.id) {
                ProgressView().controlSize(.small).frame(width: 40)
            } else if item.canToggle {
                Toggle("", isOn: Binding(get: { !item.disabled }, set: { st.setEnabled(item, $0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    .help(item.disabled ? L("已关掉，点一下打开") : L("开启中，点一下关掉"))
                    .accessibilityIdentifier("startup-toggle-" + item.label)
            } else {
                Image(systemName: "lock").foregroundStyle(.tertiary).frame(width: 40).help(L("需要管理员权限"))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hover ? 0.06 : 0.03)))
        .opacity(item.disabled ? 0.6 : 1)
        .onHover { hover = $0 }
    }
}
