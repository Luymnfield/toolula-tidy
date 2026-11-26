import AppKit
import SwiftUI

/// 「查看详情」: 列出没能处理的项目和原因
struct FailureSheet: View {
    @EnvironmentObject var store: CleanerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill").font(.title2).foregroundStyle(.orange)
                Text(L("%@ 项没能处理", "\(store.failures.count)")).font(.title2.weight(.semibold))
            }
            Text(L("其他项目已经处理好了。下面这些被跳过了，原因写在每一项下面。"))
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.failures) { f in
                        HStack(spacing: 12) {
                            Image(nsImage: IconCache.icon(f.path)).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).lineLimit(1)
                                Text(Scanner.short(URL(fileURLWithPath: f.path))).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Text(f.reason).font(.caption).foregroundStyle(.orange)
                            }
                            Spacer()
                            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)]) } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .buttonStyle(.borderless).help(L("在访达中显示"))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    }
                }
                .overlayScrollers()
            }
            .frame(minHeight: 160, maxHeight: 360)
            HStack {
                if store.failures.contains(where: \.needsAccess) {
                    Button(L("打开「完全磁盘访问权限」设置…")) { store.openFullDiskAccessSettings() }
                }
                Spacer()
                Button(L("好")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}
