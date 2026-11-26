import AppKit
import SwiftUI

/// 空间地图: 方块越大占的空间越多, 点文件夹进去看
struct DiskMapView: View {
    @EnvironmentObject var map: DiskMapStore
    @ObservedObject var info = SystemInfo.shared
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(icon: "square.grid.2x2", title: L("空间地图"), desc: L("方块越大，占的空间越多。点文件夹进去看，右键可以在访达中显示。")) {
                BigNumber(value: map.nodes.isEmpty && map.loading ? "—" : Scanner.bytes(map.total),
                          sub: info.systemDisk.map { L("硬盘还剩 %@", "\(SystemInfo.size($0.free))") } ?? " ")
            } bar: {
                breadcrumb
                Spacer(minLength: 12)
                Button { map.refresh() } label: { Label(L("重新计算"), systemImage: "arrow.clockwise") }.disabled(map.loading)
            }
            Divider()
            HStack(spacing: 0) {
                treemap.padding(14)
                Divider()
                list.frame(width: 290)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if map.loading {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large)
                        Text(L("正在计算大小…")).foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .onAppear { map.start() }
        .confirmationDialog(map.pendingTrash.map { L("把「%@」移到废纸篓？", "\($0.name)") } ?? "",
                            isPresented: Binding(get: { map.pendingTrash != nil }, set: { if !$0 { map.pendingTrash = nil } }),
                            presenting: map.pendingTrash) { n in
            Button(L("移到废纸篓"), role: .destructive) { map.trash(n) }
            Button(L("取消"), role: .cancel) {}
        } message: { n in
            Text(L("%@，需要时可以从废纸篓放回去。", "\(Scanner.bytes(n.size))"))
        }
    }

    /// 个人文件夹 › 文稿 › …
    var breadcrumb: some View {
        HStack(spacing: 4) {
            ForEach(Array(map.trail.enumerated()), id: \.offset) { i, url in
                if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                Button(i == 0 ? L("个人文件夹") : FileManager.default.displayName(atPath: url.path)) { map.back(to: i) }
                    .buttonStyle(.borderless)
                    .font(.callout.weight(i == map.trail.count - 1 ? .semibold : .regular))
                    .foregroundStyle(i == map.trail.count - 1 ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .disabled(i == map.trail.count - 1)
            }
        }
    }

    var treemap: some View {
        let shown = DiskMap.forMap(map.nodes)
        return GeometryReader { geo in
            let rects = DiskMap.layout(shown.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, n in
                    Tile(node: n, color: tileColor(n, i), hovered: hovered == n.id, total: map.total)
                        .frame(width: max(0, rects[i].width - 3), height: max(0, rects[i].height - 3))
                        .offset(x: rects[i].minX, y: rects[i].minY)
                        .onHover { hovered = $0 ? n.id : (hovered == n.id ? nil : hovered) }
                        .onTapGesture { map.open(n) }
                        .contextMenu { menu(n) }
                }
            }
        }
    }

    var list: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(map.nodes.prefix(200)) { n in
                    Button { map.open(n) } label: {
                        HStack(spacing: 8) {
                            Image(nsImage: IconCache.icon(n.url.path)).resizable().frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(n.name).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 4)
                                    Text(Scanner.bytes(n.size)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                                }
                                GeometryReader { g in
                                    Capsule().fill(Color.toolula.opacity(0.7))
                                        .frame(width: max(2, g.size.width * CGFloat(Double(n.size) / Double(max(map.total, 1)))))
                                }
                                .frame(height: 3)
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary).opacity(n.isDir ? 1 : 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovered == n.id ? 0.07 : 0)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .onHover { hovered = $0 ? n.id : (hovered == n.id ? nil : hovered) }
                    .contextMenu { menu(n) }
                    .accessibilityIdentifier("map-row-" + n.url.lastPathComponent)
                }
            }
            .padding(8)
            .overlayScrollers()
        }
        .background(Color.primary.opacity(0.02))
    }

    @ViewBuilder func menu(_ n: MapNode) -> some View {
        if n.others == 0 {
            if n.isDir { Button(L("打开")) { map.open(n) } }
            Button(L("在访达中显示")) { NSWorkspace.shared.activateFileViewerSelecting([n.url]) }
            if map.canTrash(n) {
                Divider()
                Button(L("移到废纸篓…")) { map.pendingTrash = n }
            }
        }
    }

    static let palette: [Color] = [.toolula, .blue, .purple, .orange, .pink, .teal, .indigo, .yellow, .mint, .cyan]
    func tileColor(_ n: MapNode, _ i: Int) -> Color {
        if n.others > 0 { return .gray.opacity(0.5) }
        if !n.isDir { return .gray }
        return Self.palette[i % Self.palette.count]
    }
}

/// 地图上的一块
struct Tile: View {
    let node: MapNode
    let color: Color
    let hovered: Bool
    let total: Int64

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(hovered ? 0.85 : 0.6))
                RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(hovered ? 0.7 : 0.15), lineWidth: hovered ? 2 : 1)
                if g.size.width > 56 && g.size.height > 30 {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            if node.isDir { Image(systemName: "folder.fill").font(.system(size: 10)) }
                            Text(node.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        }
                        if g.size.height > 46 {
                            Text(Scanner.bytes(node.size)).font(.system(size: 11)).monospacedDigit().opacity(0.9)
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1)
                    .padding(7)
                }
            }
        }
        .contentShape(Rectangle())
        .help("\(node.name) · \(Scanner.bytes(node.size)) · \(String(format: "%.1f%%", Double(node.size) / Double(max(total, 1)) * 100))")
        .accessibilityElement()
        .accessibilityLabel("\(node.name) \(Scanner.bytes(node.size))")
        .accessibilityIdentifier("map-tile-" + node.url.lastPathComponent)
        .accessibilityAddTraits(.isButton)
    }
}
