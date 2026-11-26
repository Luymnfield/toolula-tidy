import SwiftUI

/// 「清理」页面: 左边是所有清理类别, 右边是选中类别的详情
struct CleanView: View {
    let kind: CategoryKind
    @EnvironmentObject var store: CleanerStore

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 240)
            Divider()
            CategoryView(kind: kind).id(kind)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var list: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(CategoryKind.allCases) { k in
                        Button { store.section = .category(k) } label: {
                            CategoryListRow(kind: k, state: store.state(k), selected: k == kind)
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .accessibilityLabel(k.longTitle)
                        .accessibilityIdentifier("cat-" + k.rawValue)
                    }
                }
                .padding(8)
                .overlayScrollers()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("可清理")).foregroundStyle(.secondary)
                    Spacer()
                    Text(Scanner.bytes(store.junkTotal)).font(.headline).monospacedDigit()
                }
                Button { store.scan(CategoryKind.full) } label: {
                    Label(L("全面扫描"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .disabled(store.isScanning)
            }
            .font(.callout)
            .padding(14)
            .overlay(alignment: .top) { Divider() }
        }
        .background(Color.primary.opacity(0.02))
    }
}

/// 清理类别列表里的一行: 图标 + 名字 + 大小
struct CategoryListRow: View {
    let kind: CategoryKind
    let state: CategoryState
    let selected: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(selected ? Color.toolula : Color.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.toolula.opacity(selected ? 0.16 : 0)))
            Text(kind.longTitle).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.toolula.opacity(0.14) : (hover ? Color.primary.opacity(0.05) : .clear)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    @ViewBuilder var trailing: some View {
        if state.scanning {
            ProgressView().controlSize(.mini)
        } else if state.error != nil {
            Image(systemName: "lock").font(.caption).foregroundStyle(.orange)
        } else if !state.scanned {
            Text(L("未扫描")).font(.caption).foregroundStyle(.tertiary)
        } else {
            Text(state.total > 0 ? Scanner.bytes(state.total) : L("很干净")).font(.callout).monospacedDigit()
                .foregroundStyle(state.total > 0 ? Color.secondary : Color.toolula)
        }
    }
}
