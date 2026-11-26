import AppKit
import SwiftUI

/// 一个类别的详情页: 列出每一项, 勾选后清理
struct CategoryView: View {
    let kind: CategoryKind
    @EnvironmentObject var store: CleanerStore
    var st: CategoryState { store.state(kind) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !st.items.isEmpty { footer }
        }
        .onAppear {
            if !st.scanned && !st.scanning { store.scan([kind]) }
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: kind.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.toolula)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Color.toolula.opacity(0.13)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.longTitle).font(.system(size: 26, weight: .bold))
                    Text(kind.desc).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(st.scanned ? Scanner.bytes(st.total) : "—")
                        .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(st.scanned ? L("共 %@ 项", "\(st.items.count)") : " ").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Label(kind.notice, systemImage: kind == .trash || kind.isUserData ? "exclamationmark.triangle" : "info.circle")
                    .font(.callout)
                    .foregroundStyle(kind == .trash || kind.isUserData ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                options
                Button { store.scan([kind]) } label: { Label(L("重新扫描"), systemImage: "arrow.clockwise") }
                    .disabled(st.scanning)
            }
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
    }

    @ViewBuilder var options: some View {
        if kind == .largeFiles {
            Picker(L("大于"), selection: $store.largeThresholdMB) {
                Text("100 MB").tag(100); Text("500 MB").tag(500); Text("1 GB").tag(1000); Text("5 GB").tag(5000)
            }
            .fixedSize()
        } else if kind == .downloads {
            Picker(L("超过"), selection: $store.downloadsDays) {
                Text(L("30 天")).tag(30); Text(L("90 天")).tag(90); Text(L("半年")).tag(180); Text(L("1 年")).tag(365)
            }
            .fixedSize()
        }
    }

    @ViewBuilder var content: some View {
        if st.scanning && st.items.isEmpty {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(kind == .largeFiles ? L("正在查找大文件，文件多时需要一两分钟…") : L("正在扫描…")).foregroundStyle(.secondary)
            }
        } else if let err = st.error {
            VStack(spacing: 14) {
                Image(systemName: "lock.shield").font(.system(size: 42)).foregroundStyle(.orange)
                Text(err).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
                HStack {
                    Button(L("去开启")) { store.openFullDiskAccessSettings() }.buttonStyle(.borderedProminent).tint(.orange)
                    Button(L("重新检查")) { store.scan([kind]) }
                }
            }
        } else if st.scanned && st.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(Color.toolula)
                Text(L("很干净")).font(.title2.weight(.semibold))
                Text(L("这里没有需要清理的东西")).foregroundStyle(.secondary)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(st.items) { item in
                        ItemRow(item: item, toggle: { store.toggle(kind, item.id) }).equatable()
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .overlayScrollers()
            }
            .opacity(st.scanning ? 0.5 : 1)
        }
    }

    var footer: some View {
        let allOn = st.selectedCount == st.items.count
        return HStack(spacing: 12) {
            Button(allOn ? L("全不选") : L("全选")) { store.selectAll(kind, !allOn) }
            Text(L("已选 %@ 项 · %@", "\(st.selectedCount)", "\(Scanner.bytes(st.selectedSize))"))
                .foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            if !store.permanent(kind) {
                Text(L("移到废纸篓")).font(.caption).foregroundStyle(.tertiary)
            }
            Button {
                store.requestClean([kind])
            } label: {
                Label(store.cleaning ? L("正在清理…") : (kind == .trash ? L("清空所选") : L("清理所选")),
                      systemImage: kind == .trash ? "trash" : "wand.and.stars")
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .tint(kind == .trash ? .red : Color.toolula)
            .controlSize(.large)
            .disabled(st.selectedCount == 0 || store.cleaning || st.scanning)
        }
        .padding(.horizontal, 28).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// 列表里的一行
struct ItemRow: View, Equatable {
    let item: CleanItem
    let toggle: () -> Void
    @State private var hover = false

    /// 只有这一行的数据变了才重绘 (勾选一项时其他几百行不动)
    static func == (a: ItemRow, b: ItemRow) -> Bool { a.item == b.item }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { item.selected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox).labelsHidden()
            Image(nsImage: IconCache.icon(item.iconPath ?? item.url.path))
                .resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let note = item.note {
                Text(note).font(.caption.weight(.medium)).foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(L("在访达中显示"))
            .opacity(hover ? 1 : 0)
            Text(Scanner.bytes(item.size))
                .font(.body.weight(.medium)).monospacedDigit()
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hover ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .onHover { hover = $0 }
    }
}

/// 文件图标缓存 (NSWorkspace 取图标比较慢, 滚动列表时不重复取)
enum IconCache {
    private static let cache: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 1000; return c }()
    static func icon(_ path: String) -> NSImage {
        if let i = cache.object(forKey: path as NSString) { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        i.size = NSSize(width: 32, height: 32)
        cache.setObject(i, forKey: path as NSString)
        return i
    }
}
