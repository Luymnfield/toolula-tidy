import AppKit
import SwiftUI

/// 重复文件: 一组一组列出内容完全一样的文件
struct DuplicatesView: View {
    @EnvironmentObject var dup: DuplicateStore

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(icon: "doc.on.doc", title: L("重复文件"), desc: L("内容完全一样的文件。每组留下一份，其余移到废纸篓。")) {
                BigNumber(value: dup.scanned ? Scanner.bytes(dup.wasted) : "—",
                          sub: dup.scanned ? L("%@ 组重复", "\(dup.groups.count)") : " ")
            } bar: {
                Label(L("只找个人文件夹里你自己的文件（不含资源库、隐藏文件夹和照片图库）。每组默认留下最早的那份，开发项目里的文件默认不勾选。"), systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Picker(L("大于"), selection: $dup.minSizeMB) {
                    Text("1 MB").tag(1); Text("10 MB").tag(10); Text("100 MB").tag(100)
                }
                .fixedSize()
                Button { dup.scan() } label: { Label(dup.scanned ? L("重新查找") : L("开始查找"), systemImage: "arrow.clockwise") }
                    .disabled(dup.scanning)
            }
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !dup.groups.isEmpty { footer }
        }
        .confirmationDialog(L("把重复的文件移到废纸篓？"), isPresented: $dup.pendingClean) {
            Button(L("移到废纸篓"), role: .destructive) { dup.clean() }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("共 %@ 个文件，%@。每组都会留下一份，需要时可以从废纸篓放回去。", "\(dup.selectedFiles.count)", "\(Scanner.bytes(dup.selectedSize))"))
        }
    }

    @ViewBuilder var content: some View {
        if dup.scanning {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(L("正在比较文件内容，文件多时需要一两分钟…")).foregroundStyle(.secondary)
            }
        } else if !dup.scanned {
            VStack(spacing: 18) {
                CenterNote(icon: "doc.on.doc", title: L("查找重复文件"), text: L("先按大小筛选，再逐字节比较内容，只有完全一样的才算重复。"))
                Button { dup.scan() } label: { Label(L("开始查找"), systemImage: "magnifyingglass").frame(minWidth: 140) }
                    .buttonStyle(.borderedProminent).tint(Color.toolula).controlSize(.large)
                    .accessibilityIdentifier("dup-scan")
            }
        } else if dup.groups.isEmpty {
            CenterNote(icon: "checkmark.seal.fill", title: L("很干净"), text: L("没有找到重复的文件"))
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(dup.groups) { g in GroupCard(group: g) }
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
                .overlayScrollers()
            }
            .opacity(dup.cleaning ? 0.5 : 1)
        }
    }

    var footer: some View {
        HStack(spacing: 12) {
            Button(L("每组只留一份")) { dup.selectAllButOne() }
            Button(L("全不选")) { dup.selectNone() }
            Text(L("已选 %@ 个 · %@", "\(dup.selectedFiles.count)", "\(Scanner.bytes(dup.selectedSize))"))
                .foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Text(L("移到废纸篓")).font(.caption).foregroundStyle(.tertiary)
            Button { dup.pendingClean = true } label: {
                Label(dup.cleaning ? L("正在清理…") : L("清理所选"), systemImage: "wand.and.stars").frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent).tint(Color.toolula).controlSize(.large)
            .disabled(dup.selectedFiles.isEmpty || dup.cleaning)
            .accessibilityIdentifier("dup-clean")
        }
        .padding(.horizontal, 28).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// 一组重复文件
struct GroupCard: View {
    let group: DupGroup
    @EnvironmentObject var dup: DuplicateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: IconCache.icon(group.files[0].url.path)).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.files[0].url.lastPathComponent).font(.headline).lineLimit(1)
                    Text(L("%@ 份，每份 %@", "\(group.files.count)", "\(Scanner.bytes(group.size))")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(L("可腾出 %@", "\(Scanner.bytes(group.wasted))")).font(.callout.weight(.medium)).monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            ForEach(group.files) { f in FileRow(groupID: group.id, file: f) }
        }
        .padding(.bottom, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06)))
    }
}

struct FileRow: View {
    let groupID: String
    let file: DupFile
    @EnvironmentObject var dup: DuplicateStore
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { file.selected }, set: { _ in dup.toggle(groupID, file.id) }))
                .toggleStyle(.checkbox).labelsHidden()
            Text(Scanner.short(file.url.deletingLastPathComponent())).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(file.selected ? Color.primary : Color.secondary)
            Spacer(minLength: 8)
            Text(file.created, style: .date).font(.caption).foregroundStyle(.tertiary)
            if file.inProject { Badge(text: L("在开发项目里")) }
            if !file.selected { Badge(text: L("保留"), color: .toolula) }
            Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help(L("在访达中显示")).opacity(hover ? 1 : 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hover ? 0.05 : 0)))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { dup.toggle(groupID, file.id) }
        .onHover { hover = $0 }
    }
}
